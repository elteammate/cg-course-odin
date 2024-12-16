package main

import "core:fmt"
import "core:strings"
import "core:c"
import "core:os"
import "core:mem"
import "core:slice"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "core:reflect"
import "core:testing"
import "core:c/libc"
import timelib "core:time"

import gl "vendor:OpenGL"
import sdl "vendor:sdl2"
import stb_img "vendor:stb/image"

import common "../common"

TEXTURE_UNIT_ALBEDO :: 0
TRANSPARENCY_TEXTURE_UNIT :: 1
SUN_SHADOW_TEXTURE_UNIT :: 2
POINT_SHADOW_TEXTURE_UNIT :: 3

SHADOW_BIAS :: 1e-2

rect_vao: u32

Vertex :: struct {
    position: [3]f32,
    normal: [3]f32,
    texcoord: [2]f32,
}

Material_Gpu :: struct {
    id: int,
    albedo: [3]f32,
    albedo_texture: u32,
    use_albedo_for_transparency: bool,
    transparency: f32,
    transparency_texture: u32,
    glossiness: [3]f32,
    power: f32,
}

Object :: struct {
    name: string,
    material_name: string,
    material_id: int,
    vertices: []Vertex,
    indices: []u32,
}

Object_Gpu :: struct {
    vao: u32,
    vbo: u32,
    ebo: u32,
    vertex_count: i32,
    material_id: int,
}

Tone_Mapping :: enum {
    None, Reinhard, Arctan, Uncharted2, ACES
}

Uniforms :: struct {
    model, view, projection,
    transform,

    albedo, albedo_tex, use_albedo_tex,
    transparency_tex, use_transparency_tex,
    use_albedo_for_transparency,
    glossiness, power,

    camera_position, view_direction,

    ambient,
    sun_direction, sun_color, sun_shadow_map, sun_transform,
    point_light_count,
    point_position, point_color, point_attenuation,
    point_zero_has_shadow, point_zero_shadow_map,
    shadow_bias, is_point,
    tone_mapping,

    dummy: i32
}

Debug_Uniforms :: struct {
    center, size, tex: i32
}

send_object_to_gpu :: proc(object: ^Object) -> (o: Object_Gpu) {
    gl.GenVertexArrays(1, &o.vao)
    gl.GenBuffers(1, &o.vbo)
    gl.GenBuffers(1, &o.ebo)

    gl.BindVertexArray(o.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, o.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(object.vertices) * size_of(Vertex), raw_data(object.vertices), gl.STATIC_DRAW)

    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, o.ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(object.indices) * size_of(u32), raw_data(object.indices), gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.EnableVertexAttribArray(1)
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, position))
    gl.VertexAttribPointer(1, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, normal))
    gl.VertexAttribPointer(2, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, texcoord))

    o.vertex_count = cast(i32)len(object.indices)
    o.material_id = object.material_id

    return
}

load_texture :: proc(
    path: string,
    components: i32 = 3,
    mipmaps: enum {
        None, SRGB, Linear,
    } = .None,
    internal_format: i32 = gl.RGB8,
    min_filter: i32 = gl.LINEAR_MIPMAP_LINEAR,
    mag_filter: i32 = gl.LINEAR,
    wrap_s: i32 = gl.REPEAT,
    wrap_t: i32 = gl.REPEAT,
) -> (texture: u32, error: Maybe(string)) {
    if mipmaps != .None {
        assert(
            min_filter == gl.LINEAR_MIPMAP_LINEAR ||
            min_filter == gl.NEAREST_MIPMAP_NEAREST ||
            min_filter == gl.LINEAR_MIPMAP_NEAREST ||
            min_filter == gl.NEAREST_MIPMAP_LINEAR
        )
    } else {
        assert(
            min_filter == gl.LINEAR ||
            min_filter == gl.NEAREST
        )
    }
    assert(
        mag_filter == gl.LINEAR ||
        mag_filter == gl.NEAREST
    )

    gl.GenTextures(1, &texture)
    gl.BindTexture(gl.TEXTURE_2D, texture)

    cpath := strings.clone_to_cstring(path, context.temp_allocator)
    defer delete(cpath, context.temp_allocator)

    width, height, n_channels: c.int
    stb_img.set_flip_vertically_on_load(1)
    data := stb_img.load(cpath, &width, &height, &n_channels, c.int(components))
    if data == nil {
        return 0, fmt.tprintf("Failed to load texture %s", path)
    }
    defer stb_img.image_free(data)

    external_formats := [?]u32{0, gl.RED, gl.RG, gl.RGB, gl.RGBA}

    gl.TexImage2D(
        gl.TEXTURE_2D, 0, internal_format, width, height, 0,
        external_formats[components], gl.UNSIGNED_BYTE, data,
    )

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap_s)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap_t)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, min_filter)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, mag_filter)

    if mipmaps == .None do return

    w1, h1 := width, height
    w2, h2 := w1 / 2, h1 / 2
    pixels1 := make([]byte, w1 * h1 * components)
    pixels2 := make([]byte, w2 * h2 * components)

    mem.copy(raw_data(pixels1), data, len(pixels1))
    level: i32 = 1

    for ; w2 > 0 && h2 > 0; level += 1 {
        for y in 0..<h2 {
            for x in 0..<w2 {
                for c in 0..<components {
                    p00 := cast(f32)pixels1[((y * 2) * w1 + x * 2) * components + c]
                    p01 := cast(f32)pixels1[((y * 2) * w1 + x * 2 + 1) * components + c]
                    p10 := cast(f32)pixels1[((y * 2 + 1) * w1 + x * 2) * components + c]
                    p11 := cast(f32)pixels1[((y * 2 + 1) * w1 + x * 2 + 1) * components + c]

                    if mipmaps == .Linear && c != 3 {
                        p00 = math.pow(p00 / 255, 2.2) * 255
                        p01 = math.pow(p01 / 255, 2.2) * 255
                        p10 = math.pow(p10 / 255, 2.2) * 255
                        p11 = math.pow(p11 / 255, 2.2) * 255
                    }

                    p := (p00 + p01 + p10 + p11) / 4

                    if mipmaps == .Linear && c != 3 {
                        p = math.pow(p / 255, 1 / 2.2) * 255
                    }

                    pixels2[(y * w2 + x) * components + c] = cast(u8)math.round(p)
                }
            }
        }

        gl.TexImage2D(
            gl.TEXTURE_2D, level, internal_format, w2, h2, 0,
            external_formats[components], gl.UNSIGNED_BYTE, raw_data(pixels2),
        )

        mem.copy(raw_data(pixels1), raw_data(pixels2), len(pixels2))

        w1, h1 = w2, h2
        w2, h2 = w1 / 2, h1 / 2
    }

    delete(pixels1)
    delete(pixels2)

    return
}

