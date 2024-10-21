package main

import "core:fmt"
import "core:strings"
import "core:c"
import "core:os"
import "core:mem"
import "core:slice"
import "core:math"
import "core:math/linalg"
import glsl_linalg "core:math/linalg/glsl"
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
        "Graphics course practice 7",
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

    suzanne: struct {
        using gpu_data: common.Gpu_Obj_Data,
        program: u32,
        uniforms: struct {
            model, view, projection, camera_position, albedo, ambient_light: i32
        }
    }

    suzanne_shaders := common.compile_shader_program({
        vertex_source = #load("shader.vert", string),
        fragment_source = #load("shader.frag", string),
    }) or_return
    defer common.destroy_shader_program(suzanne_shaders)
    suzanne.program = suzanne_shaders.program
    common.get_uniform_locations(suzanne.program, &suzanne.uniforms, ignore_missing = true)

    suzanne_data := common.load_obj_file("practice7/suzanne.obj") or_return
    defer common.destory_obj_data(suzanne_data)
    suzanne.gpu_data = common.send_obj_to_gpu(suzanne_data)
    defer common.destroy_gpu_obj_data(suzanne)

    free_all(context.temp_allocator)

    last_frame_start := timelib.now()
    time: f32 = 0.0

    camera_distance: f32 = 3.0
    camera_x: f32 = 0.0
    camera_angle: f32 = 0.0

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
        if button_down[.KP_4] || button_down[.Q] do camera_x -= SPEED * dt;
        if button_down[.KP_6] || button_down[.E] do camera_x += SPEED * dt;

        gl.Viewport(0, 0, dimensions.x, dimensions.y)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        near: f32 = 0.1
        far: f32 = 100.0
        aspect_ratio := f32(dimensions.x) / f32(dimensions.y)

        model := linalg.MATRIX4F32_IDENTITY

        view := 
            linalg.matrix4_translate([3]f32{0, 0, -camera_distance}) *
            linalg.matrix4_rotate(camera_angle, [3]f32{0, 1, 0}) *
            linalg.matrix4_translate([3]f32{-camera_x, 0, 0})

        projection := linalg.matrix4_perspective(math.PI / 3, f32(dimensions.x) / f32(dimensions.y), near, far)
        camera_position := linalg.inverse(view) * [4]f32{0, 0, 0, 1};

        flat_view := linalg.matrix_flatten(view)
        flat_model := linalg.matrix_flatten(model)
        flat_projection := linalg.matrix_flatten(projection)

        gl.UseProgram(suzanne.program)
        gl.UniformMatrix4fv(suzanne.uniforms.model, 1, gl.FALSE, raw_data(flat_model[:]))
        gl.UniformMatrix4fv(suzanne.uniforms.view, 1, gl.FALSE, raw_data(flat_view[:]))
        gl.UniformMatrix4fv(suzanne.uniforms.projection, 1, gl.FALSE, raw_data(flat_projection[:]))
        gl.Uniform3fv(suzanne.uniforms.camera_position, 1, raw_data(camera_position[:]))
        gl.Uniform3f(suzanne.uniforms.albedo, 0.7, 0.4, 0.2)
        gl.Uniform3f(suzanne.uniforms.ambient_light, 0.2, 0.2, 0.2)

        gl.BindVertexArray(suzanne.vao)
        gl.DrawElements(gl.TRIANGLES, suzanne.indices_count, gl.UNSIGNED_INT, nil)

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
