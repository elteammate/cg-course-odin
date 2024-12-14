package main

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "core:c"
import "core:os"
import "core:strconv"
import "core:bufio"
import "core:mem"
import "core:slice"
import "core:math"
import "core:unicode"
import "core:math/linalg"

fix_slashes :: proc(path: string) -> (string, bool) {
    return strings.replace(path, "\\", "/", -1)
}

Wavefront_Group :: struct {
    start: int,
    end: int,
    name: string,
    material_name: string,
    material_id: int,
}

Wavefront_Obj_Data :: struct {
    material_lib_indices: map[string]int,
    materials: [dynamic]Material_Data,
    vertices: [dynamic][3]f32,
    normals: [dynamic][3]f32,
    texcoords: [dynamic][2]f32,
    triangles: [dynamic][3][3]int,
    groups: [dynamic]Wavefront_Group,
} 

Material_Data :: struct {
    id: int,
    name: string,
    albedo: [3]f32,
    albedo_texture: Maybe(string),
    transparency: f32,
    transparency_texture: Maybe(string),
    glossiness: [3]f32,
    power: f32,
}

LOCAL_BUFFER_CAPACITY :: 512
@thread_local LOCAL_BUFFER: [LOCAL_BUFFER_CAPACITY]byte

peek_byte :: proc(r: ^bufio.Reader) -> byte {
    data, err := bufio.reader_peek(r, 1)
    if err != nil do return 0
    return data[0]
}

read_byte :: proc(r: ^bufio.Reader) -> byte {
    data, err := bufio.reader_read_byte(r)
    if err != nil do return 0
    return data
}

is_whitespace :: proc(c: byte) -> bool {
    return c == ' ' || c == '\t' || c == '\r'
}

is_end_of_line :: proc(c: byte) -> bool {
    return c == '\n' || c == 0
}

skip_whitespace :: proc(r: ^bufio.Reader) {
    for {
        b := peek_byte(r)
        if b == 0 || !is_whitespace(b) do break
        read_byte(r)
    } 
}

read_word_temp :: proc(r: ^bufio.Reader) -> string {
    skip_whitespace(r)

    result := LOCAL_BUFFER[:]
    i := 0

    for ; i < LOCAL_BUFFER_CAPACITY; i += 1 {
        b := peek_byte(r)
        if is_whitespace(b) || is_end_of_line(b) do break
        result[i] = b
        read_byte(r)
    }
    return string(result[:i])
}

read_line_temp :: proc(r: ^bufio.Reader) -> string {
    result := LOCAL_BUFFER[:]
    i := 0

    for ; i < LOCAL_BUFFER_CAPACITY; i += 1 {
        b := peek_byte(r)
        if is_end_of_line(b) do break
        result[i] = b
        read_byte(r)
    }
    if i != LOCAL_BUFFER_CAPACITY do read_byte(r)
    return string(result[:i])
}

skip_line :: proc(r: ^bufio.Reader) {
    for {
        b := read_byte(r)
        if is_end_of_line(b) do break
    }
}

expect_byte :: proc(r: ^bufio.Reader, expected: byte) -> Maybe(string) {
    b := read_byte(r)
    if b == expected do return nil
    return fmt.tprintf("Expected '%c' but got '%c'", expected, b)
}

read_f32 :: proc(r: ^bufio.Reader) -> (f32, Maybe(string)) {
    skip_whitespace(r)

    buf := LOCAL_BUFFER[:]
    seen_dot := false
    seen_sign := false
    seen_digits := false
    i := 0

    for ; i < LOCAL_BUFFER_CAPACITY; i += 1 {
        b := peek_byte(r)
        if b == '.' {
            if seen_dot do break
            seen_dot = true
        } else if b == '-' || b == '+' {
            if seen_sign || seen_digits || seen_dot do break
            seen_sign = true
        } else if unicode.is_digit(rune(b)) {
            seen_digits = true
        } else {
            break
        }
        buf[i] = b
        read_byte(r)
    }

    if i == 0 do return 0, fmt.tprintf("Expected a floating-point number but got '%c'", peek_byte(r))
    value, ok := strconv.parse_f32(string(buf[:i]))
    if !ok do return 0, fmt.tprintf("Failed to parse floating-point number: %v", string(buf[:i]))
    return value, nil
}