ALBEDO_TEXTURE_CACHE: map[string]u32
TRANSPARENCY_TEXTURE_CACHE: map[string]u32

send_material_to_gpu :: proc(
    mat: ^Material_Data,
    gamma_correction: bool = true,
) -> (m: Material_Gpu, error: Maybe(string)) {
    if tex, present := mat.albedo_texture.?; present && tex == mat.transparency_texture {
        m.albedo_texture = ALBEDO_TEXTURE_CACHE[tex]
        if m.albedo_texture == 0 {
            m.albedo_texture = load_texture(
                tex,
                mipmaps = gamma_correction ? .Linear : .SRGB,
                internal_format = gamma_correction ? gl.SRGB8_ALPHA8 : gl.RGBA8,
                components = 4,
            ) or_return
            ALBEDO_TEXTURE_CACHE[tex] = m.albedo_texture
        }
        m.use_albedo_for_transparency = true
    } else {
        if tex, present := mat.albedo_texture.?; present {
            m.albedo_texture = ALBEDO_TEXTURE_CACHE[tex]
            if m.albedo_texture == 0 {
                m.albedo_texture = load_texture(
                    tex,
                    mipmaps = gamma_correction ? .Linear : .SRGB,
                    internal_format = gamma_correction ? gl.SRGB8 : gl.RGB8,
                    components = 3,
                ) or_return
                ALBEDO_TEXTURE_CACHE[tex] = m.albedo_texture
            }
        }

        if tex, present := mat.transparency_texture.?; present {
            m.transparency_texture = TRANSPARENCY_TEXTURE_CACHE[tex]
            if m.transparency_texture == 0 {
                m.transparency_texture = load_texture(
                    tex,
                    mipmaps = .SRGB,
                    components = 1,
                ) or_return
                TRANSPARENCY_TEXTURE_CACHE[tex] = m.transparency_texture
            }
        }
    }

    m.id = mat.id
    m.albedo = mat.albedo
    m.transparency = mat.transparency
    m.power = mat.power
    m.glossiness = mat.glossiness

    return
}

prepare_object_shader_program :: proc(program: u32, uniforms: ^Uniforms) {
    gl.UseProgram(program)
    gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, 0)
    gl.Uniform1i(uniforms.albedo_tex, TEXTURE_UNIT_ALBEDO)
    gl.Uniform1f(uniforms.shadow_bias, SHADOW_BIAS)
    gl.Uniform1i(uniforms.transparency_tex, TRANSPARENCY_TEXTURE_UNIT)
    tone_mapping: i32 = 0
    switch config.tone_mapping {
        case .None:
            tone_mapping = 0
        case .Reinhard:
            tone_mapping = 1
        case .Arctan:
            tone_mapping = 2
        case .ACES:
            tone_mapping = 3
        case .Uncharted2:
            tone_mapping = 4
    }
    gl.Uniform1i(uniforms.tone_mapping, tone_mapping)
}

bind_material :: proc(mat: Material_Gpu, uniforms: ^Uniforms) {
    mat := mat

    use_albedo_tex := mat.albedo_texture != 0
    gl.Uniform1i(uniforms.use_albedo_tex, cast(i32)use_albedo_tex)
    if use_albedo_tex {
        gl.ActiveTexture(gl.TEXTURE0 + TEXTURE_UNIT_ALBEDO)
        gl.BindTexture(gl.TEXTURE_2D, mat.albedo_texture)
    } else {
        gl.Uniform3fv(uniforms.albedo, 1, raw_data(mat.albedo[:]))
    }

    use_transparency := mat.transparency_texture != 0
    gl.Uniform1i(uniforms.use_transparency_tex, cast(i32)use_transparency)
    gl.Uniform1i(uniforms.use_albedo_for_transparency, cast(i32)mat.use_albedo_for_transparency)
    if use_transparency {
        gl.ActiveTexture(gl.TEXTURE0 + TRANSPARENCY_TEXTURE_UNIT)
        gl.BindTexture(gl.TEXTURE_2D, mat.transparency_texture)
    }

    gl.Uniform3fv(uniforms.glossiness, 1, raw_data(mat.glossiness[:]))
    gl.Uniform1f(uniforms.power, mat.power)
}

