package main

import "core:fmt"
import "core:strings"
import "core:c"
import "core:os"
import "core:mem"
import "core:slice"
import "core:math"
import "core:math/linalg"
import "core:reflect"
import "core:testing"
import "core:c/libc"

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
    sdl.GL_SetAttribute(sdl.GLattr.MULTISAMPLESAMPLES, 1)
    sdl.GL_SetAttribute(sdl.GLattr.MULTISAMPLESAMPLES, 4)
    sdl.GL_SetAttribute(sdl.GLattr.RED_SIZE, 8)
    sdl.GL_SetAttribute(sdl.GLattr.GREEN_SIZE, 8)
    sdl.GL_SetAttribute(sdl.GLattr.BLUE_SIZE, 8)
    sdl.GL_SetAttribute(sdl.GLattr.DEPTH_SIZE, 24)

    window := sdl.CreateWindow(
        "Graphics course practice 5",
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
    gl.ClearColor(0.8, 0.8, 1.0, 0.0)

    shaders := common.compile_shader_program({
        vertex_path = "practice5/shader.vert",
        fragment_path = "practice5/shader.frag",
    }) or_return
    defer common.destroy_shader_program(shaders)
    program := shaders.program

    gl.UseProgram(program)
    uniforms := common.get_uniform_locations(struct {
        viewmodel,
        color_texture,
        time,
        projection: i32
    }, program)

    cow := parse_obj("practice5/cow.obj") or_return
    defer delete(cow.vertices)
    defer delete(cow.indices)

    vao, vbo, ebo: u32
    gl.GenVertexArrays(1, &vao)
    gl.BindVertexArray(vao)
    defer gl.DeleteVertexArrays(1, &vao)

    gl.GenBuffers(1, &vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    defer gl.DeleteBuffers(1, &vbo)

    common.configure_vao_attributes(Vertex)
    gl.BufferData(gl.ARRAY_BUFFER, len(cow.vertices) * size_of(Vertex), raw_data(cow.vertices[:]), gl.STATIC_DRAW)

    gl.GenBuffers(1, &ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
    defer gl.DeleteBuffers(1, &ebo)

    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(cow.indices) * size_of(u32), raw_data(cow.indices[:]), gl.STATIC_DRAW)

    last_frame_start := f32(sdl.GetTicks()) / 1000
    angle_y: f32 = math.PI
    offset_z: f32 = -2.0

    button_down: map[sdl.Keycode]bool
    defer delete(button_down)

    texture_size: i32 = 512
    dummy_texture, texture: u32
    gl.GenTextures(1, &dummy_texture)
    defer gl.DeleteTextures(1, &dummy_texture)
    gl.GenTextures(1, &texture)
    defer gl.DeleteTextures(1, &texture)

    gl.BindTexture(gl.TEXTURE_2D, dummy_texture)
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST_MIPMAP_NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

    dummy_pixels := make([]u32be, texture_size * texture_size)
    defer delete(dummy_pixels)
    for i in 0..<texture_size {
        for j in 0..<texture_size {
            dummy_pixels[i * texture_size + j] = (i + j) & 1 == 0 ? 0xFFFFFFFF : 0x000000FF
        }
    }

    gl.TexImage2D(
        gl.TEXTURE_2D, 0, gl.RGBA8, texture_size, texture_size, 0,
        gl.RGBA, gl.UNSIGNED_BYTE, raw_data(dummy_pixels),
    )
    gl.GenerateMipmap(gl.TEXTURE_2D)
    texture_size /= 2
    slice.fill(dummy_pixels[:texture_size * texture_size], 0xFF0000FF)
    gl.TexImage2D(
        gl.TEXTURE_2D, 1, gl.RGBA8, texture_size, texture_size, 0,
        gl.RGBA, gl.UNSIGNED_BYTE, raw_data(dummy_pixels),
    )
    texture_size /= 2
    slice.fill(dummy_pixels[:texture_size * texture_size], 0x00FF00FF)
    gl.TexImage2D(
        gl.TEXTURE_2D, 2, gl.RGBA8, texture_size, texture_size, 0,
        gl.RGBA, gl.UNSIGNED_BYTE, raw_data(dummy_pixels),
    )
    texture_size /= 2
    slice.fill(dummy_pixels[:texture_size * texture_size], 0x0000FFFF)
    gl.TexImage2D(
        gl.TEXTURE_2D, 3, gl.RGBA8, texture_size, texture_size, 0,
        gl.RGBA, gl.UNSIGNED_BYTE, raw_data(dummy_pixels),
    )

    texture_res: [2]c.int
    channels: c.int
    pixels := stb_img.load("practice5/cow.png", &texture_res.x, &texture_res.y, &channels, 4)

    gl.BindTexture(gl.TEXTURE_2D, texture)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

    gl.TexImage2D(
        gl.TEXTURE_2D, 0, gl.RGBA8, texture_res.x, texture_res.y, 0,
        gl.RGBA, gl.UNSIGNED_BYTE, cast([^]byte)(pixels),
    )
    gl.GenerateMipmap(gl.TEXTURE_2D)
    stb_img.image_free(pixels)

    gl.ActiveTexture(gl.TEXTURE0 + 0)
    gl.BindTexture(gl.TEXTURE_2D, dummy_texture)

    gl.ActiveTexture(gl.TEXTURE0 + 1)
    gl.BindTexture(gl.TEXTURE_2D, texture)

    gl.Uniform1i(uniforms.color_texture, 1)

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
                            gl.Viewport(0, 0, dimensions.x, dimensions.y)
                    }
                case .KEYDOWN:
                    button_down[event.key.keysym.sym] = true
                case .KEYUP:
                    button_down[event.key.keysym.sym] = false
            }
        }

        time := f32(sdl.GetTicks()) / 1000
        defer last_frame_start = time
        dt := time - last_frame_start

        speed: f32 = 4
        if (button_down[.UP]) do offset_z -= speed * dt
        if (button_down[.DOWN]) do offset_z += speed * dt
        if (button_down[.LEFT]) do angle_y -= speed * dt
        if (button_down[.RIGHT]) do angle_y += speed * dt

        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        screen := linalg.to_f32(dimensions)
        near: f32 : 0.1
        far: f32 : 100
        top := near
        right := (top * screen.x) / screen.y

        viewmodel := matrix[4, 4]f32{
            math.cos(angle_y), 0, -math.sin(angle_y), 0,
            0, 1, 0, 0,
            math.sin(angle_y), 0, math.cos(angle_y), offset_z,
            0, 0, 0, 1
        }

        projection := matrix[4, 4]f32{
            near / right, 0, 0, 0,
            0, near / top, 0, 0,
            0, 0, -(far + near) / (far - near), -2 * far * near / (far - near),
            0, 0, -1, 0
        }

        flat_viewmodel := linalg.matrix_flatten(viewmodel)
        flat_projection := linalg.matrix_flatten(projection)

        gl.UseProgram(program)
        gl.UniformMatrix4fv(uniforms.viewmodel, 1, false, raw_data(flat_viewmodel[:]))
        gl.UniformMatrix4fv(uniforms.projection, 1, false, raw_data(flat_projection[:]))
        gl.Uniform1f(uniforms.time, time)

        gl.DrawElements(gl.TRIANGLES, cast(i32)len(cow.indices), gl.UNSIGNED_INT, nil)

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
