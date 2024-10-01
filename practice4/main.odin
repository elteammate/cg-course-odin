package main

import "base:intrinsics"
import "core:fmt"
import "core:strings"
import "core:c"
import "core:os"
import "core:math"

import glew "../glew"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

glew_fail :: proc(msg: string, err: gl.GL_Enum) -> string {
    return strings.concatenate({
        "GLEW Error (", msg, "): ", string(glew.GetErrorString(err))
    })
}

sdl2_fail :: proc(msg: string) -> string {
    return strings.concatenate({
        "SDL2 Error (", msg, "): ", string(sdl.GetError())
    })
}

shader_program_info :: struct {
    vertex: string,
    fragment: string,
}

compile_shader :: proc(source: string, type: gl.GL_Enum) -> (u32, Maybe(string)) {
    shader := gl.CreateShader(u32(type))
    sources := []cstring {strings.unsafe_string_to_cstring(source)}
    lengths := []i32 {cast(i32)len(source)}
    gl.ShaderSource(shader, 1, raw_data(sources), raw_data(lengths))
    gl.CompileShader(shader)
    compile_status: gl.GL_Enum = ---
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, cast([^]i32)&compile_status)
    if (compile_status != .TRUE) {
        infolog_size: i32 = ---
        gl.GetShaderiv(shader, gl.INFO_LOG_LENGTH, &infolog_size)
        infolog := make([]u8, infolog_size)
        gl.GetShaderInfoLog(shader, infolog_size, nil, cast([^]u8)raw_data(infolog))
        return 0, strings.concatenate({"Error compiling shader: ", string(infolog)})
    }
    return shader, nil
}

compile_shader_program :: proc(program_info: shader_program_info) -> (u32, Maybe(string)) {
    vertex, vert_error := compile_shader(program_info.vertex, .VERTEX_SHADER)
    if err, has_err := vert_error.?; has_err do return 0, err

    fragment, frag_error := compile_shader(program_info.fragment, .FRAGMENT_SHADER)
    if err, has_err := frag_error.?; has_err do return 0, err

    program := gl.CreateProgram()
    gl.AttachShader(program, vertex)
    gl.AttachShader(program, fragment)
    gl.LinkProgram(program)

    link_status: gl.GL_Enum = ---
    gl.GetProgramiv(program, gl.LINK_STATUS, cast([^]i32)&link_status)
    if (link_status != .TRUE) {
        infolog_size: i32 = ---
        gl.GetProgramiv(program, gl.INFO_LOG_LENGTH, &infolog_size)
        infolog := make([]u8, infolog_size)
        gl.GetProgramInfoLog(program, infolog_size, nil, cast([^]u8)raw_data(infolog))
        return 0, strings.concatenate({"Error linking program: ", string(infolog)})
    }

    return program, nil
}

application :: proc() -> Maybe(string) {
    if (sdl.Init(sdl.INIT_VIDEO) != 0) do return sdl2_fail("sdl.Init")
    defer sdl.Quit()

    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_MAJOR_VERSION, 3)
    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_MINOR_VERSION, 3)
    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_PROFILE_MASK, c.int(sdl.GLprofile.CORE))
    sdl.GL_SetAttribute(sdl.GLattr.DOUBLEBUFFER, 1)
    sdl.GL_SetAttribute(sdl.GLattr.MULTISAMPLESAMPLES, 1)
    sdl.GL_SetAttribute(sdl.GLattr.MULTISAMPLESAMPLES, 4)
    sdl.GL_SetAttribute(sdl.GLattr.RED_SIZE, 8)
    sdl.GL_SetAttribute(sdl.GLattr.GREEN_SIZE, 8)
    sdl.GL_SetAttribute(sdl.GLattr.BLUE_SIZE, 8)
    sdl.GL_SetAttribute(sdl.GLattr.DEPTH_SIZE, 24)

    window := sdl.CreateWindow(
        "Graphics course practice 4",
        sdl.WINDOWPOS_CENTERED,
        sdl.WINDOWPOS_CENTERED,
        800, 600,
        sdl.WINDOW_OPENGL | sdl.WINDOW_RESIZABLE,
    )
    if window == nil do return sdl2_fail("sdl.CreateWindow")
    defer sdl.DestroyWindow(window)

    width, height: i32 = ---, ---
    sdl.GetWindowSize(window, &width, &height)

    ctx := sdl.GL_CreateContext(window)
    if ctx == nil do return sdl2_fail("sdl.GL_CreateContext")
    defer sdl.GL_DeleteContext(ctx)

    sdl.GL_SetSwapInterval(0)

    gl.load_up_to(3, 3, sdl.gl_set_proc_address)

    gl.ClearColor(0.1, 0.1, 0.2, 0.0)

    vertex_source_bytes, vert_file_read_ok := os.read_entire_file("practice4/vertex.glsl")
    if !vert_file_read_ok do return "Failed to read vertex shader source"
    fragment_source_bytes, frag_file_read_ok := os.read_entire_file("practice4/fragment.glsl")
    if !frag_file_read_ok do return "Failed to read fragment shader source"

    program, err := compile_shader_program(shader_program_info{
        vertex = string(vertex_source_bytes),
        fragment = string(fragment_source_bytes),
    })
    if err, has_err := err.?; has_err do return err
    gl.UseProgram(program)

    model_location := gl.GetUniformLocation(program, "model")
    view_location := gl.GetUniformLocation(program, "view")
    projection_location := gl.GetUniformLocation(program, "projection")

    bunny_data, obj_parsing_err := parse_obj("practice4/bunny.obj")
    if err, has_err := obj_parsing_err.?; has_err do return err

    last_frame_start := sdl.GetTicks()
    time: f32 = 0.0
    button_down: map[sdl.Keycode]bool
    running := true

    for running {
        for event: sdl.Event = ---; sdl.PollEvent(&event); {
            #partial switch event.type {
                case .QUIT:
                    running = false
                case .WINDOWEVENT:
                    #partial switch event.window.event {
                        case .RESIZED:
                            width := event.window.data1
                            height := event.window.data2
                            gl.Viewport(0, 0, width, height)
                    }
                case .KEYDOWN:
                    button_down[event.key.keysym.sym] = true
                case .KEYUP:
                    button_down[event.key.keysym.sym] = false
            }
        }

        if !running do break

        now := sdl.GetTicks()
        dt := cast(f32)(now - last_frame_start) / 1000.0
        last_frame_start := now
        time += dt

        gl.Clear(gl.COLOR_BUFFER_BIT)

        model := matrix[4, 4]f32{
            1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0, 
        }

        view := matrix[4, 4]f32{
            1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0, 
        }

        projection := matrix[4, 4]f32{
            1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0, 
        }

        model_flat := intrinsics.matrix_flatten(model)
        view_flat := intrinsics.matrix_flatten(view)
        projection_flat := intrinsics.matrix_flatten(projection)

        gl.UniformMatrix4fv(view_location, 1, true, raw_data(view_flat[:]))
        gl.UniformMatrix4fv(model_location, 1, true, raw_data(model_flat[:]))
        gl.UniformMatrix4fv(projection_location, 1, true, raw_data(projection_flat[:]))

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