CUBEMAP_SIDES := [?]u32{
    gl.TEXTURE_CUBE_MAP_POSITIVE_X, gl.TEXTURE_CUBE_MAP_NEGATIVE_X,
    gl.TEXTURE_CUBE_MAP_POSITIVE_Y, gl.TEXTURE_CUBE_MAP_NEGATIVE_Y,
    gl.TEXTURE_CUBE_MAP_POSITIVE_Z, gl.TEXTURE_CUBE_MAP_NEGATIVE_Z,
}

CUBEMAP_FACE_ORIENTATIONS := [6][2][3]f32{
    {{1, 0, 0}, {0, -1, 0}},
    {{-1, 0, 0}, {0, -1, 0}},
    {{0, 1, 0}, {0, 0, 1}},
    {{0, -1, 0}, {0, 0, -1}},
    {{0, 0, 1}, {0, -1, 0}},
    {{0, 0, -1}, {0, -1, 0}},
}

SUN_SHADOW_MAP_SIZE :: 1024
POINT_SHADOW_MAP_SIZE :: 512

MAX_POINT_LIGHTS :: 8

Lights :: struct {
    ambient: [3]f32,

    sun_direction: [3]f32,
    sun_color: [3]f32,
    sun_shadow_map: u32,
    sun_shadow_fbo: u32,
    sun_shadow_rbo_depth: u32,
    cached_sun_transform: matrix[4, 4]f32,

    point_light_number: i32,
    point_position: [MAX_POINT_LIGHTS][3]f32,
    point_color: [MAX_POINT_LIGHTS][3]f32,
    point_attenuation: [MAX_POINT_LIGHTS][3]f32,
    point_zero_shadow_map: u32,
    point_zero_shadow_depth: u32,
    point_zero_shadow_fbos: [6]u32,
    cached_point_transform: matrix[4, 4]f32,
    near: f32,
    far: f32,
}

init_lights :: proc(lights: ^Lights) {
    gl.GenTextures(1, &lights.sun_shadow_map)
    gl.BindTexture(gl.TEXTURE_2D, lights.sun_shadow_map)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RG32F, SUN_SHADOW_MAP_SIZE, SUN_SHADOW_MAP_SIZE, 0, gl.RGBA, gl.FLOAT, nil)

    gl.GenRenderbuffers(1, &lights.sun_shadow_rbo_depth)
    gl.BindRenderbuffer(gl.RENDERBUFFER, lights.sun_shadow_rbo_depth)
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, SUN_SHADOW_MAP_SIZE, SUN_SHADOW_MAP_SIZE)

    gl.GenFramebuffers(1, &lights.sun_shadow_fbo)
    gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, lights.sun_shadow_fbo)
    gl.FramebufferTexture2D(gl.DRAW_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, lights.sun_shadow_map, 0)
    gl.FramebufferRenderbuffer(gl.DRAW_FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, lights.sun_shadow_rbo_depth)

    gl.GenTextures(1, &lights.point_zero_shadow_map)
    gl.BindTexture(gl.TEXTURE_CUBE_MAP, lights.point_zero_shadow_map)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    for side in CUBEMAP_SIDES {
        gl.TexImage2D(side, 0, gl.RG32F, POINT_SHADOW_MAP_SIZE, POINT_SHADOW_MAP_SIZE, 0, gl.RGBA, gl.FLOAT, nil)
    }

    gl.GenRenderbuffers(1, &lights.point_zero_shadow_depth)
    gl.BindRenderbuffer(gl.RENDERBUFFER, lights.point_zero_shadow_depth)
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, POINT_SHADOW_MAP_SIZE, POINT_SHADOW_MAP_SIZE)

    gl.GenFramebuffers(6, raw_data(lights.point_zero_shadow_fbos[:]))
    for i in 0..<6 {
        gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, lights.point_zero_shadow_fbos[i])
        gl.FramebufferTexture2D(gl.DRAW_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, CUBEMAP_SIDES[i], lights.point_zero_shadow_map, 0)
        gl.FramebufferRenderbuffer(gl.DRAW_FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, lights.point_zero_shadow_depth)
    }
}

lights_push_point :: proc(lights: ^Lights, position, color, attenuation: [3]f32) {
    assert(lights.point_light_number < MAX_POINT_LIGHTS)

    lights.point_position[lights.point_light_number] = position
    lights.point_color[lights.point_light_number] = color
    lights.point_attenuation[lights.point_light_number] = attenuation
    lights.point_light_number += 1
}

