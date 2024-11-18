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
    position: [3]f32,
    normal: [3]f32,
    texcoord: [2]f32,
}

Material_Gpu :: struct {
    id: int,
    albedo: [3]f32,
    albedo_texture: u32,
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

    return
}

load_texture :: proc(
    path: string,
    mipmaps: bool = true,
    min_filter: gl.Enum = gl.LINEAR_MIPMAP_LINEAR,
    mag_filter: gl.Enum = gl.LINEAR,
) -> (texture: u32) {
    gl.Gen
}

send_material_to_gpu :: proc(mat: ^Material_Data) -> (m: Material_Gpu) {
    if 
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
        "Graphics course homework 2",
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

    fmt.printfln("args: %v", os.args)
    if len(os.args) < 2 {
        return "Usage: homework2 <path_to_obj>"
    }

    path_to_obj := os.args[1]
    obj_data, obj_reading_error := read_obj_file(path_to_obj)
    if obj_reading_error != nil {
        return obj_reading_error
    }
    objects, materials := obj_data_into_objects(obj_data)
    defer destroy_objects(objects)
    defer destroy_materials(materials)

    last_frame_start := timelib.now()
    time: f32 = 0.0

    gl.load_up_to(3, 3, sdl.gl_set_proc_address)

    free_all(context.temp_allocator)

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
                    }
                case .KEYDOWN:
                    #partial switch event.key.keysym.sym {
                        case .ESCAPE:
                            running = false
                    }
                    button_down[event.key.keysym.sym] = true
                case .KEYUP:
                    button_down[event.key.keysym.sym] = false
            }
        }

        current_time := timelib.now()
        defer last_frame_start = current_time
        dt := cast(f32)timelib.duration_seconds(timelib.diff(last_frame_start, current_time))
        time += dt

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
