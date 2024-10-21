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
        "Graphics course practice 6",
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

    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)

    dragon: struct {
        using gpu_data: common.Gpu_Obj_Data,
        program: u32,
        uniforms: struct {
            model, view, projection, camera_position: i32,
        }
    }

    dragon_shaders := common.compile_shader_program({
        vertex_source = #load("dragon.vert", string),
        fragment_source = #load("dragon.frag", string),
    }) or_return
    defer common.destroy_shader_program(dragon_shaders)
    dragon.program = dragon_shaders.program
    common.get_uniform_locations(dragon.program, &dragon.uniforms)

    dragon_data := common.load_obj_file("practice6/dragon.obj") or_return
    defer common.destory_obj_data(dragon_data)
    dragon.gpu_data = common.send_obj_to_gpu(dragon_data)
    defer common.destroy_gpu_obj_data(dragon)

    rectangle: struct {
        program: u32,
        vao: u32,
        uniforms: struct {
            center, size, render_result, mode, time: i32,
        }
    }

    rectangle_shaders := common.compile_shader_program({
        vertex_source = #load("rectangle.vert", string),
        fragment_source = #load("rectangle.frag", string),
    }) or_return
    defer common.destroy_shader_program(rectangle_shaders)
    rectangle.program = rectangle_shaders.program
    common.get_uniform_locations(rectangle.program, &rectangle.uniforms)

    gl.GenVertexArrays(1, &rectangle.vao)
    defer gl.DeleteVertexArrays(1, &rectangle.vao)

    free_all(context.temp_allocator)

    fbo: u32
    gl.GenFramebuffers(1, &fbo)
    gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, fbo)

    texture: u32
    gl.GenTextures(1, &texture)
    gl.BindTexture(gl.TEXTURE_2D, texture)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, dimensions.x / 2, dimensions.y / 2, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.FramebufferTexture(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, texture, 0)

    depth_renderbuffer: u32
    gl.GenRenderbuffers(1, &depth_renderbuffer)
    gl.BindRenderbuffer(gl.RENDERBUFFER, depth_renderbuffer)
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, dimensions.x / 2, dimensions.y / 2)
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depth_renderbuffer)

    if gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
        fmt.printfln("Failed to initialize framebuffer")
    }

    last_frame_start := timelib.now()
    time: f32 = 0.0
    view_angle: f32 = 0.0
    camera_distance: f32 = 0.5
    model_angle: f32 = math.PI / 2
    model_scale: f32 = 1.0

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
                            gl.BindTexture(gl.TEXTURE_2D, texture)
                            gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, dimensions.x / 2, dimensions.y / 2, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
                            gl.BindRenderbuffer(gl.RENDERBUFFER, depth_renderbuffer)
                            gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, dimensions.x / 2, dimensions.y / 2)
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

        SPEED :: 1.0
        ROTATION_SPEED :: 2.0
        if button_down[sdl.Keycode.UP] do camera_distance -= SPEED * dt
        if button_down[sdl.Keycode.DOWN] do camera_distance += SPEED * dt
        if button_down[sdl.Keycode.LEFT] do model_angle += ROTATION_SPEED * dt
        if button_down[sdl.Keycode.RIGHT] do model_angle -= ROTATION_SPEED * dt

        Render_Config :: struct {
            view: matrix[4, 4]f32,
            projection: matrix[4, 4]f32,
            center: [2]f32,
            clear_color: [3]f32,
            mode: i32,
        }

        far: f32 = 100.0
        near: f32 = 0.1
        aspect_ratio := f32(dimensions.x) / f32(dimensions.y)
        top: f32 = 0.5

        configs := [?]Render_Config{
            {
                view = linalg.matrix4_rotate(view_angle, [3]f32{1, 0, 0}) * linalg.matrix4_translate([3]f32{0.0, 0.0, -camera_distance}),
                projection = linalg.matrix4_perspective(math.PI / 2, aspect_ratio, near, far),
                center = {-0.5, -0.5},
                clear_color = {0.8, 0.8, 1.0},
                mode = 0,
            },
            {
                view = linalg.matrix4_translate([3]f32{0.0, 0.0, -camera_distance}),
                projection = linalg.matrix_ortho3d(-aspect_ratio * top, aspect_ratio * top, -top, top, near, far),
                center = {0.5, -0.5},
                clear_color = {1.0, 0.7, 0.8},
                mode = 1,
            },
            {
                view = linalg.matrix4_rotate(-math.PI / 2, [3]f32{0, 1, 0}) * linalg.matrix4_translate([3]f32{-camera_distance, 0.0, 0.0}),
                projection = linalg.matrix_ortho3d(-aspect_ratio * top, aspect_ratio * top, -top, top, near, far),
                center = {0.5, 0.5},
                clear_color = {1.0, 1.0, 0.8},
                mode = 2,
            },
            {
                view = linalg.matrix4_rotate(math.PI / 2, [3]f32{1, 0, 0}) * linalg.matrix4_translate([3]f32{0.0, -camera_distance, 0.0}),
                projection = linalg.matrix_ortho3d(-aspect_ratio * top, aspect_ratio * top, -top, top, near, far),
                center = {-0.5, 0.5},
                clear_color = {0.8, 1.0, 0.8},
                mode = 3,
            },
        }

        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Viewport(0, 0, dimensions.x, dimensions.y)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        for cfg in configs {
            gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
            gl.Viewport(0, 0, dimensions.x / 2, dimensions.y / 2)
            gl.ClearColor(cfg.clear_color.r, cfg.clear_color.g, cfg.clear_color.b, 0.0)
            gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

            projection := cfg.projection
            view := cfg.view
            model := linalg.matrix4_rotate(model_angle, [3]f32{0, 1, 0}) * linalg.matrix4_scale(model_scale)
            camera_position := (linalg.inverse(view) * [4]f32{0, 0, 0, 1}).xyz

            flat_model := linalg.matrix_flatten(model)
            flat_view := linalg.matrix_flatten(view)
            flat_projection := linalg.matrix_flatten(projection)

            gl.UseProgram(dragon.program)
            gl.UniformMatrix4fv(dragon.uniforms.model, 1, gl.FALSE, raw_data(flat_model[:]))
            gl.UniformMatrix4fv(dragon.uniforms.view, 1, gl.FALSE, raw_data(flat_view[:]))
            gl.UniformMatrix4fv(dragon.uniforms.projection, 1, gl.FALSE, raw_data(flat_projection[:]))

            gl.Uniform3fv(dragon.uniforms.camera_position, 1, raw_data(camera_position[:]))

            gl.BindVertexArray(dragon.vao)
            gl.DrawElements(gl.TRIANGLES, dragon.indices_count, gl.UNSIGNED_INT, nil)

            gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
            gl.Viewport(0, 0, dimensions.x, dimensions.y)

            gl.ActiveTexture(gl.TEXTURE0)
            gl.BindTexture(gl.TEXTURE_2D, texture)

            gl.UseProgram(rectangle_shaders.program)
            gl.Uniform2f(rectangle.uniforms.center, cfg.center.x, cfg.center.y)
            gl.Uniform2f(rectangle.uniforms.size, 0.5, 0.5)
            gl.Uniform1i(rectangle.uniforms.render_result, 0)
            gl.Uniform1i(rectangle.uniforms.mode, cfg.mode)
            gl.Uniform1f(rectangle.uniforms.time, time)
            gl.BindVertexArray(rectangle.vao)
            gl.DrawArrays(gl.TRIANGLES, 0, 6)
        }

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
