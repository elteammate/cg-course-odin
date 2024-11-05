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


spread3 :: proc(x: [3]$T) -> (T, T, T) {
    return x.x, x.y, x.z
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
        "Graphics course practice 9",
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

    scene: struct {
        using gpu_data: common.Gpu_Obj_Data,
        program: u32,
        shadow_program: u32,
        uniforms: struct {
            model, view, projection, transform,
            ambient, light_direction, light_color,
            shadow_map: i32
        },
        shadow_uniforms: struct {
            model, transform: i32
        },
    }

    debug_rect: struct {
        vao: u32,
        program: u32,
        uniforms: struct {
            shadow_map: i32
        },
    }

    scene_shaders := common.compile_shader_program({
        vertex_source = #load("scene.vert", string),
        fragment_source = #load("scene.frag", string),
    }) or_return
    defer common.destroy_shader_program(scene_shaders)
    scene.program = scene_shaders.program
    common.get_uniform_locations(scene.program, &scene.uniforms)

    shadow_shaders := common.compile_shader_program({
        vertex_source = #load("shadow.vert", string),
        fragment_source = #load("shadow.frag", string),
    }) or_return
    defer common.destroy_shader_program(shadow_shaders)
    scene.shadow_program = shadow_shaders.program
    common.get_uniform_locations(scene.shadow_program, &scene.shadow_uniforms)

    scene_data := common.load_obj_file("practice9/bunny.obj") or_return

    scene_bb_min := scene_data.vertices[0].position
    scene_bb_max := scene_data.vertices[0].position
    for vertex in scene_data.vertices {
        scene_bb_min = linalg.min(scene_bb_min, vertex.position)
        scene_bb_max = linalg.max(scene_bb_max, vertex.position)
    }
    scene_bb_center := (scene_bb_min + scene_bb_max) / 2
    scene_bb_vertices := [?][3]f32{
        {scene_bb_min.x, scene_bb_min.y, scene_bb_min.z},
        {scene_bb_min.x, scene_bb_min.y, scene_bb_max.z},
        {scene_bb_min.x, scene_bb_max.y, scene_bb_min.z},
        {scene_bb_min.x, scene_bb_max.y, scene_bb_max.z},
        {scene_bb_max.x, scene_bb_min.y, scene_bb_min.z},
        {scene_bb_max.x, scene_bb_min.y, scene_bb_max.z},
        {scene_bb_max.x, scene_bb_max.y, scene_bb_min.z},
        {scene_bb_max.x, scene_bb_max.y, scene_bb_max.z},
    }

    defer common.destory_obj_data(scene_data)
    scene.gpu_data = common.send_obj_to_gpu(scene_data)
    defer common.destroy_gpu_obj_data(scene.gpu_data)

    debug_rect_shaders := common.compile_shader_program({
        vertex_source = #load("debug.vert", string),
        fragment_source = #load("debug.frag", string),
    }) or_return
    defer common.destroy_shader_program(debug_rect_shaders)
    debug_rect.program = debug_rect_shaders.program
    common.get_uniform_locations(debug_rect.program, &debug_rect.uniforms)

    gl.GenVertexArrays(1, &debug_rect.vao)
    defer gl.DeleteVertexArrays(1, &debug_rect.vao)

    shadow_map_resolution: i32 = 1024
    shadow_map: u32
    gl.GenTextures(1, &shadow_map)
    gl.BindTexture(gl.TEXTURE_2D, shadow_map)
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    // gl.TexImage2D(
    //     gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT24, shadow_map_resolution, shadow_map_resolution, 0,
    //     gl.DEPTH_COMPONENT, gl.FLOAT, nil
    // )
    gl.TexImage2D(
        gl.TEXTURE_2D, 0, gl.RG32F, shadow_map_resolution, shadow_map_resolution, 0,
        gl.RGBA, gl.FLOAT, nil
    )

    shadow_depth_rbo: u32
    gl.GenRenderbuffers(1, &shadow_depth_rbo)
    gl.BindRenderbuffer(gl.RENDERBUFFER, shadow_depth_rbo)
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, shadow_map_resolution, shadow_map_resolution)

    shadow_fbo: u32
    gl.GenFramebuffers(1, &shadow_fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, shadow_fbo)
    // gl.FramebufferTexture(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, shadow_map, 0)
    gl.FramebufferTexture(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, shadow_map, 0)
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, shadow_depth_rbo)

    if (gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
        return "Failed to create shadow framebuffer"
    }
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

    free_all(context.temp_allocator)

    last_frame_start := timelib.now()
    time: f32 = 0.0
    paused := false

    button_down: map[sdl.Keycode]bool
    defer delete(button_down)

    view_elevation := math.to_radians_f32(45.0)
    view_azimuth: f32 = 0.0
    camera_distance: f32 = 1.5

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

        SPEED :: 1.0
        ROTATION_SPEED :: 2.0
        if button_down[.UP] || button_down[.W] do camera_distance -= SPEED * dt
        if button_down[.DOWN] || button_down[.S] do camera_distance += SPEED * dt
        if button_down[.LEFT] || button_down[.A] do view_azimuth -= ROTATION_SPEED * dt
        if button_down[.RIGHT] || button_down[.D] do view_azimuth += ROTATION_SPEED * dt

        model := linalg.MATRIX4F32_IDENTITY

        light_direction := linalg.normalize([3]f32{math.cos(time * 0.5), 1.0, math.sin(time * 0.5)})

        gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, shadow_fbo)
        gl.ClearColor(1, 1, 0, 0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
        gl.Viewport(0, 0, shadow_map_resolution, shadow_map_resolution)
        gl.Enable(gl.DEPTH_TEST)
        gl.DepthFunc(gl.LEQUAL)
        gl.Enable(gl.CULL_FACE)
        gl.CullFace(gl.BACK)

        light_z := -light_direction;
        light_x := linalg.normalize(linalg.cross(light_z, [3]f32{0.0, 1.0, 0.0}))
        light_y := linalg.cross(light_x, light_z)
        shadow_scale: f32 = 2

        // transform := linalg.transpose(matrix[4, 4]f32{
        //     shadow_scale * light_x.x, shadow_scale * light_y.x, shadow_scale * light_z.x, 0,
        //     shadow_scale * light_x.y, shadow_scale * light_y.y, shadow_scale * light_z.y, 0,
        //     shadow_scale * light_x.z, shadow_scale * light_y.z, shadow_scale * light_z.z, 0,
        //     0, 0, 0, 1,
        // })

        furthest_point_along_direction :: proc(dir, o: [3]f32, points: [][3]f32) -> (result: f32) {
            result = -math.INF_F32
            for p in points do result = max(result, abs(linalg.dot(dir, p - o)))
            return
        }

        light_x *= furthest_point_along_direction(light_x, scene_bb_center, scene_bb_vertices[:])
        light_y *= furthest_point_along_direction(light_y, scene_bb_center, scene_bb_vertices[:])
        light_z *= furthest_point_along_direction(light_z, scene_bb_center, scene_bb_vertices[:])
        transform := linalg.inverse(matrix[4, 4]f32{
            light_x.x, light_y.x, light_z.x, scene_bb_center.x,
            light_x.y, light_y.y, light_z.y, scene_bb_center.y,
            light_x.z, light_y.z, light_z.z, scene_bb_center.z,
            0, 0, 0, 1,
        })

        flat_model := linalg.matrix_flatten(model)
        flat_transform := linalg.matrix_flatten(transform)

        gl.UseProgram(scene.shadow_program)
        gl.UniformMatrix4fv(scene.shadow_uniforms.model, 1, false, raw_data(flat_model[:]))
        gl.UniformMatrix4fv(scene.shadow_uniforms.transform, 1, false, raw_data(flat_transform[:]))

        gl.BindVertexArray(scene.vao)
        gl.DrawElements(gl.TRIANGLES, scene.indices_count, gl.UNSIGNED_INT, nil)

        gl.BindTexture(gl.TEXTURE_2D, shadow_map)
        gl.GenerateMipmap(gl.TEXTURE_2D)

        gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, 0)
        gl.Viewport(0, 0, dimensions.x, dimensions.y)

        gl.ClearColor(0.8, 0.8, 0.9, 0.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
        gl.Enable(gl.DEPTH_TEST)
        gl.DepthFunc(gl.LEQUAL)
        gl.Enable(gl.CULL_FACE)
        gl.CullFace(gl.BACK)

        near: f32 = 0.01
        far: f32 = 10.0

        view :=
            linalg.matrix4_translate_f32({0, 0, -camera_distance}) * 
            linalg.matrix4_rotate_f32(view_elevation, {1, 0, 0}) *
            linalg.matrix4_rotate_f32(view_azimuth, {0, 1, 0})

        projection := linalg.matrix4_perspective_f32(math.PI / 2, f32(dimensions.x) / f32(dimensions.y), near, far)

        gl.BindTexture(gl.TEXTURE_2D, shadow_map)

        gl.UseProgram(scene.program)

        flat_model = linalg.matrix_flatten(model)
        flat_view := linalg.matrix_flatten(view)
        flat_projection := linalg.matrix_flatten(projection)
        flat_transform = linalg.matrix_flatten(transform)

        gl.UniformMatrix4fv(scene.uniforms.model, 1, false, raw_data(flat_model[:]))
        gl.UniformMatrix4fv(scene.uniforms.view, 1, false, raw_data(flat_view[:]))
        gl.UniformMatrix4fv(scene.uniforms.projection, 1, false, raw_data(flat_projection[:]))
        gl.UniformMatrix4fv(scene.uniforms.transform, 1, false, raw_data(flat_transform[:]))

        gl.Uniform3f(scene.uniforms.ambient, 0.2, 0.2, 0.2)
        gl.Uniform3f(scene.uniforms.light_direction, light_direction.x, light_direction.y, light_direction.z)
        gl.Uniform3f(scene.uniforms.light_color, 0.8, 0.8, 0.8)

        gl.BindVertexArray(scene.vao)
        gl.DrawElements(gl.TRIANGLES, scene.indices_count, gl.UNSIGNED_INT, nil)

        gl.UseProgram(debug_rect.program)
        gl.BindTexture(gl.TEXTURE_2D, shadow_map)
        gl.BindVertexArray(debug_rect.vao)
        gl.DrawArrays(gl.TRIANGLES, 0, 6)

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