bind_shadow_map :: proc(lights: ^Lights, uniforms: ^Uniforms, i: int, scene_aabb: AABB) {
    assert(0 <= i && i < 7)

    if i == 0 {
        light_z := -lights.sun_direction;
        light_x := linalg.normalize(linalg.cross(light_z, [3]f32{0.0, 1.0, 0.0}))
        light_y := linalg.normalize(linalg.cross(light_x, light_z))

        furthest_point_along_direction :: proc(dir, o: [3]f32, points: [][3]f32) -> (result: f32) {
            result = -math.INF_F32
            for p in points do result = max(result, linalg.dot(dir, p - o))
            return
        }

        scene_center := (scene_aabb.min + scene_aabb.max) * 0.5
        aabb_vertices := aabb_vertices(scene_aabb)

        light_x *= furthest_point_along_direction(light_x, scene_center, aabb_vertices[:])
        light_y *= furthest_point_along_direction(light_y, scene_center, aabb_vertices[:])
        light_z *= furthest_point_along_direction(light_z, scene_center, aabb_vertices[:])
        transform := linalg.inverse(matrix[4, 4]f32{
            light_x.x, light_y.x, light_z.x, scene_center.x,
            light_x.y, light_y.y, light_z.y, scene_center.y,
            light_x.z, light_y.z, light_z.z, scene_center.z,
            0, 0, 0, 1,
        })
        lights.cached_sun_transform = transform

        flat_transform := linalg.matrix_flatten(transform)
        gl.UniformMatrix4fv(uniforms.transform, 1, false, raw_data(flat_transform[:]))
        gl.Uniform1i(uniforms.is_point, 0)

        gl.Viewport(0, 0, SUN_SHADOW_MAP_SIZE, SUN_SHADOW_MAP_SIZE)
        gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, lights.sun_shadow_fbo)
    } else if config.point_light_zero_shadow && lights.point_light_number > 0 {
        i := i - 1
        side := CUBEMAP_SIDES[i]

        transform := linalg.matrix4_perspective_f32(
            math.PI / 2, 1, lights.near, lights.far,
        ) * linalg.matrix4_look_at_f32(
            lights.point_position[0],
            lights.point_position[0] + CUBEMAP_FACE_ORIENTATIONS[i][0],
            CUBEMAP_FACE_ORIENTATIONS[i][1],
        )
        lights.cached_point_transform = transform

        flat_transform := linalg.matrix_flatten(transform)
        gl.UniformMatrix4fv(uniforms.transform, 1, false, raw_data(flat_transform[:]))
        gl.Uniform1i(uniforms.is_point, 1)
        gl.Uniform3fv(uniforms.point_position, 1, &lights.point_position[0][0])

        gl.Viewport(0, 0, POINT_SHADOW_MAP_SIZE, POINT_SHADOW_MAP_SIZE)
        gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, lights.point_zero_shadow_fbos[i])
    }
}

bind_lights :: proc(lights: Lights, uniforms: ^Uniforms) {
    lights := lights

    gl.Uniform3fv(uniforms.ambient, 1, raw_data(lights.ambient[:]))
    gl.Uniform3fv(uniforms.sun_direction, 1, raw_data(lights.sun_direction[:]))
    gl.Uniform3fv(uniforms.sun_color, 1, raw_data(lights.sun_color[:]))
    gl.UniformMatrix4fv(uniforms.sun_transform, 1, false, &lights.cached_sun_transform[0, 0])

    n := lights.point_light_number
    gl.Uniform1i(uniforms.point_light_count, n)
    gl.Uniform3fv(uniforms.point_position, n, &lights.point_position[0][0])
    gl.Uniform3fv(uniforms.point_color, n, &lights.point_color[0][0])
    gl.Uniform3fv(uniforms.point_attenuation, n, &lights.point_attenuation[0][0])

    gl.ActiveTexture(gl.TEXTURE0 + SUN_SHADOW_TEXTURE_UNIT)
    gl.BindTexture(gl.TEXTURE_2D, lights.sun_shadow_map)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.Uniform1i(uniforms.sun_shadow_map, SUN_SHADOW_TEXTURE_UNIT)

    gl.ActiveTexture(gl.TEXTURE0 + POINT_SHADOW_TEXTURE_UNIT)
    gl.BindTexture(gl.TEXTURE_CUBE_MAP, lights.point_zero_shadow_map)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.Uniform1i(uniforms.point_zero_has_shadow, config.point_light_zero_shadow ? 1 : 0)
    gl.Uniform1i(uniforms.point_zero_shadow_map, POINT_SHADOW_TEXTURE_UNIT)
}

bind_object :: proc(obj: Object_Gpu, uniforms: ^Uniforms) {
    gl.BindVertexArray(obj.vao)

    model := linalg.MATRIX4F32_IDENTITY
    flat_model := linalg.matrix_flatten(model)
    gl.UniformMatrix4fv(uniforms.model, 1, false, raw_data(flat_model[:]))
}

