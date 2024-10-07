package common

import "core:strings"
import "core:fmt"
import "core:os"
import "core:reflect"
import sa "core:container/small_array"

import gl "vendor:OpenGL"

ShaderProgramInfo :: struct {
    vertex_source: Maybe(string),
    fragment_source: Maybe(string),
    vertex_path: Maybe(string),
    fragment_path: Maybe(string),
    include_sources: []string,
    include_paths: []string,
}

ShaderProgram :: struct {
    program: u32,
    vertex_shader: u32,
    fragment_shader: u32,
}

destroy_shader_program :: proc(program: ShaderProgram) {
    gl.DeleteShader(program.vertex_shader)
    gl.DeleteShader(program.fragment_shader)
    gl.DeleteProgram(program.program)
}

_read_string_from_file :: proc(path: string) -> (string, Maybe(string)) {
    data, ok := os.read_entire_file(path)
    if !ok do return "", fmt.tprintf("Error reading file: %s", path)
    return string(data), nil
}

MAX_PARTS_PER_SHADER :: 16

_compile_shader :: proc(
    given_sources: ^sa.Small_Array(MAX_PARTS_PER_SHADER, string),
    type: gl.GL_Enum
) -> (u32, Maybe(string)) {
    shader := gl.CreateShader(u32(type))
    sources: sa.Small_Array(MAX_PARTS_PER_SHADER, cstring)
    lengths: sa.Small_Array(MAX_PARTS_PER_SHADER, i32)

    for source in sa.slice(given_sources) {
        sa.append(&sources, strings.unsafe_string_to_cstring(source))
        sa.append(&lengths, cast(i32)len(source))
    }

    gl.ShaderSource(shader, 1, raw_data(sa.slice(&sources)), raw_data(sa.slice(&lengths)))
    gl.CompileShader(shader)
    compile_status: i32 = ---
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &compile_status)
    if (compile_status != 1) {
        infolog_size: i32 = ---
        gl.GetShaderiv(shader, gl.INFO_LOG_LENGTH, &infolog_size)
        infolog := make([]u8, infolog_size)
        gl.GetShaderInfoLog(shader, infolog_size, nil, raw_data(infolog))
        return 0, fmt.tprintf("Error compiling shader: %s", string(infolog))
    }
    return shader, nil
}

compile_shader_program :: proc(program_info: ShaderProgramInfo) -> (result: ShaderProgram, err: Maybe(string)) {
    result = ShaderProgram{}
    sources: sa.Small_Array(MAX_PARTS_PER_SHADER, string)
    defer assert(sa.len(sources) == 0)

    for source in program_info.include_paths {
        data, err := _read_string_from_file(source)
        if err != nil do return result, err
        sa.append(&sources, data)
    }
    defer for _ in program_info.include_paths do delete(sa.pop_back(&sources))

    for source in program_info.include_sources do sa.append(&sources, source)
    defer for source in program_info.include_sources do sa.pop_back(&sources)

    if source, present := program_info.vertex_source.?; present {
        sa.append(&sources, source)
    } else if path, present := program_info.vertex_path.?; present {
        data, err := _read_string_from_file(path)
        if err != nil do return result, err
        sa.append(&sources, data)
    } else {
        return result, "No vertex shader source or path provided"
    }

    result.vertex_shader, err = _compile_shader(&sources, .VERTEX_SHADER)
    if program_info.vertex_source != nil do sa.pop_back(&sources)
        else if program_info.vertex_path != nil do delete(sa.pop_back(&sources))
    if err != nil do return

    if source, present := program_info.fragment_source.?; present {
        sa.append(&sources, source)
    } else if path, present := program_info.fragment_path.?; present {
        data, err := _read_string_from_file(path)
        if err != nil do return result, err
        sa.append(&sources, data)
    } else {
        return result, "No fragment shader source or path provided"
    }
    result.fragment_shader, err = _compile_shader(&sources, .FRAGMENT_SHADER)
    if program_info.fragment_source != nil do sa.pop_back(&sources)
        else if program_info.fragment_path != nil do delete(sa.pop_back(&sources))
    if err != nil do return

    result.program = gl.CreateProgram()
    gl.AttachShader(result.program, result.vertex_shader)
    gl.AttachShader(result.program, result.fragment_shader)
    gl.LinkProgram(result.program)

    link_status: i32 = ---
    gl.GetProgramiv(result.program, gl.LINK_STATUS, &link_status)
    if (link_status != 1) {
        infolog_size: i32 = ---
        gl.GetProgramiv(result.program, gl.INFO_LOG_LENGTH, &infolog_size)
        infolog := make([]u8, infolog_size)
        gl.GetProgramInfoLog(result.program, infolog_size, nil, cast([^]u8)raw_data(infolog))
        return result, fmt.tprintf("Error linking program: %s", string(infolog))
    }

    return result, nil
}
