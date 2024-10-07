package main

import "core:fmt"
import "core:strings"
import "core:c"
import "core:os"
import "core:math"
import "core:math/linalg"
import "core:reflect"

import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

import common "../common"

function :: proc(x, y, t: f32) -> f32 {
    return math.sin(x * x + y * y + t)
}

Grid_Info :: struct {
    low: [2]i32,
    size: [2]i32,
}

RESTART_INDEX: u32 : 0xFFFFFFFF

application :: proc() -> Maybe(string) {
    if (sdl.Init(sdl.INIT_VIDEO) != 0) do return common.sdl2_panic("sdl.Init")
    defer sdl.Quit()

    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_MAJOR_VERSION, 3)
    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_MINOR_VERSION, 3)
    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_PROFILE_MASK, c.int(sdl.GLprofile.CORE))
    sdl.GL_SetAttribute(sdl.GLattr.DOUBLEBUFFER, 1)
    sdl.GL_SetAttribute(sdl.GLattr.MULTISAMPLESAMPLES, 1)
    sdl.GL_SetAttribute(sdl.GLattr.MULTISAMPLESAMPLES, 4)

    window := sdl.CreateWindow(
        "Graphics course practice 4",
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

    gl.Enable(gl.PRIMITIVE_RESTART)
    gl.PrimitiveRestartIndex(RESTART_INDEX)
    // gl.ClearColor(0.0, 0.0, 0.0, 1.0)

    graph_program_shaders := common.compile_shader_program({
        vertex_path = "homework1/graph.vert",
        fragment_path = "homework1/graph.frag",
    }) or_return
    defer common.destroy_shader_program(graph_program_shaders)
    graph_program := graph_program_shaders.program

    graph_uniforms := common.get_uniform_locations(struct {
        low_color,
        high_color,
        low_value,
        high_value,
        view: i32
    }, graph_program)
    gl.UseProgram(graph_program)
    gl.Uniform3f(graph_uniforms.low_color, 0/255.0, 0/255.0, 40/255.0)
    gl.Uniform3f(graph_uniforms.high_color, 255/255.0, 128/255.0, 46/255.0)
    gl.Uniform1f(graph_uniforms.low_value, -1.0)
    gl.Uniform1f(graph_uniforms.high_value, 1.0)

    graph_vao: u32 = ---
    gl.GenVertexArrays(1, &graph_vao)
    gl.BindVertexArray(graph_vao)

    grid_positions_buffer: u32 = ---
    gl.GenBuffers(1, &grid_positions_buffer)
    gl.BindBuffer(gl.ARRAY_BUFFER, grid_positions_buffer)
    common.configure_vao_attribute(0, [2]f32)

    graph_value_buffer: u32 = ---
    gl.GenBuffers(1, &graph_value_buffer)
    gl.BindBuffer(gl.ARRAY_BUFFER, graph_value_buffer)
    common.configure_vao_attribute(1, f32)

    graph_indices_buffer: u32 = ---
    gl.GenBuffers(1, &graph_indices_buffer)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, graph_indices_buffer)

    center: [2]f32 = {0, 0}
    units_per_pixel: f32 = 0.01
    grid_nodes_per_unit: f32 = 20.0
    last_frame_time: f32 = 0
    should_terminate := false
    should_update_grid := true
    current_grid := Grid_Info{}
    view: matrix[4, 4]f32

    grid_vertices := [dynamic][2]f32{}
    index_buffer := [dynamic]u32{}
    graph_values := [dynamic]f32{}

    free_all(context.temp_allocator)

    for !should_terminate {
        for event: sdl.Event = ---; sdl.PollEvent(&event); {
            #partial switch event.type {
                case .QUIT: should_terminate = true
                case .WINDOWEVENT:
                    #partial switch event.window.event {
                        case .RESIZED:
                            sdl.GetWindowSize(window, &dimensions.x, &dimensions.y)
                            gl.Viewport(0, 0, dimensions.x, dimensions.y)
                            should_update_grid = true
                    }
                case .KEYDOWN:
                    #partial switch event.key.keysym.sym {
                        case .ESCAPE: should_terminate = true
                    }
            }
        }

        time := cast(f32)sdl.GetTicks() / 1000
        dt := time - last_frame_time
        defer last_frame_time = time

        gl.UseProgram(graph_program)

        if should_update_grid {
            defer should_update_grid = false
            screen := linalg.to_f32(dimensions)
            units_on_screen := screen * units_per_pixel
            top_left_corner := center - units_on_screen * 0.5
            top_left_grid_node := linalg.to_i32(linalg.floor(top_left_corner * grid_nodes_per_unit))
            num_grid_nodes := linalg.to_i32(linalg.ceil(units_on_screen * grid_nodes_per_unit)) + 1

            grid_params := Grid_Info{
                top_left_grid_node,
                num_grid_nodes,
            }

            // Recompute the grid nodes if the grid has changed (shifted, scaled, etc.)
            if current_grid != grid_params {
                clear(&grid_vertices)
                reserve(&grid_vertices, num_grid_nodes.x * num_grid_nodes.y)
                for i in 0..<num_grid_nodes.y {
                    y := f32(top_left_grid_node.y + i) / grid_nodes_per_unit
                    for j in 0..<num_grid_nodes.x {
                        x := f32(top_left_grid_node.x + j) / grid_nodes_per_unit
                        append(&grid_vertices, [2]f32{x, y}) 
                    }
                }

                gl.BindBuffer(gl.ARRAY_BUFFER, grid_positions_buffer)
                gl.BufferData(gl.ARRAY_BUFFER, len(grid_vertices) * size_of([2]f32), raw_data(grid_vertices), gl.STATIC_DRAW)

                // Undate the index buffer if the grid size has changed
                if current_grid.size != num_grid_nodes {
                    num_x := num_grid_nodes.x
                    num_y := num_grid_nodes.y

                    index_buffer_size := (num_y - 1) * (num_x * 2 + 1)
                    clear(&index_buffer)
                    reserve(&index_buffer, index_buffer_size)

                    for i in 0..<num_y - 1 {
                        for j in 0..<num_x {
                            append(&index_buffer, u32(i * num_x + j))
                            append(&index_buffer, u32((i + 1) * num_x + j))
                        }
                        append(&index_buffer, RESTART_INDEX)
                    }

                    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, graph_indices_buffer)
                    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(index_buffer) * size_of(u32), raw_data(index_buffer), gl.STATIC_DRAW)

                    // Reallocate the value buffer if the new grid is larger
                    if num_x * num_y > current_grid.size.x * current_grid.size.y {
                        resize(&graph_values, num_x * num_y)
                        gl.BindBuffer(gl.ARRAY_BUFFER, graph_value_buffer)
                        gl.BufferData(gl.ARRAY_BUFFER, len(graph_values) * size_of(f32), raw_data(graph_values), gl.DYNAMIC_DRAW)
                    }
                }

                current_grid = grid_params
            }

            aspect_ratio := f32(dimensions.x) / f32(dimensions.y)
            y_scale := 2 / units_on_screen.y
            x_scale := y_scale / aspect_ratio
            view = matrix[4, 4]f32{
                x_scale, 0, 0, -center.x,
                0, y_scale, 0, -center.y,
                0, 0, 1, 0,
                0, 0, 0, 1,
            }
            view_flat := linalg.matrix_flatten(view)
            gl.UniformMatrix4fv(graph_uniforms.view, 1, false, raw_data(view_flat[:]))
        }

        // Update the graph values
        for i in 0..<len(grid_vertices) {
            v := grid_vertices[i]
            graph_values[i] = function(v.x, v.y, time)
        }
        gl.BindBuffer(gl.ARRAY_BUFFER, graph_value_buffer)
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, len(graph_values) * size_of(f32), raw_data(graph_values))

        // gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.BindVertexArray(graph_vao)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, graph_indices_buffer)
        gl.DrawElements(gl.TRIANGLE_STRIP, cast(i32)len(index_buffer), gl.UNSIGNED_INT, nil)

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