read_int :: proc(r: ^bufio.Reader) -> (int, Maybe(string)) {
    skip_whitespace(r)

    buf := LOCAL_BUFFER[:]
    seen_sign := false
    seen_digits := false
    i := 0

    for ; i < LOCAL_BUFFER_CAPACITY; i += 1 {
        b := peek_byte(r)
        if b == '-' || b == '+' {
            if seen_sign || seen_digits do break
            seen_sign = true
        } else if unicode.is_digit(rune(b)) {
            seen_digits = true
        } else {
            break
        }
        buf[i] = b
        read_byte(r)
    }

    if !seen_digits do return 0, fmt.tprintf("Expected an integer but got '%c'", peek_byte(r))

    value, ok := strconv.parse_int(string(buf[:i]), 10)
    if !ok do return 0, fmt.tprintf("Failed to parse integer: %v", string(buf[:i]))
    return value, nil
}

read_material_file :: proc(path: string, lib: ^map[string]int, materials: ^[dynamic]Material_Data) -> Maybe(string) {
    directory := filepath.dir(path)
    defer delete(directory)

    file_handle, file_open_err := os.open(path)
    if file_open_err != nil do return fmt.tprintf("Failed to open file: %v", path)
    defer os.close(file_handle)

    stream := os.stream_from_handle(file_handle)

    reader: bufio.Reader
    r := &reader
    bufio.reader_init(r, stream)

    current_material: Material_Data
    current_material.transparency = 1.0

    for peek_byte(r) != 0 {
        command := read_word_temp(r)

        if command == "#" {
            skip_line(r)
        } else if command == "" {
            skip_line(r)
        } else if command == "newmtl" {
            if current_material.id != 0 {
                mat_index, found := lib[current_material.name]
                if !found {
                    append(materials, current_material)
                    lib[current_material.name] = current_material.id
                }
            }
            skip_whitespace(r)
            name := read_line_temp(r)
            current_material = Material_Data{
                id = len(lib),
                name = strings.clone(name),
                transparency = 1.0,
            }
        } else if command == "Ka" {
            cr := read_f32(r) or_return
            cg := read_f32(r) or_return
            cb := read_f32(r) or_return
            skip_whitespace(r)
            if !is_end_of_line(peek_byte(r)) {
                return fmt.tprintf("Expected end of line after Ka command and 3 components")
            }
            current_material.albedo = [3]f32{cr, cg, cb}
        } else if command == "map_Ka" {
            skip_whitespace(r)
            rel_path, allocates := fix_slashes(read_line_temp(r))
            current_material.albedo_texture = filepath.join({directory, rel_path})
            if allocates do delete(rel_path)
        } else if command == "d" {
            d := read_f32(r) or_return
            skip_whitespace(r)
            if !is_end_of_line(peek_byte(r)) {
                return fmt.tprintf("Expected end of line after d command and 1 component")
            }
            current_material.transparency = d
        } else if command == "map_d" {
            skip_whitespace(r)
            rel_path, allocates := fix_slashes(read_line_temp(r))
            current_material.transparency_texture = filepath.join({directory, rel_path})
            if allocates do delete(rel_path)
        } else if command == "Ks" {
            ksr := read_f32(r) or_return
            skip_whitespace(r)
            if is_end_of_line(peek_byte(r)) {
                current_material.glossiness = {ksr, ksr, ksr}
            } else {
                ksg := read_f32(r) or_return
                ksb := read_f32(r) or_return
                skip_whitespace(r)
                if !is_end_of_line(peek_byte(r)) {
                    return fmt.tprintf("Expected end of line after Ks command and 1 or 3 components")
                }
                current_material.glossiness = {ksr, ksg, ksb}
            }
        } else if command == "Ns" {
            ns := read_f32(r) or_return
            skip_whitespace(r)
            if !is_end_of_line(peek_byte(r)) {
                return fmt.tprintf("Expected end of line after Ns command and 1 component")
            }
            current_material.power = ns
        } else {
            read_line_temp(r)
        }
    }

    if current_material.id != 0 {
        mat_index, found := lib[current_material.name]
        if !found {
            append(materials, current_material)
            lib[current_material.name] = current_material.id
        }
    }

    return nil
}