debug_draw :: proc(center: [2]f32, size: [2]f32, tex: u32, uniforms: ^Debug_Uniforms, debug_program: u32) {
    center := center
    size := size

    gl.Disable(gl.DEPTH_TEST)
    defer gl.Enable(gl.DEPTH_TEST)

    gl.UseProgram(debug_program)
    gl.Uniform2fv(uniforms.center, 1, raw_data(center[:]))
    gl.Uniform2fv(uniforms.size, 1, raw_data(size[:]))

    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, tex)
    gl.Uniform1i(uniforms.tex, 0)

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)

    gl.BindVertexArray(rect_vao)
    gl.DrawArrays(gl.TRIANGLES, 0, 6)
}

Camera_Controls :: struct {
    position: [3]f32,
    fov: f32,
    near, far: f32,
    yaw, pitch, roll: f32,
    up: [3]f32,
}

Camera :: struct {
    using controls: Camera_Controls,

    projection_matrix: matrix[4, 4]f32,
    forward: [3]f32,
    right: [3]f32,
    view_matrix: matrix[4, 4]f32,
}

AABB :: struct {
    min, max: [3]f32,
}

AABB_EMPTY :: AABB{
    min = {math.INF_F32, math.INF_F32, math.INF_F32}, max = {-math.INF_F32, -math.INF_F32, -math.INF_F32}
}

aabb_update :: proc(aabb: ^AABB, point: [3]f32) {
    aabb.min = linalg.min(aabb.min, point)
    aabb.max = linalg.max(aabb.max, point)
}

aabb_vertices :: proc(aabb: AABB) -> [8][3]f32 {
    return {
        {aabb.min.x, aabb.min.y, aabb.min.z},
        {aabb.min.x, aabb.min.y, aabb.max.z},
        {aabb.min.x, aabb.max.y, aabb.min.z},
        {aabb.min.x, aabb.max.y, aabb.max.z},
        {aabb.max.x, aabb.min.y, aabb.min.z},
        {aabb.max.x, aabb.min.y, aabb.max.z},
        {aabb.max.x, aabb.max.y, aabb.min.z},
        {aabb.max.x, aabb.max.y, aabb.max.z},
    }
}

aabb_diagonal :: proc(aabb: AABB) -> f32 {
    return linalg.length(aabb.max - aabb.min)
}

compute_camera :: proc(controls: Camera_Controls, dimensions: [2]i32) -> (c: Camera) {
    c.controls = controls

    c.projection_matrix = linalg.matrix4_perspective_f32(
        controls.fov,
        cast(f32)dimensions.x / cast(f32)dimensions.y,
        controls.near,
        controls.far,
    )

    c.forward = linalg.quaternion128_mul_vector3(
        linalg.quaternion_from_pitch_yaw_roll(controls.pitch, controls.yaw, controls.roll),
        [3]f32{0, 0, 1}
    )

    c.right = linalg.normalize(linalg.cross(c.forward, controls.up))

    c.view_matrix = linalg.matrix4_look_at_f32(
        controls.position,
        controls.position + c.forward,
        controls.up,
    )

    return
}

bind_camera :: proc(cam: Camera, uniforms: ^Uniforms) {
    cam := cam
    flat_view := linalg.matrix_flatten(cam.view_matrix)
    flat_projection := linalg.matrix_flatten(cam.projection_matrix)

    gl.UniformMatrix4fv(uniforms.view, 1, false, &flat_view[0])
    gl.UniformMatrix4fv(uniforms.projection, 1, false, &flat_projection[0])
    gl.Uniform3fv(uniforms.camera_position, 1, raw_data(cam.position[:]))
    gl.Uniform3fv(uniforms.view_direction, 1, raw_data(cam.forward[:]))
}

Blur_Pass_Uniforms :: struct {
    center, size, tex, vertical, side: i32
}

Blur_Gpu :: struct {
    fbo: u32,
    temp_texture_2d: u32,
    temp_texture_cube: u32,
}

configure_texture_for_blur :: proc(target: u32, texture: u32) {
    gl.BindTexture(target, texture)
    gl.TexParameteri(target, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(target, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    if target != gl.TEXTURE_CUBE_MAP {
        gl.TexParameteri(target, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
        gl.TexParameteri(target, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    }
}

init_blur_2d :: proc() -> (blur: Blur_Gpu) {
    gl.GenFramebuffers(1, &blur.fbo)

    gl.GenTextures(1, &blur.temp_texture_2d)
    configure_texture_for_blur(gl.TEXTURE_2D, blur.temp_texture_2d)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RG32F, SUN_SHADOW_MAP_SIZE, SUN_SHADOW_MAP_SIZE, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)

    gl.GenTextures(1, &blur.temp_texture_cube)
    configure_texture_for_blur(gl.TEXTURE_2D, blur.temp_texture_cube)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RG32F, POINT_SHADOW_MAP_SIZE, POINT_SHADOW_MAP_SIZE, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)

    return
}

run_blur_2d :: proc(program: u32, tex: u32, uniforms: ^Blur_Pass_Uniforms, blur: Blur_Gpu) {
    gl.UseProgram(program)
    gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, blur.fbo)
    gl.Uniform2f(uniforms.center, 0, 0)
    gl.Uniform2f(uniforms.size, 2, 2)

    gl.Disable(gl.DEPTH_TEST)
    defer gl.Enable(gl.DEPTH_TEST)

    gl.Viewport(0, 0, SUN_SHADOW_MAP_SIZE, SUN_SHADOW_MAP_SIZE)

    gl.FramebufferTexture2D(gl.DRAW_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, blur.temp_texture_2d, 0)

    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, tex)
    configure_texture_for_blur(gl.TEXTURE_2D, tex)

    gl.Uniform1i(uniforms.tex, 0)
    gl.Uniform1i(uniforms.vertical, 0)

    gl.BindVertexArray(rect_vao)
    gl.DrawArrays(gl.TRIANGLES, 0, 6)

    gl.FramebufferTexture2D(gl.DRAW_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0)
    gl.BindTexture(gl.TEXTURE_2D, blur.temp_texture_2d)
    gl.Uniform1i(uniforms.vertical, 1)

    gl.DrawArrays(gl.TRIANGLES, 0, 6)
}

