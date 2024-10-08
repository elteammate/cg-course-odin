package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:mem"
import "core:strconv"

Vertex :: struct {
    position: [3]f32,
    normal: [3]f32,
    texcoord: [2]f32,
}

ObjData :: struct {
    vertices: [dynamic]Vertex,
    indices: [dynamic]u32,
}

parse_obj :: proc(path: string) -> (result: ObjData, error: Maybe(string)) {
    result = ObjData{}

    data, ok := os.read_entire_file(path)
    if !ok do return result, "Failed to read file"
    defer delete(data)
    content := string(data)

    positions: [dynamic][3]f32
    defer delete(positions)
    normals: [dynamic][3]f32
    defer delete(normals)
    texcoords: [dynamic][2]f32
    defer delete(texcoords)
    index_map: map[[3]u32]u32
    defer delete(index_map)


    for line in strings.split_lines_iterator(&content) {
        if len(line) == 0 || line[0] == '#' do continue

        tokens := strings.split(line, " ")
        defer delete(tokens)
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
            vertices: [dynamic]u32
            defer delete(vertices)
            for i := 1; i < len(tokens); i += 1 {
                indices := strings.split(tokens[i], "/")
                defer delete(indices)
                
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
