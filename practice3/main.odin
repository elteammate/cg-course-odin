package main

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

Vertex :: struct {
    position: [2]f32,
    color: [4]u8,
}

CurveVertex :: struct {
    position: [2]f32,
    color: [4]u8,
    dist: f32,
}

bezier :: proc(vertices: []Vertex, t: f32) -> [2]f32 {
    points := make([][2]f32, len(vertices))
    for i in 0..<len(vertices) {
        points[i] = vertices[i].position
    }

    for k in 0..<(len(vertices) - 1) {
        for i in 0..<(len(vertices) - k - 1) {
            points[i] = points[i] * (1.0 - t) + points[i+1] * t
        }
    }
    return points[0]
}

update_curve_vertices :: proc(vertices: []Vertex, curve_vertices: ^[dynamic]CurveVertex, curve_vbo: u32, quality: i32) {
    count := quality * (i32(len(vertices)) - 1)
    if len(vertices) < 2 {
        return
    }
    curve_vertices^ = {}
    last_p := vertices[0].position
    dist: f32 = 0.0
    for i in 0..=count {
        t := cast(f32)i / cast(f32)count
        p := bezier(vertices, t)
        dist += math.hypot_f32(p.x - last_p.x, p.y - last_p.y)
        curve_vertex := CurveVertex{
            position = p,
            color = [4]u8{255, 0, 0, 255},
            dist = dist,
        }
        append(curve_vertices, curve_vertex)
        last_p = p
    }

    // Update the VBO with new curve data
    gl.BindBuffer(gl.ARRAY_BUFFER, curve_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(curve_vertices^) * size_of(CurveVertex), raw_data(curve_vertices^), gl.DYNAMIC_DRAW)
}

update_line_vertices :: proc(vertices: []Vertex, curve_vertices: ^[dynamic]CurveVertex, line_vbo: u32, curve_vbo: u32, quality: i32) {
    gl.BindBuffer(gl.ARRAY_BUFFER, line_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(Vertex), raw_data(vertices), gl.DYNAMIC_DRAW)
    update_curve_vertices(vertices, curve_vertices, curve_vbo, quality)
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
        "Graphics course practice 3",
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

    gl.ClearColor(0.8, 0.8, 1.0, 0.0)

    vertex_source_bytes, vert_file_read_ok := os.read_entire_file("practice3/vertex.glsl")
    if !vert_file_read_ok do return "Failed to read vertex shader source"
    fragment_source_bytes, frag_file_read_ok := os.read_entire_file("practice3/fragment.glsl")
    if !frag_file_read_ok do return "Failed to read fragment shader source"

    program, err := compile_shader_program(shader_program_info{
        vertex = string(vertex_source_bytes),
        fragment = string(fragment_source_bytes),
    })
    if err, has_err := err.?; has_err do return err

    view_location := gl.GetUniformLocation(program, "view")
    time_location := gl.GetUniformLocation(program, "time")
    use_dist_location := gl.GetUniformLocation(program, "use_dist")

    line_vao, curve_vao: u32
    gl.GenVertexArrays(1, &line_vao)
    gl.GenVertexArrays(1, &curve_vao)

    vertices: [dynamic]Vertex
    curve_vertices: [dynamic]CurveVertex

    line_vbo, curve_vbo: u32
    gl.GenBuffers(1, &line_vbo)
    gl.GenBuffers(1, &curve_vbo)

    // Line VAO setup
    gl.BindVertexArray(line_vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, line_vbo)
    gl.EnableVertexAttribArray(0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), 0)
    gl.VertexAttribPointer(1, 4, gl.UNSIGNED_BYTE, gl.TRUE, size_of(Vertex), 8)

    // Curve VAO setup
    gl.BindVertexArray(curve_vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, curve_vbo)
    gl.EnableVertexAttribArray(0)
    gl.EnableVertexAttribArray(1)
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(CurveVertex), 0)
    gl.VertexAttribPointer(1, 4, gl.UNSIGNED_BYTE, gl.TRUE, size_of(CurveVertex), 8)
    gl.VertexAttribPointer(2, 1, gl.FLOAT, gl.FALSE, size_of(CurveVertex), 12)

    gl.LineWidth(5.0)
    gl.PointSize(10.0)

    quality: i32 = 4

    last_frame_start := sdl.GetTicks()

    time: f32 = 0.0
    running := true

    for running {
        for event: sdl.Event = ---; sdl.PollEvent(&event); {
            #partial switch event.type {
            case .QUIT:
                running = false
            case .WINDOWEVENT:
                #partial switch event.window.event {
                case .RESIZED:
                    width, height := event.window.data1, event.window.data2
                    gl.Viewport(0, 0, width, height)
                }
            case .MOUSEBUTTONDOWN:
                if event.button.button == sdl.BUTTON_LEFT {
                    mouse_x := event.button.x
                    mouse_y := event.button.y
                    append(&vertices, Vertex{
                        position = [2]f32{cast(f32)mouse_x, cast(f32)mouse_y},
                        color = [4]u8{0, 0, 0, 255},
                    })
                    fmt.println("Added vertex at", mouse_x, ",", mouse_y)
                    update_line_vertices(vertices[:], &curve_vertices, line_vbo, curve_vbo, quality)
                } else if event.button.button == sdl.BUTTON_RIGHT {
                    if len(vertices) > 0 {
                        update_line_vertices(vertices[:], &curve_vertices, line_vbo, curve_vbo, quality)
                    }
                }
            case .KEYDOWN:
                #partial switch event.key.keysym.sym {
                case .LEFT:
                    if quality > 1 {
                        quality -= 1
                        update_curve_vertices(vertices[:], &curve_vertices, curve_vbo, quality)
                    }
                case .RIGHT:
                    quality += 1
                    update_curve_vertices(vertices[:], &curve_vertices, curve_vbo, quality)
                }
            }
        }

        now := sdl.GetTicks()
        dt := cast(f32)(now - last_frame_start) / 1000.0
        last_frame_start = now
        time += dt

        gl.Clear(gl.COLOR_BUFFER_BIT)

        // Setup view matrix
        view := [16]f32{
            2.0 / cast(f32)width, 0.0, 0.0, -1.0,
            0.0, -2.0 / cast(f32)height, 0.0, 1.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0,
        }

        gl.UseProgram(program)
        gl.UniformMatrix4fv(view_location, 1, gl.TRUE, raw_data(view[:]))
        gl.Uniform1f(time_location, time)

        gl.Uniform1i(use_dist_location, 0)

        gl.BindVertexArray(line_vao)
        gl.BindBuffer(gl.ARRAY_BUFFER, line_vbo)
        gl.DrawArrays(gl.LINE_STRIP, 0, i32(len(vertices)))
        gl.DrawArrays(gl.POINTS, 0, i32(len(vertices)))

        gl.Uniform1i(use_dist_location, 1)

        gl.BindVertexArray(curve_vao)
        gl.BindBuffer(gl.ARRAY_BUFFER, curve_vbo)
        gl.DrawArrays(gl.LINE_STRIP, 0, i32(len(curve_vertices)))

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
