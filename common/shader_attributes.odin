package common

import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:reflect"

import gl "vendor:OpenGL"

get_uniform_locations_explicit :: #force_inline proc($T: typeid, program: u32, ignore_missing: bool = false) -> T {
    result: T = ---
    memory := transmute([^]i32)&result
    fields := reflect.struct_fields_zipped(T)
    for i in 0..<len(fields) {
        assert(fields[i].type.id == i32, "Only i32 fields are supported")
        name := strings.clone_to_cstring(fields[i].name, context.temp_allocator)
        offset := fields[i].offset / align_of(i32)
        memory[offset] = gl.GetUniformLocation(program, name)
        delete(name, context.temp_allocator)
        if (!ignore_missing && memory[offset] < 0) {
            fmt.eprintfln("Uniform %v not found", name)
            unreachable()
        }
    }
    return result
}

get_uniform_locations_implicit :: #force_inline proc(program: u32, uniforms: ^$T, ignore_missing: bool = false) {
    uniforms^ = get_uniform_locations_explicit(T, program, ignore_missing = ignore_missing)
}

get_uniform_locations :: proc{get_uniform_locations_explicit, get_uniform_locations_implicit}

configure_vao_attribute :: #force_inline proc(location: u32, T: typeid, stride: i32 = -1, offset: i32 = 0) {
    stride := stride
    if stride == -1 do stride = cast(i32)reflect.size_of_typeid(T)

    gl_type: u32
    gl_size: i32 = 1
    field_type: typeid = ---
    if reflect.is_array(type_info_of(T)) {
        field_type = reflect.typeid_elem(T)
        gl_size = i32(reflect.size_of_typeid(T) / reflect.size_of_typeid(field_type))
    } else {
        field_type = T
    }

    switch field_type {
        case f32: gl_type = gl.FLOAT
        case i32: gl_type = gl.INT
        case u32: gl_type = gl.UNSIGNED_INT
        case i16: gl_type = gl.SHORT
        case u16: gl_type = gl.UNSIGNED_SHORT
        case i8: gl_type = gl.BYTE
        case u8: gl_type = gl.UNSIGNED_BYTE
        case: panic(fmt.tprintf("Unsupported attribute type, got %v", field_type))
    }

    gl.EnableVertexAttribArray(location)
    gl.VertexAttribPointer(
        location,
        gl_size,
        gl_type,
        false,
        stride,
        cast(uintptr)offset,
    )
}

configure_vao_attributes :: #force_inline proc($T: typeid) {
    location_pattern :: "location="
    fields := reflect.struct_fields_zipped(T)
    for i in 0..<len(fields) {
        tag_value := reflect.struct_tag_lookup(fields[i].tag, "gl") or_else
            panic("Attribute must have a 'gl' tag")
        assert(tag_value != "", "Attribute must have a non-empty 'gl' tag")
        index := strings.index(tag_value, location_pattern)
        if index == -1 do panic("Attribute must have a 'location' field in the 'gl' tag")
        index += len(location_pattern)
        location := strconv.parse_i64(tag_value[index:]) or_else
            panic("Attribute location must be an integer")

        if location == -1 do continue
        if location < 0 || location >= 16 {
            panic("Attribute location must be in the range [0, 16) or -1")
        }

        configure_vao_attribute(cast(u32)location, fields[i].type.id, size_of(T), cast(i32)fields[i].offset)
    }
}
