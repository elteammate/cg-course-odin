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
import timelib "core:time"

import gl "vendor:OpenGL"
import sdl "vendor:sdl2"
import stb_img "vendor:stb/image"

import common "../common"

Vertex :: struct {
    position: [3]f32 `gl:"location=0"`,
    tangent: [3]f32 `gl:"location=1"`,
    normal: [3]f32 `gl:"location=2"`,
    texcoords: [2]f32 `gl:"location=3"`,
}

generate_sphere :: proc(radius: f32, quality: u32) -> (vertices: [dynamic]Vertex, indices: [dynamic]u32) {
    for latitude in -int(quality) ..= int(quality) {
        for longitude in 0 ..= 4 * int(quality) {
            lat := f32(latitude) * math.PI / (2 * f32(quality))
            lon := f32(longitude) * math.PI / (2 * f32(quality))

            normal := [3]f32{math.cos(lat) * math.cos(lon), math.sin(lat), math.cos(lat) * math.sin(lon)}
            append(&vertices, Vertex{
                normal=normal,
                position=normal * radius,
                tangent={-math.cos(lat) * math.sin(lon), 0, math.cos(lat) * math.cos(lon)},
                texcoords={f32(longitude) / (4 * f32(quality)), f32(latitude) / (2 * f32(quality)) + 0.5},
            })
        }
    }

    for latitude in 0 ..< 2 * quality {
        for longitude in 0 ..< 4 * quality {
            i0 := (latitude + 0) * (4 * quality + 1) + (longitude + 0)
            i1 := (latitude + 1) * (4 * quality + 1) + (longitude + 0)
            i2 := (latitude + 0) * (4 * quality + 1) + (longitude + 1)
            i3 := (latitude + 1) * (4 * quality + 1) + (longitude + 1)

            append(&indices, i0, i1, i2, i2, i1, i3)
        }
    }

    return
}

load_texture :: proc(path: cstring) -> (result: u32) {
    width, height, channels: c.int
    pixels := stb_img.load(path, &width, &height, &channels, 4)

    gl.GenTextures(1, &result)
    gl.BindTexture(gl.TEXTURE_2D, result)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.GenerateMipmap(gl.TEXTURE_2D)

    stb_img.image_free(pixels)

    return
}


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
        "Graphics course practice 10",
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

    sphere: struct {
        using gpu_data: common.Gpu_Obj_Data,
        program: u32,
        uniforms: struct {
            model, view, projection, light_direction, camera_position, albedo_texture: i32
        }
    }

    sphere_shaders := common.compile_shader_program({
        vertex_source = #load("shader.vert", string),
        fragment_source = #load("shader.frag", string),
    }) or_return
    defer common.destroy_shader_program(sphere_shaders)
    sphere.program = sphere_shaders.program
    common.get_uniform_locations(sphere.program, &sphere.uniforms, ignore_missing=true)

    vertices, indices := generate_sphere(1.0, 16)
    sphere.gpu_data = common.send_vertices_indices_to_gpu(vertices[:], indices[:])
    delete(vertices)
    delete(indices)


    albedo_texture := load_texture("practice10/textures/brick_albedo.jpg")

    free_all(context.temp_allocator)

    last_frame_start := timelib.now()
    time: f32 = 0.0
    paused := false

    button_down: map[sdl.Keycode]bool
    defer delete(button_down)

    view_elevation := math.to_radians_f32(30.0)
    view_azimuth: f32 = 0.0
    camera_distance: f32 = 2.0

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
                    #partial switch event.key.keysym.sym {
                        case .ESCAPE:
                            running = false
                        case .SPACE:
                            paused = !paused
                    }
                    button_down[event.key.keysym.sym] = true
                case .KEYUP:
                    button_down[event.key.keysym.sym] = false
            }
        }

        current_time := timelib.now()
        defer last_frame_start = current_time
        dt := cast(f32)timelib.duration_seconds(timelib.diff(last_frame_start, current_time))
        if !paused do time += dt

        if button_down[.UP] || button_down[.W] do camera_distance -= 4.0 * dt
        if button_down[.DOWN] || button_down[.S] do camera_distance += 4.0 * dt
        if button_down[.LEFT] || button_down[.A] do view_azimuth -= 2.0 * dt
        if button_down[.RIGHT] || button_down[.D] do view_azimuth += 2.0 * dt

        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
        gl.Enable(gl.DEPTH_TEST)
        gl.Enable(gl.CULL_FACE)

        near: f32 = 0.1
        far: f32 = 100.0
        top := near
        right := (top * f32(dimensions.x)) / f32(dimensions.y)

        model := linalg.matrix4_rotate_f32(time * 0.1, {0, 1, 0})

        view :=
            linalg.matrix4_translate_f32({0, 0, -camera_distance}) *
            linalg.matrix4_rotate_f32(view_elevation, {1, 0, 0}) *
            linalg.matrix4_rotate_f32(view_azimuth, {0, 1, 0})

        projection := linalg.matrix4_perspective_f32(math.PI / 2, f32(dimensions.x) / f32(dimensions.y), near, far)

        light_direction := linalg.normalize([3]f32{1, 2, 3})
        camera_position := (linalg.inverse(view) * [4]f32{0, 0, 0, 1}).xyz

        flat_model := linalg.matrix_flatten(model)
        flat_view := linalg.matrix_flatten(view)
        flat_projection := linalg.matrix_flatten(projection)

        gl.UseProgram(sphere.program)
        gl.UniformMatrix4fv(sphere.uniforms.model, 1, false, raw_data(flat_model[:]))
        gl.UniformMatrix4fv(sphere.uniforms.view, 1, false, raw_data(flat_view[:]))
        gl.UniformMatrix4fv(sphere.uniforms.projection, 1, false, raw_data(flat_projection[:]))
        gl.Uniform3f(sphere.uniforms.light_direction, light_direction.x, light_direction.y, light_direction.z)
        gl.Uniform3f(sphere.uniforms.camera_position, camera_position.x, camera_position.y, camera_position.z)
        gl.Uniform1i(sphere.uniforms.albedo_texture, 0)

        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, albedo_texture)

        gl.BindVertexArray(sphere.vao)
        gl.DrawElements(gl.TRIANGLES, sphere.indices_count, gl.UNSIGNED_INT, nil)

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
