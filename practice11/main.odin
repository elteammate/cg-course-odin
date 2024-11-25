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

Particle :: struct {
    position: [3]f32 `gl:"location=0"`,
    size: f32 `gl:"location=1"`,
    rotation: f32 `gl:"location=2"`,
    velocity: [3]f32,
    angular_velocity: f32,
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


sdf :: proc(p: [3]f32) -> f32 {
    return min(
        linalg.length2(p - [3]f32{-0.3, 0.5, 0}) - 0.5,
        linalg.length2(p - [3]f32{0.3, 0.5, 0}) - 0.5,
    )
}

potential_field :: proc(p: [3]f32) -> f32 {
    f := sdf(p)
    return f > 0 ? f : -f * 5.0
}

grad :: proc(p: [3]f32, f: $F) -> [3]f32{
    EPS :: 1e-5
    return {
        (f(p + [3]f32{EPS, 0, 0}) - f(p - [3]f32{EPS, 0, 0})) / (2 * EPS),
        (f(p + [3]f32{0, EPS, 0}) - f(p - [3]f32{0, EPS, 0})) / (2 * EPS),
        (f(p + [3]f32{0, 0, EPS}) - f(p - [3]f32{0, 0, EPS})) / (2 * EPS),
    }
}

force :: proc(p: [3]f32) -> [3]f32 {
    return -grad(p, potential_field) * 0.5 + [3]f32{0, 1, 0}
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
        "Graphics course practice 11",
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

    gl.ClearColor(0.0, 0.0, 0.0, 0.0)

    shaders := common.compile_shader_program({
        vertex_source = #load("shader.vert", string),
        geometry_source = #load("shader.geom", string),
        fragment_source = #load("shader.frag", string),
    }) or_return

    uniforms: struct {
        model, view, projection, camera_position, tex, palette: i32
    }
    common.get_uniform_locations(shaders.program, &uniforms, ignore_missing = true)

    MAX_PARTICLES :: 4096
    FRICTION: f32 = 0.1
    DECAY: f32 = 0.7
    PARTICLES_PER_SECOND: f32 = 300.0

    particles := make([dynamic]Particle, 0, MAX_PARTICLES)
    /*
    for &p in particles {
        p = {
            position = {
                rand.float32_range(-1.0, 1.0),
                0,
                rand.float32_range(-1.0, 1.0),
            },
            size = rand.float32_range(0.2, 0.4),
            velocity = {
                rand.float32_range(-0.1, 0.1),
                rand.float32_range(-0.1, 0.1),
                rand.float32_range(-0.1, 0.1),
            },
            angular_velocity = rand.float32_range(-1, 1),
        }
    }
    */

    emit_budget: f32 = 0

    gpu_particles: struct {
        vao, vbo: u32,
    }

    gl.GenVertexArrays(1, &gpu_particles.vao)
    gl.BindVertexArray(gpu_particles.vao)

    gl.GenBuffers(1, &gpu_particles.vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, gpu_particles.vbo)
    common.configure_vao_attributes(Particle)

    texture: u32 = load_texture("practice11/particle.png")

    palette: u32
    gl.GenTextures(1, &palette)
    gl.BindTexture(gl.TEXTURE_1D, palette)
    palette_colors := [?][3]u8{
        {0, 0, 0},
        {20, 20, 150},
        {40, 60, 255},
        {120, 160, 255},
        {255, 255, 255},
    }
    gl.TexImage1D(gl.TEXTURE_1D, 0, gl.RGB8, len(palette_colors), 0, gl.RGB, gl.UNSIGNED_BYTE, raw_data(palette_colors[:]))
    gl.TexParameteri(gl.TEXTURE_1D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_1D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_1D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)

    gl.PointSize(5.0)

    free_all(context.temp_allocator)

    last_frame_start := timelib.now()
    time: f32 = 0.0
    paused := false

    button_down: map[sdl.Keycode]bool
    defer delete(button_down)

    view_angle: f32 = 0.0
    camera_distance: f32 = 2.0
    camera_height: f32 = 0.5
    camera_rotation: f32 = 0.0

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

        if !running do break

        current_time := timelib.now()
        defer last_frame_start = current_time
        dt := cast(f32)timelib.duration_seconds(timelib.diff(last_frame_start, current_time))
        if !paused do time += dt

        if !paused {
            for &p in particles {
                p.velocity += force(p.position) * dt
                p.position += p.velocity * dt
                p.size *= math.pow(DECAY, dt)
                p.velocity *= math.pow(FRICTION, dt)
                p.rotation += p.angular_velocity * dt
            }

            for i := 0; i < len(particles); i += 1 {
                p := particles[i]
                if p.size < 1e-2 { 
                    particles[i] = particles[len(particles) - 1]
                    i -= 1
                    pop(&particles) 
                }
            }

            emit_budget += PARTICLES_PER_SECOND * dt

            for len(particles) < MAX_PARTICLES {
                if emit_budget <= 1 { break }
                emit_budget -= 1
                phi := rand.float32_range(0, 2 * math.PI)
                r := math.sqrt(rand.float32_range(0, 1))

                p := Particle{
                    position = linalg.matrix3_rotate_f32(phi, {0, 1, 0}) * [3]f32{r, -0.5, 0},
                    size = rand.float32_range(0.2, 0.3),
                    velocity = linalg.matrix3_rotate_f32(phi + math.PI / 2, {0, 1, 0}) * [3]f32{0.2, 0, 0},
                    angular_velocity = rand.float32_range(-1, 1),
                }
                append(&particles, p)
            }
            if len(particles) == MAX_PARTICLES {
                emit_budget = 0
            }
        }

        if button_down[.UP] || button_down[.W] do camera_distance -= 3.0 * dt
        if button_down[.DOWN] || button_down[.S] do camera_distance += 3.0 * dt
        if button_down[.LEFT] || button_down[.A] do camera_rotation -= 3.0 * dt
        if button_down[.RIGHT] || button_down[.D] do camera_rotation += 3.0 * dt

        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
        gl.Disable(gl.DEPTH_TEST)
        gl.Enable(gl.BLEND)
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE)

        near: f32 = 0.1
        far: f32 = 100.0

        model := linalg.MATRIX4F32_IDENTITY

        view :=
            linalg.matrix4_translate_f32({0, -camera_height, -camera_distance}) *
            linalg.matrix4_rotate_f32(view_angle, {1, 0, 0}) *
            linalg.matrix4_rotate_f32(camera_rotation, {0, 1, 0})

        projection := linalg.matrix4_perspective_f32(math.PI / 2, f32(dimensions.x) / f32(dimensions.y), near, far)

        camera_position := (linalg.inverse(view) * [4]f32{0, 0, 0, 1}).xyz

        gl.BindBuffer(gl.ARRAY_BUFFER, gpu_particles.vbo)
        gl.BufferData(gl.ARRAY_BUFFER, len(particles) * size_of(Particle), raw_data(particles[:]), gl.STATIC_DRAW)

        gl.UseProgram(shaders.program)
        gl.UniformMatrix4fv(uniforms.model, 1, false, &model[0, 0])
        gl.UniformMatrix4fv(uniforms.view, 1, false, &view[0, 0])
        gl.UniformMatrix4fv(uniforms.projection, 1, false, &projection[0, 0])
        gl.Uniform3fv(uniforms.camera_position, 1, raw_data(camera_position[:]))
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, texture)
        gl.Uniform1i(uniforms.tex, 0)
        gl.ActiveTexture(gl.TEXTURE1)
        gl.BindTexture(gl.TEXTURE_1D, palette)
        gl.Uniform1i(uniforms.palette, 1)

        gl.BindVertexArray(gpu_particles.vao)
        gl.DrawArrays(gl.POINTS, 0, cast(i32)len(particles))

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