read_obj_file :: proc(path: string) -> (data: Wavefront_Obj_Data, error: Maybe(string)) {
    directory := filepath.dir(path)
    defer delete(directory)

    file_handle, file_open_err := os.open(path)
    if file_open_err != nil do return data, fmt.tprintf("Failed to open file: %v", path)
    defer os.close(file_handle)

    stream := os.stream_from_handle(file_handle)

    reader: bufio.Reader
    r := &reader
    bufio.reader_init(r, stream)

    Raw_Group :: struct {
        index: int,
        name: string,
        is_material: bool,
    }

    vertices := make([dynamic][3]f32, 0, 1024)
    normals := make([dynamic][3]f32, 0, 1024)
    texcoords := make([dynamic][2]f32, 0, 1024)
    triangles := make([dynamic][3][3]int, 0, 1024)
    raw_groups := make([dynamic]Raw_Group, 0, 8)
    material_lib := make(map[string]int)
    materials := make([dynamic]Material_Data, 1, 8)
    material_lib[""] = 0

    for peek_byte(r) != 0 {
        command := read_word_temp(r)

        if command == "" {
            skip_line(r)
        } else if command[0] == '#' {
            skip_line(r)
        } else if command == "v" {
            x := read_f32(r) or_return
            y := read_f32(r) or_return
            z := read_f32(r) or_return
            skip_whitespace(r)
            if !is_end_of_line(peek_byte(r)) {
                return data, fmt.tprintf("Expected end of line after vertex coordinates, w coordinate is not supported")
            }
            append(&vertices, [3]f32{x, y, z})
        } else if command == "vn" {
            x := read_f32(r) or_return
            y := read_f32(r) or_return
            z := read_f32(r) or_return
            skip_whitespace(r)
            if !is_end_of_line(peek_byte(r)) {
                return data, fmt.tprintf("Expected end of line after noormal coordinates, w coordinate is not supported")
            }
            append(&normals, [3]f32{x, y, z})
        } else if command == "vt" {
            u := read_f32(r) or_return
            v := read_f32(r) or_return
            skip_whitespace(r)
            if !is_end_of_line(peek_byte(r)) {
                w := read_f32(r) or_return
                // if w != 0 {
                //     return data, fmt.tprintf("Expected end of line after 2/3 texcoords, only 2d coordinates are supported")
                // }
                skip_whitespace(r)
                if !is_end_of_line(peek_byte(r)) {
                    return data, fmt.tprintf("Expected end of line after 2/3 texcoords, only 2d coordinates are supported")
                }
            }
            append(&texcoords, [2]f32{u, v})
        } else if command == "f" {
            first, previous, current: [3]int

            i := 0

            for ;; i += 1 {
                v_index, t_index, n_index: int
                v_index = read_int(r) or_return
                if v_index == 0 { return data, fmt.tprintf("Expected vertex index, found 0") }
                expect_byte(r, '/') or_return
                t_index = read_int(r) or_return
                expect_byte(r, '/') or_return
                n_index = read_int(r) or_return

                if v_index < 0 { v_index = len(vertices) + v_index + 1 }
                if t_index < 0 { t_index = len(texcoords) + t_index + 1 }
                if n_index < 0 { n_index = len(normals) + n_index + 1 }

                if i == 0 {
                    first = [3]int{v_index, t_index, n_index} - 1
                } else if i == 1 {
                    previous = [3]int{v_index, t_index, n_index} - 1
                } else {
                    current = [3]int{v_index, t_index, n_index} - 1
                    append(&triangles, [3][3]int{first, previous, current})
                    previous = current
                }

                skip_whitespace(r)
                if is_end_of_line(peek_byte(r)) { break }
            }
        } else if command == "g" || command == "o" {
            skip_whitespace(r)
            name := read_line_temp(r)
            append(&raw_groups, Raw_Group{len(triangles), strings.clone(name, context.temp_allocator), false})
        } else if command == "usemtl" {
            skip_whitespace(r)
            name := read_line_temp(r)
            append(&raw_groups, Raw_Group{len(triangles), strings.clone(name, context.temp_allocator), true})
        } else if command == "mtllib" {
            skip_whitespace(r)

            rel_path, allocates := fix_slashes(read_line_temp(r))
            lib_path, path_error := filepath.join({directory, rel_path})
            if allocates do delete(rel_path)
            if path_error != nil {
                return data, fmt.tprintf("Failed to resolve material lib path: %v", path_error)
            }
            defer delete(lib_path)

            material_lib_error := read_material_file(lib_path, &material_lib, &materials)
            if material_lib_error != nil {
                return data, fmt.tprintf("Failed to read material lib: %v", material_lib_error)
            }
        } else if command == "s" {
            // Skip smoothing group because vertex normals are set explicitly
            skip_line(r)
        } else {
            read_line_temp(r)
        }
    }

    append(&raw_groups, Raw_Group{len(triangles), "", false})
    groups := make([dynamic]Wavefront_Group, 0, len(raw_groups))

    last_group_start := 0
    cur_group_name, cur_group_material: string

    for group in raw_groups {
        if group.index != last_group_start {
            append(&groups, Wavefront_Group{
                start = last_group_start,
                end = group.index,
                name = strings.clone(cur_group_name),
                material_name = strings.clone(cur_group_material),
                material_id = material_lib[cur_group_material],
            })
        }
        if group.is_material {
            delete(cur_group_material, context.temp_allocator)
            cur_group_material = group.name
        } else {
            delete(cur_group_name, context.temp_allocator)
            cur_group_name = group.name
        }
        last_group_start = group.index
    }

    delete(cur_group_name, context.temp_allocator)
    delete(cur_group_material, context.temp_allocator)

    return Wavefront_Obj_Data{
        material_lib_indices = material_lib,
        materials = materials,
        vertices = vertices,
        normals = normals,
        texcoords = texcoords,
        triangles = triangles,
        groups = groups,
    }, nil
}