run_blur_cube :: proc(program_2d, program_cube: u32, tex: u32, uniforms: ^Blur_Pass_Uniforms, blur: Blur_Gpu, side: i32) {
    gl.UseProgram(program_cube)
    gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, blur.fbo)
    gl.Uniform2f(uniforms.center, 0, 0)
    gl.Uniform2f(uniforms.size, 2, 2)

    gl.Disable(gl.DEPTH_TEST)
    defer gl.Enable(gl.DEPTH_TEST)

    gl.Viewport(0, 0, POINT_SHADOW_MAP_SIZE, POINT_SHADOW_MAP_SIZE)

    gl.FramebufferTexture2D(gl.DRAW_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, blur.temp_texture_cube, 0)

    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_CUBE_MAP, tex)
    configure_texture_for_blur(gl.TEXTURE_CUBE_MAP, tex)

    gl.Uniform1i(uniforms.tex, 0)
    gl.Uniform1i(uniforms.side, side)

    gl.BindVertexArray(rect_vao)
    gl.DrawArrays(gl.TRIANGLES, 0, 6)

    gl.UseProgram(program_2d)

    gl.FramebufferTexture2D(gl.DRAW_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, CUBEMAP_SIDES[side], tex, 0)
    gl.BindTexture(gl.TEXTURE_2D, blur.temp_texture_cube)
    gl.Uniform1i(uniforms.vertical, 0)

    gl.DrawArrays(gl.TRIANGLES, 0, 6)
}

