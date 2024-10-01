package main

import "base:intrinsics"
import "core:fmt"
import "core:strings"
import "core:c"
import "core:os"
import "core:math"
import "core:math/linalg"

import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

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

    sdl.GL_SetSwapInterval(1)

    gl.load_up_to(3, 3, sdl.gl_set_proc_address)

    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)
    // gl.CullFace(gl.FRONT)
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
    defer gl.DeleteProgram(program)

    model_location := gl.GetUniformLocation(program, "model")
    view_location := gl.GetUniformLocation(program, "view")
    projection_location := gl.GetUniformLocation(program, "projection")

    obj_data, obj_parsing_err := parse_obj("practice4/bunny.obj")
    if err, has_err := obj_parsing_err.?; has_err do return err

    vao, vbo, ebo: u32
    gl.GenVertexArrays(1, &vao)
    gl.GenBuffers(1, &vbo)
    gl.GenBuffers(1, &ebo)

    gl.BindVertexArray(vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(obj_data.vertices) * size_of(Vertex), raw_data(obj_data.vertices), gl.STATIC_DRAW)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(obj_data.indices) * 4, raw_data(obj_data.indices), gl.STATIC_DRAW)

    for attr in u32(0)..<3 do gl.EnableVertexAttribArray(attr)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, position)) 
    gl.VertexAttribPointer(1, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, normal))
    gl.VertexAttribPointer(2, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, texcoord))

    last_frame_start := sdl.GetTicks()
    time: f32 = 0.0
    button_down: map[sdl.Keycode]bool
    running := true

    Object :: struct {
        position: [3]f32,
        move_speed: [2]f32,
        vao: u32,
        rotation_speed: f32,
        rotation_axis: u32,
        rotation_angle: f32,
        scale: f32,
    }

    objects := [?]Object{
        {
            position = {0, 0, 0},
            move_speed = {1.0, 1.0},
            vao = vao,
            rotation_speed = 0.7,
            rotation_axis = 1,
            scale = 0.5,
        },
        {
            position = {1.0, 1.0, -3},
            move_speed = {0.7, 1.5},
            vao = vao,
            rotation_speed = 20.0,
            rotation_axis = 0,
            scale = 0.3,
        },
        {
            position = {-0.4, 0.1, -1.5},
            move_speed = {-0.3, -0.6},
            vao = vao,
            rotation_speed = 0.4,
            rotation_axis = 2,
            scale = 0.6,
        },
    }

    rotation_matrix :: proc(axis: u32, angle: f32) -> matrix[4, 4]f32 {
        cos := math.cos(angle)
        sin := math.sin(angle)
        switch axis {
            case 0:
                return matrix[4, 4]f32{
                    1, 0, 0, 0,
                    0, cos, -sin, 0,
                    0, sin, cos, 0,
                    0, 0, 0, 1,
                }
            case 1:
                return matrix[4, 4]f32{
                    cos, 0, sin, 0,
                    0, 1, 0, 0,
                    -sin, 0, cos, 0,
                    0, 0, 0, 1,
                }
            case 2:
                return matrix[4, 4]f32{
                    cos, -sin, 0, 0,
                    sin, cos, 0, 0,
                    0, 0, 1, 0,
                    0, 0, 0, 1,
                }
        }
        unreachable()
    }

    for running {
        for event: sdl.Event; sdl.PollEvent(&event); {
            #partial switch event.type {
                case .QUIT:
                    running = false
                case .WINDOWEVENT:
                    #partial switch event.window.event {
                        case .RESIZED:
                            width = event.window.data1
                            height = event.window.data2
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
        last_frame_start = now
        time += dt

        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        cam_position: = [3]f32{0, 0, 2}

        view := matrix[4, 4]f32{
            1, 0, 0, -cam_position.x,
            0, 1, 0, -cam_position.y,
            0, 0, 1, -cam_position.z,
            0, 0, 0, 1, 
        }

        near: f32 = 0.01
        far: f32 = 100
        fov: f32 = 60 * math.RAD_PER_DEG
        right := math.tan(fov / 2) * near
        aspect_ratio := f32(width) / f32(height)
        top := right / aspect_ratio

        projection := matrix[4, 4]f32{
            near / right, 0, 0, 0,
            0, near / top, 0, 0,
            0, 0, -(far + near) / (far - near), -2 * far * near / (far - near),
            0, 0, -1, 0, 
        }
        // projection := matrix[4, 4]f32{
        //     1, 0, 0, 0,
        //     0, 1, 0, 0,
        //     0, 0, 1, 0,
        //     0, 0, 0, 1, 
        // }

        view_flat := linalg.matrix_flatten(view)
        projection_flat := linalg.matrix_flatten(projection)

        gl.UniformMatrix4fv(view_location, 1, false, raw_data(view_flat[:]))
        gl.UniformMatrix4fv(projection_location, 1, false, raw_data(projection_flat[:]))

        for &obj in objects {
            if button_down[sdl.Keycode.LEFT] do obj.position.x -= dt * obj.move_speed.x 
            if button_down[sdl.Keycode.RIGHT] do obj.position.x += dt * obj.move_speed.x
            if button_down[sdl.Keycode.UP] do obj.position.y += dt * obj.move_speed.y
            if button_down[sdl.Keycode.DOWN] do obj.position.y -= dt * obj.move_speed.y

            obj.rotation_angle += dt * obj.rotation_speed

            model := matrix[4, 4]f32{
                1, 0, 0, obj.position.x,
                0, 1, 0, obj.position.y,
                0, 0, 1, obj.position.z,
                0, 0, 0, 1,
            } * matrix[4, 4]f32{
                obj.scale, 0, 0, 0,
                0, obj.scale, 0, 0,
                0, 0, obj.scale, 0,
                0, 0, 0, 1, 
            } * rotation_matrix(obj.rotation_axis, obj.rotation_angle)
            model_flat := linalg.matrix_flatten(model)

            gl.BindVertexArray(vao)
            gl.UniformMatrix4fv(model_location, 1, false, raw_data(model_flat[:]))
            gl.DrawElements(gl.TRIANGLES, cast(i32)len(obj_data.indices), gl.UNSIGNED_INT, nil)
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