obj_data_into_objects :: proc(data: Wavefront_Obj_Data) -> (objects: []Object, materials: []Material_Data) {
    objects = make([]Object, len(data.groups))

    index_map: map[[3]int]u32
    defer delete(index_map)

    for group, obj_index in data.groups {
        trigs := data.triangles[group.start:group.end]
        num_trigs := len(trigs)
        estimated_num_vertices := num_trigs * 3 / 2
        vertices := make([dynamic]Vertex, 0, estimated_num_vertices)
        indices := make([]u32, num_trigs * 3)

        for trig, i in trigs {
            for j in 0..<3 {
                key := trig[j]
                index, ok := index_map[key]
                if !ok {
                    index = cast(u32)len(vertices)
                    index_map[key] = index
                    append(&vertices, Vertex{
                        position = data.vertices[key[0]],
                        normal = data.normals[key[2]],
                        texcoord = data.texcoords[key[1]],
                    })
                }
                indices[i * 3 + j] = index
            }
        }

        objects[obj_index] = Object{
            name = strings.clone(group.name),
            material_name = strings.clone(group.material_name),
            material_id = group.material_id,
            vertices = dynamic_into_slice(vertices),
            indices = indices,
        }

        clear(&index_map)
    }

    delete(data.material_lib_indices)
    materials = dynamic_into_slice(data.materials)
    delete(data.vertices)
    delete(data.normals)
    delete(data.texcoords)
    delete(data.triangles)
    delete(data.groups)

    return
}

destroy_objects :: proc(objects: []Object) {
    for obj in objects {
        delete(obj.name)
        delete(obj.material_name)
        delete(obj.vertices)
        delete(obj.indices)
    }
    delete(objects)
}

destroy_materials :: proc(materials: []Material_Data) {
    for mat in materials {
        delete(mat.name)
        if s, present := mat.albedo_texture.?; present do delete(s)
        if s, present := mat.transparency_texture.?; present do delete(s)
    }
    delete(materials)
}