application :: proc() -> Maybe(string) {
    inspector_start()

    if (sdl.Init(sdl.INIT_VIDEO) != 0) do return common.sdl2_panic("sdl.Init")
    defer sdl.Quit()

    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_MAJOR_VERSION, 4)
    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_MINOR_VERSION, 6)
    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_PROFILE_MASK, c.int(sdl.GLprofile.CORE))
    sdl.GL_SetAttribute(sdl.GLattr.DOUBLEBUFFER, 1)
    sdl.GL_SetAttribute(sdl.GLattr.RED_SIZE, 8)
    sdl.GL_SetAttribute(sdl.GLattr.GREEN_SIZE, 8)
    sdl.GL_SetAttribute(sdl.GLattr.BLUE_SIZE, 8)
    sdl.GL_SetAttribute(sdl.GLattr.DEPTH_SIZE, 24)

    window := sdl.CreateWindow(
        "Graphics course homework 3",
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
    gl.load_up_to(4, 6, sdl.gl_set_proc_address)

    log("OpenGL initialized: %s", gl.GetString(gl.VERSION))

    /////////////////////////////////

    if len(os.args) < 2 {
        return "Usage: homework3 <path_to_obj>"
    }

    path_to_obj := os.args[1]
    log("Loading scene from %s", path_to_obj)

    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)

    obj_data, obj_reading_error := read_obj_file(path_to_obj)
    if obj_reading_error != nil {
        return obj_reading_error
    }
    objects, materials := obj_data_into_objects(obj_data)

    scene_aabb := AABB_EMPTY
    for object in objects {
        for vertex in object.vertices {
            aabb_update(&scene_aabb, vertex.position)
        }
    }

    gpu_objects := make([]Object_Gpu, len(objects))
    for &object, i in objects do gpu_objects[i] = send_object_to_gpu(&object)

    gpu_materials := make([]Material_Gpu, len(materials))
    gpu_materials_not_gamma_corrected := make([]Material_Gpu, len(materials))

    clear(&ALBEDO_TEXTURE_CACHE)
    for &mat, i in materials do gpu_materials[i] = send_material_to_gpu(&mat) or_return

    clear(&ALBEDO_TEXTURE_CACHE)
    for &mat, i in materials do gpu_materials_not_gamma_corrected[i] =
        send_material_to_gpu(&mat, gamma_correction = false) or_return

    destroy_objects(objects)
    destroy_materials(materials)

    log("Scene loaded to VRAM")

    /////////////////////////////////

    log("Compiling shaders")

    object_shaders := common.compile_shader_program({
        vertex_path = "homework3/shaders/object.vert",
        fragment_path = "homework3/shaders/object.frag",
    }) or_return
    defer common.destroy_shader_program(object_shaders)
    object_program := object_shaders.program
    object_program_uniforms := Uniforms{}
    common.get_uniform_locations(object_program, &object_program_uniforms, ignore_missing = true)

    shadow_shaders := common.compile_shader_program({
        vertex_path = "homework3/shaders/shadow.vert",
        fragment_path = "homework3/shaders/shadow.frag",
    }) or_return
    defer common.destroy_shader_program(shadow_shaders)
    shadow_program := shadow_shaders.program
    shadow_program_uniforms := Uniforms{}
    common.get_uniform_locations(shadow_program, &shadow_program_uniforms, ignore_missing = true)

    blur_pass_2d_shaders := common.compile_shader_program({
        vertex_path = "homework3/shaders/rect.vert",
        fragment_path = "homework3/shaders/blur_pass_2d.frag",
    }) or_return
    defer common.destroy_shader_program(blur_pass_2d_shaders)
    blur_pass_2d_program := blur_pass_2d_shaders.program
    blur_pass_2d_program_uniforms := Blur_Pass_Uniforms{}
    common.get_uniform_locations(blur_pass_2d_program, &blur_pass_2d_program_uniforms, ignore_missing = true)

    blur_pass_cube_shaders := common.compile_shader_program({
        vertex_path = "homework3/shaders/rect.vert",
        fragment_path = "homework3/shaders/blur_pass_cube.frag",
    }) or_return
    defer common.destroy_shader_program(blur_pass_cube_shaders)
    blur_pass_cube_program := blur_pass_cube_shaders.program
    blur_pass_cube_program_uniforms := Blur_Pass_Uniforms{}
    common.get_uniform_locations(blur_pass_cube_program, &blur_pass_cube_program_uniforms, ignore_missing = true)

    debug_shaders := common.compile_shader_program({
        vertex_path = "homework3/shaders/rect.vert",
        fragment_path = "homework3/shaders/debug.frag",
    }) or_return
    defer common.destroy_shader_program(debug_shaders)
    debug_program := debug_shaders.program
    debug_program_uniforms := Debug_Uniforms{}
    common.get_uniform_locations(debug_program, &debug_program_uniforms)

    log("Finished compiling shaders")

    /////////////////////////////////

    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)
    gl.Enable(gl.TEXTURE_CUBE_MAP_SEAMLESS)

    gl.GenVertexArrays(1, &rect_vao)

    blur := init_blur_2d()

    /////////////////////////////////

    last_frame_start := timelib.now()
    time: f32 = 0.0

    camera_controls := Camera_Controls{
        position = [3]f32{0, 0, -5},
        fov = math.to_radians_f32(60),
        near = 0.1,
        far = aabb_diagonal(scene_aabb) * 2.0,
        yaw = 0,
        pitch = 0,
        roll = 0,
        up = [3]f32{0, 1, 0},
    }
    camera := compute_camera(camera_controls, dimensions)

    lights := Lights{
        ambient = {0.1, 0.1, 0.1},
        sun_direction = linalg.normalize([3]f32{0.5, 0.5, 0.5}),
        sun_color = {1, 1, 0.8},
        point_light_number = 0,
        near = 0.1,
        far = aabb_diagonal(scene_aabb) * 1.5,
    }
    init_lights(&lights)

    point_light_attenuation := [3]f32{1, 0, 1000.0 / sqr(aabb_diagonal(scene_aabb))}

    speed: f32 = linalg.length(scene_aabb.max - scene_aabb.min) * 0.1
    SENSITIVITY :: 0.01

    /////////////////////////////////

    free_all(context.temp_allocator)

    button_down: map[sdl.Keycode]bool
    button_pressed: map[sdl.Keycode]bool
    defer delete(button_down)
    defer delete(button_pressed)

    mouse_down: bit_set[1..=2]

    running := true
    move_camera := true
    for running {
        inspector_inc_frame()

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
                        case .P:
                            config.paused = !config.paused
                        case .V:
                            config.debug = !config.debug
                        case .M:
                            move_camera = !move_camera

                        case .UP:
                            inspector_selection_up()
                        case .DOWN:
                            inspector_selection_down()
                        case .LEFT:
                            inspector_action(-1)
                        case .RIGHT:
                            inspector_action(1)
                        case .KP_ENTER:
                            fallthrough
                        case .RETURN:
                            inspector_action(0)
                    }
                    button_down[event.key.keysym.sym] = true
                case .KEYUP:
                    button_down[event.key.keysym.sym] = false
                case .MOUSEMOTION:
                    if 1 in mouse_down {
                        camera_controls.yaw -= cast(f32)event.motion.xrel * SENSITIVITY
                        camera_controls.pitch += cast(f32)event.motion.yrel * SENSITIVITY
                    }
                case .MOUSEBUTTONDOWN:
                    button := event.button.button
                    if button >= 1 && button <= 2 {
                        mouse_down |= {cast(int)button}
                    }
                case .MOUSEBUTTONUP:
                    button := event.button.button
                    if button >= 1 && button <= 2 {
                        mouse_down &= ~{cast(int)button}
                    }
                case .MOUSEWHEEL:
                    speed *= math.pow(1.1, cast(f32)event.wheel.y)
            }
        }

        for key, down in button_down {
            button_pressed[key] = down && !button_down[key]
        }

        current_time := timelib.now()
        defer last_frame_start = current_time
        dt := cast(f32)timelib.duration_seconds(timelib.diff(last_frame_start, current_time))
        if !config.paused do time += dt

        ///////////////////////////////////

        camera_controls.pitch = clamp(camera_controls.pitch, -math.PI / 2 + 0.01, math.PI / 2 - 0.01)

        forward := -linalg.cross(camera.right, camera.up)
        if button_down[.W] do camera_controls.position += forward * dt * speed
        if button_down[.S] do camera_controls.position -= forward * dt * speed
        if button_down[.D] do camera_controls.position += camera.right * dt * speed
        if button_down[.A] do camera_controls.position -= camera.right * dt * speed
        if button_down[.SPACE] do camera_controls.position += camera.up * dt * speed
        if button_down[.LSHIFT] do camera_controls.position -= camera.up * dt * speed
        if button_down[.Y] do speed *= math.pow(2.0, dt)
        if button_down[.U] do speed /= math.pow(2.0, dt)

        camera = compute_camera(camera_controls, dimensions)

        ///////////////////////////////////

        lights.sun_direction = linalg.quaternion128_mul_vector3(
            linalg.quaternion_from_pitch_yaw_roll(0, time * 0.3, 0),
            linalg.normalize([3]f32{0.2, 0.5, 0.2}),
        )

        if config.regenerate_lights {
            config.regenerate_lights = false
            lights.point_light_number = 0
            rand.reset(frame)
            for i in 0..<MAX_POINT_LIGHTS {
                x := rand.float32_uniform(scene_aabb.min.x, scene_aabb.max.x)
                y := rand.float32_uniform(scene_aabb.min.y, scene_aabb.max.y)
                z := rand.float32_uniform(scene_aabb.min.z, scene_aabb.max.z)
                r := rand.float32_uniform(0, 15)
                g := rand.float32_uniform(0, 15)
                b := rand.float32_uniform(0, 15)
                lights_push_point(&lights, {x, y, z}, {r, g, b}, point_light_attenuation)
            }
        }

        scene_size := aabb_diagonal(scene_aabb)
        if config.move_light_zero_around && !config.paused && lights.point_light_number > 0 {
            lights.point_position[0] = camera.position + 
                [3]f32{math.sin(time * 0.5), math.sin(time * 0.4), math.sin(time * 0.3)} * scene_size * 0.03
        }

        if config.teleport_light_zero_to_camera {
            config.teleport_light_zero_to_camera = false
            lights.point_position[0] = camera.position
        }

        if config.teleport_light_one_to_camera {
            config.teleport_light_one_to_camera = false
            lights.point_position[1] = camera.position
        }

        ///////////////////////////////////

        prepare_object_shader_program(shadow_program, &shadow_program_uniforms)

        for i in 0..<7 {
            bind_shadow_map(&lights, &shadow_program_uniforms, i, scene_aabb)
            gl.ClearColor(1.0, 1.0, 0.0, 0.0)
            gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

            for object in gpu_objects {
                bind_object(object, &shadow_program_uniforms)
                bind_material(gpu_materials[object.material_id], &shadow_program_uniforms)
                gl.DrawElements(gl.TRIANGLES, object.vertex_count, gl.UNSIGNED_INT, nil)
            }
        }

        ///////////////////////////////////

        // fmt.printfln("Camera pos: %v, camera dir: %v", camera.position, camera.forward)
        run_blur_2d(blur_pass_2d_program, lights.sun_shadow_map, &blur_pass_2d_program_uniforms, blur)
        // for side in i32(1)..<2 {
        //     run_blur_cube(blur_pass_2d_program, blur_pass_cube_program, lights.point_shadow_map, &blur_pass_2d_program_uniforms, blur, side)
        // }

        ///////////////////////////////////

        prepare_object_shader_program(object_program, &object_program_uniforms)
        gl.Viewport(0, 0, dimensions.x, dimensions.y)

        gl.ClearColor(0.7, 0.8, 1.0, 0.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        if config.srgb_framebuffer {
            gl.Enable(gl.FRAMEBUFFER_SRGB)
        } else {
            gl.Disable(gl.FRAMEBUFFER_SRGB)
        }

        bind_lights(lights, &object_program_uniforms)
        bind_camera(camera, &object_program_uniforms)

        for object in gpu_objects {
            material := gpu_materials[object.material_id]
            if !config.gamma_correction {
                material = gpu_materials_not_gamma_corrected[object.material_id]
            }
            bind_material(material, &object_program_uniforms)
            bind_object(object, &object_program_uniforms)

            gl.DrawElements(gl.TRIANGLES, object.vertex_count, gl.UNSIGNED_INT, nil)
        }

        ///////////////////////////////////

        if config.debug {
            debug_draw({-0.8, -0.8}, {0.4, 0.4}, lights.sun_shadow_map, &debug_program_uniforms, debug_program)
            debug_draw({-0.4, -0.8}, {0.4, 0.4}, gpu_materials[1].albedo_texture, &debug_program_uniforms, debug_program)
            debug_draw({0.0, -0.8}, {0.4, 0.4}, blur.temp_texture_2d, &debug_program_uniforms, debug_program)
            debug_draw({0.4, -0.8}, {0.4, 0.4}, blur.temp_texture_cube, &debug_program_uniforms, debug_program)
        }

        inspector_render()
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
