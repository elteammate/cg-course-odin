package common

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:mem"

import gl "vendor:OpenGL"


Vertex :: struct {
    position: [3]f32 `gl:"location=0"`,
    normal: [3]f32 `gl:"location=1"`,
    texcoord: [2]f32 `gl:"location=2"`,
}

Obj_Data :: struct {
    vertices: [dynamic]Vertex,
    indices: [dynamic]u32,
}

Gpu_Obj_Data :: struct {
    vao: u32,
    vbo: u32,
    ebo: u32,
    indices_count: i32,
}

destory_obj_data :: proc(data: Obj_Data) {
    delete(data.vertices)
    delete(data.indices)
}

parse_obj :: proc(content: string) -> (result: Obj_Data, error: Maybe(string)) {
    content := content
    positions := make([dynamic][3]f32, 0, 1024, context.temp_allocator)
    defer delete(positions)
    normals := make([dynamic][3]f32, 0, 1024, context.temp_allocator)
    defer delete(normals)
    texcoords := make([dynamic][2]f32, 0, 1024, context.temp_allocator)
    defer delete(texcoords)
    index_map := make(map[[3]u32]u32, 1024, context.temp_allocator)
    defer delete(index_map)


    for line in strings.split_lines_iterator(&content) {
        if len(line) == 0 || line[0] == '#' do continue

        tokens := strings.split(line, " ", context.temp_allocator)
        defer delete(tokens, context.temp_allocator)
        tag := tokens[0]

        if tag == "v" {
            position: [3]f32
            position[0], _ = strconv.parse_f32(tokens[1])
            position[1], _ = strconv.parse_f32(tokens[2])
            position[2], _ = strconv.parse_f32(tokens[3])
            append(&positions, position)
        } else if tag == "vn" {
            normal: [3]f32
            normal[0], _ = strconv.parse_f32(tokens[1])
            normal[1], _ = strconv.parse_f32(tokens[2])
            normal[2], _ = strconv.parse_f32(tokens[3])
            append(&normals, normal)
        } else if tag == "vt" {
            texcoord: [2]f32
            texcoord[0], _ = strconv.parse_f32(tokens[1])
            texcoord[1], _ = strconv.parse_f32(tokens[2])
            append(&texcoords, texcoord)
        } else if tag == "f" {
            vertices := make([dynamic]u32, 0, context.temp_allocator)
            defer delete(vertices)
            for i := 1; i < len(tokens); i += 1 {
                indices := strings.split(tokens[i], "/", context.temp_allocator)
                defer delete(indices, context.temp_allocator)
                
                index: [3]i64
                index[0], _ = strconv.parse_i64(indices[0])
                index[0] -= 1
                
                if len(indices) > 1 && indices[1] != "" {
                    index[1], _ = strconv.parse_i64(indices[1])
                    index[1] -= 1
                }
                
                if len(indices) > 2 && indices[2] != "" {
                    index[2], _ = strconv.parse_i64(indices[2])
                    index[2] -= 1
                }

                // Check the index map
                cast_index := [3]u32{u32(index[0]), u32(index[1]), u32(index[2])}
                v_index, ok := index_map[cast_index]
                if !ok {
                    v_index = cast(u32)(len(result.vertices))
                    index_map[cast_index] = v_index

                    vertex: Vertex
                    vertex.position = positions[index[0]]

                    if len(texcoords) > 0 && index[1] != -1 {
                        vertex.texcoord = texcoords[index[1]]
                    } else {
                        vertex.texcoord = [2]f32{0.0, 0.0}
                    }

                    if len(normals) > 0 && index[2] != -1 {
                        vertex.normal = normals[index[2]]
                    } else {
                        vertex.normal = [3]f32{0.0, 0.0, 0.0}
                    }

                    append(&result.vertices, vertex)
                }

                append(&vertices, v_index)
            }

            for j := 1; j + 1 < len(vertices); j += 1 {
                append(&result.indices, vertices[0], vertices[j], vertices[j + 1])
            }
        }
    }

    return result, nil
}

load_obj_file :: proc(path: string) -> (result: Obj_Data, error: Maybe(string)) {
    result = Obj_Data{}

    data, ok := os.read_entire_file(path, context.temp_allocator)
    if !ok do return result, "Failed to read file"
    defer delete(data, context.temp_allocator)
    content := string(data)

    return parse_obj(content)
}

send_obj_to_gpu :: proc(data: Obj_Data) -> (result: Gpu_Obj_Data) {
    return send_vertices_indices_to_gpu(data.vertices[:], data.indices[:])
}

send_vertices_indices_to_gpu :: #force_inline proc(vertices: []$V, indices: []u32) -> (result: Gpu_Obj_Data) {
    gl.GenVertexArrays(1, &result.vao)
    gl.BindVertexArray(result.vao)
    defer gl.BindVertexArray(0)

    gl.GenBuffers(1, &result.vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, result.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(V), raw_data(vertices), gl.STATIC_DRAW)

    gl.GenBuffers(1, &result.ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, result.ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), raw_data(indices), gl.STATIC_DRAW)

    configure_vao_attributes(V)

    result.indices_count = cast(i32)(len(indices))

    return
}

destroy_gpu_obj_data :: proc(data: Gpu_Obj_Data) {
    data := data
    gl.DeleteVertexArrays(1, &data.vao)
    gl.DeleteBuffers(1, &data.vbo)
    gl.DeleteBuffers(1, &data.ebo)
}

