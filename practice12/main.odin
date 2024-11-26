package main

import "core:fmt"
import "core:strings"
import "core:c"
import "core:os"
import "core:mem"
import "core:slice"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:reflect"
import "core:testing"
import "core:c/libc"
import timelib "core:time"

import gl "vendor:OpenGL"
import sdl "vendor:sdl2"
import stb_img "vendor:stb/image"

import common "../common"

CUBE_VERTICES :: [8][3]f32{
    {0, 0, 0},
    {1, 0, 0},
    {0, 1, 0},
    {1, 1, 0},
    {0, 0, 1},
    {1, 0, 1},
    {0, 1, 1},
    {1, 1, 1},
}

CUBE_INDICES :: [12 * 3]u32{
	// -Z
	0, 2, 1,
	1, 2, 3,
	// +Z
	4, 5, 6,
	6, 5, 7,
	// -Y
	0, 1, 4,
	4, 1, 5,
	// +Y
	2, 6, 3,
	3, 6, 7,
	// -X
	0, 4, 2,
	2, 4, 6,
	// +X
	1, 3, 5,
	5, 3, 7,
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
        "Graphics course practice 12",
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

    shaders := common.compile_shader_program({
        vertex_source = #load("shader.vert", string),
        fragment_source = #load("shader.frag", string),
    }) or_return
    defer common.destroy_shader_program(shaders)

    box: struct {
        vao, vbo, ebo: u32,
        program: u32,
        uniforms: struct {
            view, projection, bbox_min, bbox_max, camera_position, light_direction, cloud: i32
        },
    }
    box.program = shaders.program
    common.get_uniform_locations(box.program, &box.uniforms, ignore_missing = true)

    cube_vertices := CUBE_VERTICES
    cube_indices := CUBE_INDICES

    gl.GenVertexArrays(1, &box.vao)
    gl.BindVertexArray(box.vao)

    gl.GenBuffers(1, &box.vbo);
    gl.BindBuffer(gl.ARRAY_BUFFER, box.vbo);
    gl.BufferData(gl.ARRAY_BUFFER, size_of(CUBE_VERTICES), &cube_vertices, gl.STATIC_DRAW);

    gl.GenBuffers(1, &box.ebo);
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, box.ebo);
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(CUBE_INDICES), &cube_indices, gl.STATIC_DRAW);

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of([3]f32), 0)

    // texture_path := "bunny.data"; cloud_texture_size := [3]i32{64, 64, 64}
    texture_path := "disney_cloud.data"; cloud_texture_size := [3]i32{126, 86, 154}
    // texture_path := "cloud.data"; cloud_texture_size := [3]i32{128, 64, 64}

    cloud: u32
    gl.GenTextures(1, &cloud)
    gl.BindTexture(gl.TEXTURE_3D, cloud)
    gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

    pixels, read_ok := os.read_entire_file_from_filename(fmt.tprintf("practice12/%s", texture_path))
    defer delete(pixels)
    if !read_ok do return "Failed to read texture"

    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    gl.TexImage3D(
        gl.TEXTURE_3D, 0, gl.R8,
        cloud_texture_size[0], cloud_texture_size[1], cloud_texture_size[2],
        0, gl.RED, gl.UNSIGNED_BYTE, raw_data(pixels),
    )

    cloud_bbox_max := linalg.to_f32(cloud_texture_size) / 100;
    cloud_bbox_min := -cloud_bbox_max

    free_all(context.temp_allocator)

    view_angle: f32 = math.PI / 12
    camera_distance: f32 = 2.5
    camera_rotation: f32 = math.PI / 2

    button_down: map[sdl.Keycode]bool
    defer delete(button_down)

    last_frame_start := timelib.now()
    time: f32 = 0.0
    paused := false
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

        if button_down[.UP] || button_down[.E] do camera_distance -= 3.0 * dt
        if button_down[.DOWN] || button_down[.Q] do camera_distance += 3.0 * dt

        if button_down[.W] do view_angle -= 2.0 * dt
        if button_down[.S] do view_angle += 2.0 * dt
        if button_down[.A] do camera_rotation -= 2.0 * dt
        if button_down[.D] do camera_rotation += 2.0 * dt

        gl.ClearColor(0.6, 0.8, 1.0, 0.0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        gl.Enable(gl.DEPTH_TEST);

        gl.Enable(gl.CULL_FACE);
        gl.CullFace(gl.FRONT);

        gl.Enable(gl.BLEND);
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        near: f32 = 0.1
        far: f32 = 100.0

        view :=
            linalg.matrix4_translate_f32({0, 0, -camera_distance}) *
            linalg.matrix4_rotate_f32(view_angle, {1, 0, 0}) *
            linalg.matrix4_rotate_f32(camera_rotation, {0, 1, 0})

        projection := linalg.matrix4_perspective_f32(math.PI / 2, f32(dimensions.x) / f32(dimensions.y), near, far)

        camera_position := (linalg.inverse(view) * [4]f32{0, 0, 0, 1}).xyz
        light_direction := linalg.normalize([3]f32{math.cos(time), 1.0, math.sin(time)})

        gl.UseProgram(box.program)
        gl.UniformMatrix4fv(box.uniforms.projection, 1, false, &projection[0, 0])
        gl.UniformMatrix4fv(box.uniforms.view, 1, false, &view[0, 0])
        gl.Uniform3fv(box.uniforms.bbox_min, 1, &cloud_bbox_min[0])
        gl.Uniform3fv(box.uniforms.bbox_max, 1, &cloud_bbox_max[0])
        gl.Uniform3fv(box.uniforms.camera_position, 1, &camera_position[0])
        gl.Uniform3fv(box.uniforms.light_direction, 1, &light_direction[0])
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_3D, cloud)
        gl.Uniform1i(box.uniforms.cloud, 0)

        gl.BindVertexArray(box.vao)
        gl.DrawElements(gl.TRIANGLES, len(cube_indices), gl.UNSIGNED_INT, nil)

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
