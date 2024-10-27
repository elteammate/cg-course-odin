package main

import "core:fmt"
import "core:strings"
import "core:c"
import "core:os"
import "core:mem"
import "core:slice"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "core:reflect"
import "core:testing"
import "core:c/libc"
import timelib "core:time"

import gl "vendor:OpenGL"
import sdl "vendor:sdl2"
import stb_img "vendor:stb/image"

import common "../common"


application :: proc() -> Maybe(string) {
    if (sdl.Init(sdl.INIT_VIDEO) != 0) do return common.sdl2_panic("sdl.Init")
    defer sdl.Quit()

    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_MAJOR_VERSION, 3)
    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_MINOR_VERSION, 3)
    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_PROFILE_MASK, c.int(sdl.GLprofile.CORE))
    sdl.GL_SetAttribute(sdl.GLattr.DOUBLEBUFFER, 1)
    sdl.GL_SetAttribute(sdl.GLattr.RED_SIZE, 8)
    sdl.GL_SetAttribute(sdl.GLattr.GREEN_SIZE, 8)
    sdl.GL_SetAttribute(sdl.GLattr.BLUE_SIZE, 8)
    sdl.GL_SetAttribute(sdl.GLattr.DEPTH_SIZE, 24)

    window := sdl.CreateWindow(
        "Graphics course practice 8",
        sdl.WINDOWPOS_CENTERED,
        sdl.WINDOWPOS_CENTERED,
        800, 600,
        sdl.WINDOW_OPENGL | sdl.WINDOW_RESIZABLE,
    )
    if window == nil do return common.sdl2_panic("sdl.CreateWindow")
    defer sdl.DestroyWindow(window)

    dimensions: [2]i32
    sdl.GetWindowSize(window, &dimensions.x, &dimensions.y)

    ctx := sdl.GL_CreateContext(window)
    if ctx == nil do return common.sdl2_panic("sdl.GL_CreateContext")
    defer sdl.GL_DeleteContext(ctx)

    sdl.GL_SetSwapInterval(1)

    gl.load_up_to(3, 3, sdl.gl_set_proc_address)

    gl.ClearColor(0.8, 0.8, 1.0, 0.0)
    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)

    scene: struct {
        using gpu_data: common.Gpu_Obj_Data,
        program: u32,
        uniforms: struct {
            model, view, projection, camera_position, albedo, sun_direction, sun_color: i32
        }
    }

    scene_shaders := common.compile_shader_program({
        vertex_source = #load("shader.vert", string),
        fragment_source = #load("shader.frag", string),
    }) or_return
    defer common.destroy_shader_program(scene_shaders)
    scene.program = scene_shaders.program
    common.get_uniform_locations(scene.program, &scene.uniforms, ignore_missing = true)

    scene_data := common.load_obj_file("practice8/buddha.obj") or_return
    defer common.destory_obj_data(scene_data)
    scene.gpu_data = common.send_obj_to_gpu(scene_data)
    defer common.destroy_gpu_obj_data(scene)

    free_all(context.temp_allocator)

    last_frame_start := timelib.now()
    time: f32 = 0.0

    camera_distance: f32 = 1.5
    camera_angle: f32 = math.PI

    button_down: map[sdl.Keycode]bool
    defer delete(button_down)

    running := true
    for running {
        for event: sdl.Event; sdl.PollEvent(&event); {
            #partial switch event.type {
                case .QUIT:
                    running = false
                case .WINDOWEVENT:
                    #partial switch event.window.event {
                        case .RESIZED:
                            dimensions.x = event.window.data1
                            dimensions.y = event.window.data2
                    }
                case .KEYDOWN:
                    button_down[event.key.keysym.sym] = true
                case .KEYUP:
                    button_down[event.key.keysym.sym] = false
            }
        }

        current_time := timelib.now()
        defer last_frame_start = current_time
        dt := cast(f32)timelib.duration_seconds(timelib.diff(last_frame_start, current_time))
        time += dt

        SPEED :: 4.0
        ROTATION_SPEED :: 2.0
        if button_down[.UP] || button_down[.W] do camera_distance -= SPEED * dt
        if button_down[.DOWN] || button_down[.S] do camera_distance += SPEED * dt
        if button_down[.LEFT] || button_down[.A] do camera_angle += ROTATION_SPEED * dt
        if button_down[.RIGHT] || button_down[.D] do camera_angle -= ROTATION_SPEED * dt

        gl.Viewport(0, 0, dimensions.x, dimensions.y)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        near: f32 = 0.1
        far: f32 = 100.0

        model := linalg.MATRIX4F32_IDENTITY

        view :=
            linalg.matrix4_translate_f32({0, 0, -camera_distance}) * 
            linalg.matrix4_rotate_f32(math.PI / 6, {1, 0, 0}) *
            linalg.matrix4_rotate_f32(camera_angle, {0, 1, 0}) *
            linalg.matrix4_translate_f32({0, -0.5, 0})

        projection := linalg.matrix4_perspective_f32(math.PI / 3, f32(dimensions.x) / f32(dimensions.y), near, far)

        camera_position := (linalg.inverse(view) * [4]f32{0, 0, 0, 1}).xyz
        sun_direction := linalg.normalize([3]f32{math.sin(time * 0.5), 2, math.cos(time * 0.5)})

        gl.UseProgram(scene.program)

        flat_model := linalg.matrix_flatten(model)
        flat_view := linalg.matrix_flatten(view)
        flat_projection := linalg.matrix_flatten(projection)

        gl.UniformMatrix4fv(scene.uniforms.model, 1, false, raw_data(flat_model[:]))
        gl.UniformMatrix4fv(scene.uniforms.view, 1, false, raw_data(flat_view[:]))
        gl.UniformMatrix4fv(scene.uniforms.projection, 1, false, raw_data(flat_projection[:]))
        gl.Uniform3fv(scene.uniforms.camera_position, 1, raw_data(camera_position[:]))
        gl.Uniform3f(scene.uniforms.albedo, 0.8, 0.7, 0.6)
        gl.Uniform3f(scene.uniforms.sun_color, 1, 1, 1)
        gl.Uniform3fv(scene.uniforms.sun_direction, 1, raw_data(sun_direction[:]))

        gl.BindVertexArray(scene.vao)
        gl.DrawElements(gl.TRIANGLES, scene.indices_count, gl.UNSIGNED_INT, nil)

        sdl.GL_SwapWindow(window)
    }

    return nil
}

main :: proc() {
    err, has_err := application().?
    if has_err {
        fmt.println(err)
    }
}
