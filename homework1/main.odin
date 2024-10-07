package main

import "core:fmt"
import "core:strings"
import "core:c"
import "core:os"
import "core:math"
import "core:math/linalg"
import "core:reflect"
import "core:testing"

import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

import common "../common"

hash :: proc(seed: u32, i, j: i32) -> u32 {
    return u32(i) * 601486597 + u32(j) * 1302311863 + seed * 1182399403
}

perlin :: proc(seed: u32, x, y, t: f32) -> (value: f32, grad: [2]f32) {
    x0, y0 := math.floor(x), math.floor(y)
    x1, y1 := x0 + 1, y0 + 1
    p := [2]f32{x - x0, y - y0}

    i := i32(x0)
    j := i32(y0)

    hash00 := hash(seed, i, j) 
    hash01 := hash(seed, i, j + 1)
    hash10 := hash(seed, i + 1, j)
    hash11 := hash(seed, i + 1, j + 1)

    val00, raw_speed00 := hash00 >> 20, hash00 & (1 << 17)
    val01, raw_speed01 := hash01 >> 20, hash01 & (1 << 17)
    val10, raw_speed10 := hash10 >> 20, hash10 & (1 << 17)
    val11, raw_speed11 := hash11 >> 20, hash11 & (1 << 17)

    speed00 := f32(raw_speed00) / 2e5
    speed01 := f32(raw_speed01) / 2e5
    speed10 := f32(raw_speed10) / 2e5
    speed11 := f32(raw_speed11) / 2e5

    zip2 :: proc(a, b: f32) -> [2]f32 { return {a, b} }
    interpolate :: proc(a, b: f32, t: f32) -> f32 { return (b - a) * (3 - t * 2) * t * t + a }

    g00 := zip2(math.sincos(speed00 * t + f32(val00)))
    g01 := zip2(math.sincos(speed01 * t + f32(val01)))
    g10 := zip2(math.sincos(speed10 * t + f32(val10)))
    g11 := zip2(math.sincos(speed11 * t + f32(val11)))

    d00 := linalg.dot(g00, [2]f32{-p.x, -p.y})
    d01 := linalg.dot(g01, [2]f32{-p.x, 1 - p.y})
    d10 := linalg.dot(g10, [2]f32{1 - p.x, -p.y})
    d11 := linalg.dot(g11, [2]f32{1 - p.x, 1 - p.y})

    d00_grad := g00
    d01_grad := [2]f32{g01.x, -g01.y}
    d10_grad := [2]f32{-g10.x, g10.y}
    d11_grad := [2]f32{-g11.x, -g11.y}

    value = interpolate(
        interpolate(d00, d10, p.x),
        interpolate(d01, d11, p.x),
        p.y,
    )

    return
}

function :: proc(x, y, t: f32) -> f32 {
    value, grad := perlin(0, x, y, t)
    return value
}

Grid_Info :: struct {
    low: [2]i32,
    size: [2]i32,
}

RESTART_INDEX: u32 : 0xFFFFFFFF

Edge_Continuation :: struct {
    begin: u32,
    end: u32,
    has_next: bool,
    next: u32,
    edge1: u32,
    edge2: u32,
}

edge_continuation :: proc(size: [2]u32, id: u32) -> (cont: Edge_Continuation) {
    gsize := size - 1
    horizontal_edges := gsize.x * size.y
    vertical_edges := size.x * gsize.y
    diagonal_edges := gsize.x * gsize.y

    idx := id
    flipped := (idx & 1) != 0
    idx >>= 1

    type: enum u16 {
        Horizontal,
        Vertical,
        Diagonal,
    } = ---
    row: u32 = ---
    col: u32 = ---

    if idx < horizontal_edges {
        row = idx / gsize.x
        col = idx - row * gsize.x
        type = .Horizontal
    } else if idx -= horizontal_edges; idx < vertical_edges {
        row = idx / size.x
        col = idx - row * size.x
        type = .Vertical
    } else {
        idx -= vertical_edges
        row = idx / gsize.x
        col = idx - row * gsize.x
        type = .Diagonal
    }

    switch type {
        case .Horizontal:
            if !flipped {
                cont.begin = row * size.x + col
                cont.end = row * size.x + col + 1
                cont.has_next = row != gsize.y
                if cont.has_next {
                    cont.next = (row + 1) * size.x + col
                    cont.edge1 = (idx + horizontal_edges + vertical_edges) << 1
                    cont.edge2 = (idx + horizontal_edges + row) << 1
                }
            } else {
                cont.begin = row * size.x + col + 1
                cont.end = row * size.x + col
                cont.has_next = row != 0
                if cont.has_next {
                    cont.next = (row - 1) * size.x + col + 1
                    cont.edge1 = ((row - 1) * gsize.x + col + horizontal_edges + vertical_edges) << 1 | 1
                    cont.edge2 = ((row - 1) * size.x + col + horizontal_edges + 1) << 1 | 1
                }
            }
        case .Vertical:
            if !flipped {
                cont.begin = (row + 1) * size.x + col
                cont.end = row * size.x + col
                cont.has_next = col != 0
                if cont.has_next {
                    cont.next = (row + 1) * size.x + col - 1
                    cont.edge1 = (row * gsize.x + col - 1 + horizontal_edges + vertical_edges) << 1 | 1
                    cont.edge2 = ((row + 1) * gsize.x + col - 1) << 1
                }
            } else {
                cont.begin = row * size.x + col
                cont.end = (row + 1) * size.x + col
                cont.has_next = col != gsize.x
                if cont.has_next {
                    cont.next = row * size.x + col + 1
                    cont.edge1 = (row * gsize.x + col + horizontal_edges + vertical_edges) << 1
                    cont.edge2 = (row * gsize.x + col) << 1 | 1
                }
            }
        case .Diagonal:
            if !flipped {
                cont.begin = row * size.x + col + 1
                cont.end = (row + 1) * size.x + col
                cont.has_next = true
                cont.next = (row + 1) * size.x + col + 1
                cont.edge1 = ((row + 1) * gsize.x + col) << 1
                cont.edge2 = (row * size.x + col + 1 + horizontal_edges) << 1 | 1
            } else {
                cont.begin = (row + 1) * size.x + col
                cont.end = row * size.x + col + 1
                cont.has_next = true
                cont.next = row * size.x + col
                cont.edge1 = (row * gsize.x + col) << 1 | 1
                cont.edge2 = (row * size.x + col + horizontal_edges) << 1
            }
    }
    return
}

edge_between :: proc(size: [2]u32, a, b: [2]u32) -> u32 {
    gsize := size - 1
    horizontal_edges := gsize.x * size.y
    vertical_edges := size.x * gsize.y
    diagonal_edges := gsize.x * gsize.y

    a, b := a, b
    flipped: u32 = 0
    if a.y > b.y || a.y == b.y && a.x > b.x do a, b, flipped = b, a, 1

    if a.x == b.x && a.y + 1 == b.y {
        return (horizontal_edges + a.y * size.x + a.x) << 1 | (1 - flipped)
    } else if a.x + 1 == b.x && a.y == b.y {
        return (a.y * gsize.x + a.x) << 1 | flipped
    } else if a.x == b.x + 1 && a.y + 1 == b.y {
        return (horizontal_edges + vertical_edges + a.y * gsize.x + b.x) << 1 | flipped
    } else {
        panic(fmt.tprintf("Vertices do not form an edge: %v, %v", a, b))
    }
}

@(test) test_edge_nodes :: proc(t: ^testing.T) {
    size := [2]u32{4, 3}
    testing.expect_value(t, edge_continuation(size, 0), Edge_Continuation{0, 1, true, 4, 34, 18})
    testing.expect_value(t, edge_continuation(size, 1), Edge_Continuation{1, 0, false, 0, 0, 0})
    testing.expect_value(t, edge_continuation(size, 2), Edge_Continuation{1, 2, true, 5, 36, 20})
    testing.expect_value(t, edge_continuation(size, 17), Edge_Continuation{11, 10, true, 7, 45, 33})
    testing.expect_value(t, edge_continuation(size, 10), Edge_Continuation{6, 7, true, 10, 44, 30})
    testing.expect_value(t, edge_continuation(size, 18), Edge_Continuation{4, 0, false, 0, 0, 0})
    testing.expect_value(t, edge_continuation(size, 19), Edge_Continuation{0, 4, true, 1, 34, 1})
    testing.expect_value(t, edge_continuation(size, 29), Edge_Continuation{5, 9, true, 6, 42, 9})
    testing.expect_value(t, edge_continuation(size, 28), Edge_Continuation{9, 5, true, 8, 41, 12})
    testing.expect_value(t, edge_continuation(size, 23), Edge_Continuation{2, 6, true, 3, 38, 5})
    testing.expect_value(t, edge_continuation(size, 22), Edge_Continuation{6, 2, true, 5, 37, 8})
    testing.expect_value(t, edge_continuation(size, 34), Edge_Continuation{1, 4, true, 5, 6, 21})
    testing.expect_value(t, edge_continuation(size, 35), Edge_Continuation{4, 1, true, 0, 1, 18})
    testing.expect_value(t, edge_continuation(size, 42), Edge_Continuation{6, 9, true, 10, 14, 31})
    testing.expect_value(t, edge_continuation(size, 43), Edge_Continuation{9, 6, true, 5, 9, 28})
}

@(test) test_edge_between :: proc(t: ^testing.T) {
    size := [2]u32{4, 3}
    testing.expect_value(t, edge_between(size, {0, 0}, {0, 1}), 19)
    testing.expect_value(t, edge_between(size, {0, 1}, {0, 0}), 18)
    testing.expect_value(t, edge_between(size, {1, 1}, {1, 2}), 29)
    testing.expect_value(t, edge_between(size, {1, 1}, {2, 1}), 8)
    testing.expect_value(t, edge_between(size, {2, 1}, {1, 1}), 9)
    testing.expect_value(t, edge_between(size, {0, 2}, {1, 1}), 41)
    testing.expect_value(t, edge_between(size, {3, 0}, {2, 1}), 38)
}

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
    gl.CullFace(gl.BACK)
    gl.LineWidth(2.0)
    gl.ClearColor(0.1, 0.0, 0.2, 1.0)

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
        cutoff_low,
        cutoff_high,
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
    defer gl.DeleteVertexArrays(1, &graph_vao)

    grid_positions_buffer: u32 = ---
    gl.GenBuffers(1, &grid_positions_buffer)
    gl.BindBuffer(gl.ARRAY_BUFFER, grid_positions_buffer)
    common.configure_vao_attribute(0, [2]f32)
    defer gl.DeleteBuffers(1, &grid_positions_buffer)

    graph_value_buffer: u32 = ---
    gl.GenBuffers(1, &graph_value_buffer)
    gl.BindBuffer(gl.ARRAY_BUFFER, graph_value_buffer)
    common.configure_vao_attribute(1, f32)
    defer gl.DeleteBuffers(1, &graph_value_buffer)

    graph_indices_buffer: u32 = ---
    gl.GenBuffers(1, &graph_indices_buffer)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, graph_indices_buffer)
    defer gl.DeleteBuffers(1, &graph_indices_buffer)

    isolines_program_shaders := common.compile_shader_program({
        vertex_path = "homework1/isolines.vert",
        fragment_path = "homework1/isolines.frag",
    }) or_return
    defer common.destroy_shader_program(isolines_program_shaders)
    isolines_program := isolines_program_shaders.program
    isolines_uniforms := common.get_uniform_locations(struct {
        cutoff_low,
        cutoff_high,
        view,
        color: i32,
    }, isolines_program)
    gl.UseProgram(isolines_program)
    gl.Uniform3f(isolines_uniforms.color, 1.0, 1.0, 1.0)

    isolines_vao: u32 = ---
    gl.GenVertexArrays(1, &isolines_vao)
    gl.BindVertexArray(isolines_vao)
    defer gl.DeleteVertexArrays(1, &isolines_vao)

    isolines_positions_buffer: u32 = ---
    gl.GenBuffers(1, &isolines_positions_buffer)
    gl.BindBuffer(gl.ARRAY_BUFFER, isolines_positions_buffer)
    common.configure_vao_attribute(0, [2]f32)
    defer gl.DeleteBuffers(1, &isolines_positions_buffer)

    isolines_indices_buffer: u32 = ---
    gl.GenBuffers(1, &isolines_indices_buffer)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, isolines_indices_buffer)
    defer gl.DeleteBuffers(1, &isolines_indices_buffer)

    free_all(context.temp_allocator)

    fixed_size_mode := false
    fixed_size: [2]f32 = {5, 5}
    paused := false
    logging := false
    speed: f32 = 200.0
    center: [2]f32 = {0, 0}
    units_per_pixel: f32 = 0.01
    grid_nodes_per_unit: f32 = 20.0
    last_frame_time: f32 = 0
    plotting_time: f32 = 0
    should_terminate := false
    should_update_grid := true
    grid := Grid_Info{}
    view: matrix[4, 4]f32
    isolines_low: f32 = -1.0
    isolines_high: f32 = 1.0
    MAX_ISOLINES :: 64
    isoline_count: int = 10

    grid_nodes := [dynamic][2]f32{}
    defer delete(grid_nodes)
    graph_grid_indices := [dynamic]u32{}
    defer delete(graph_grid_indices)
    graph_values := [dynamic]f32{}
    defer delete(graph_values)
    isoline_positions := [dynamic][2]f32{}
    defer delete(isoline_positions)
    isoline_indices := [dynamic]u32{}
    defer delete(isoline_indices)

    pressed := bit_set[enum {
        Up, Down, Left, Right, Mouse
    }]{}

    for !should_terminate {
        defer free_all(context.temp_allocator)
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
                        case .TAB: fixed_size_mode = !fixed_size_mode; should_update_grid = true
                        case .SPACE: paused = !paused
                        case .R: center = {0, 0}; should_update_grid = true
                        case .Q: if isoline_count > 1 do isoline_count -= 1
                        case .E: if isoline_count < MAX_ISOLINES do isoline_count += 1
                        case .Z: 
                            grid_nodes_per_unit *= 1.1
                            should_update_grid = true
                        case .X: 
                            grid_nodes_per_unit /= 1.1
                            should_update_grid = true
                        case .UP: fallthrough
                        case .W: pressed |= {.Up}
                        case .DOWN: fallthrough
                        case .S: pressed |= {.Down}
                        case .LEFT: fallthrough
                        case .A: pressed |= {.Left}
                        case .RIGHT: fallthrough
                        case .D: pressed |= {.Right}
                        case .F: logging = !logging
                        case .C: units_per_pixel *= 1.1; should_update_grid = true
                        case .V: units_per_pixel /= 1.1; should_update_grid = true
                    }

                case .KEYUP:
                    #partial switch event.key.keysym.sym {
                        case .UP: fallthrough
                        case .W: pressed &= ~{.Up}
                        case .DOWN: fallthrough
                        case .S: pressed &= ~{.Down}
                        case .LEFT: fallthrough
                        case .A: pressed &= ~{.Left}
                        case .RIGHT: fallthrough
                        case .D: pressed &= ~{.Right}
                    }

                case .MOUSEWHEEL:
                    units_per_pixel *= math.pow(1.1, -cast(f32)event.wheel.y)
                    should_update_grid = true

                case .MOUSEBUTTONDOWN:
                    pressed |= {.Mouse}

                case .MOUSEBUTTONUP:
                    pressed &= ~{.Mouse}

                case.MOUSEMOTION:
                    if .Mouse in pressed {
                        center += [2]f32{-cast(f32)event.motion.xrel, cast(f32)event.motion.yrel} * units_per_pixel
                        should_update_grid = true
                    }
            }
        }

        time := cast(f32)sdl.GetTicks() / 1000
        dt := time - last_frame_time
        defer last_frame_time = time

        camera_offset := [2]f32{}
        if .Up in pressed do camera_offset.y += 1
        if .Down in pressed do camera_offset.y -= 1
        if .Left in pressed do camera_offset.x -= 1
        if .Right in pressed do camera_offset.x += 1

        if camera_offset != {} {
            center += camera_offset * speed * dt * units_per_pixel
            should_update_grid = true
        }

        if logging {
            fmt.printfln("=================")
            fmt.printfln("Center: %v", center)
            fmt.printfln("Units per pixel: %v", units_per_pixel)
            fmt.printfln("Grid nodes per unit: %v", grid_nodes_per_unit)
            fmt.printfln("Isoline count: %v", isoline_count)
            fmt.printfln("Fixed size mode: %v", fixed_size_mode)
            fmt.printfln("Paused: %v", paused)
            fmt.printfln("Time: %v", plotting_time)
            fmt.printfln("FPS: %v", 1 / dt)
            fmt.printfln("=================")
        }

        if !paused {
            plotting_time += dt
        }

        if should_update_grid {
            fmt.printf("Update cascade: User control -> ")
            defer should_update_grid = false

            new_grid: Grid_Info = ---

            screen := linalg.to_f32(dimensions)
            units_on_screen := fixed_size_mode ? fixed_size : screen * units_per_pixel
            top_left_corner := center - units_on_screen * 0.5
            top_left_grid_node := linalg.to_i32(linalg.floor(top_left_corner * grid_nodes_per_unit))
            num_grid_nodes := linalg.to_i32(linalg.ceil(units_on_screen * grid_nodes_per_unit)) + 2
            new_grid = Grid_Info{
                top_left_grid_node,
                num_grid_nodes,
            }
            aspect_ratio := screen.x / screen.y

            if fixed_size_mode {
                effective_aspect_ratio := fixed_size.x / fixed_size.y
                y_scale := effective_aspect_ratio < aspect_ratio ? 2 / fixed_size.y : 2 / fixed_size.x * aspect_ratio
                x_scale := y_scale / aspect_ratio

                view = matrix[4, 4]f32{
                    x_scale, 0, 0, -center.x * x_scale,
                    0, y_scale, 0, -center.y * y_scale,
                    0, 0, 1, 0,
                    0, 0, 0, 1,
                }
            } else {
                y_scale := 2 / units_on_screen.y
                x_scale := y_scale / aspect_ratio
                view = matrix[4, 4]f32{
                    x_scale, 0, 0, -center.x * x_scale,
                    0, y_scale, 0, -center.y * y_scale,
                    0, 0, 1, 0,
                    0, 0, 0, 1,
                }
            }

            // Recompute the grid nodes if the grid has changed (shifted, scaled, etc.)
            if grid != new_grid {
                fmt.printf("Grid params change -> ")
                defer grid = new_grid

                clear(&grid_nodes)
                reserve(&grid_nodes, new_grid.size.x * new_grid.size.y)
                for i in 0..<new_grid.size.y {
                    y := f32(new_grid.low.y + i) / grid_nodes_per_unit
                    for j in 0..<new_grid.size.x {
                        x := f32(new_grid.low.x + j) / grid_nodes_per_unit
                        append(&grid_nodes, [2]f32{x, y}) 
                    }
                }

                gl.BindBuffer(gl.ARRAY_BUFFER, grid_positions_buffer)
                gl.BufferData(gl.ARRAY_BUFFER, len(grid_nodes) * size_of([2]f32), raw_data(grid_nodes), gl.STATIC_DRAW)

                // Undate the index buffer if the grid size has changed
                if grid.size != new_grid.size {
                    fmt.printf("Grid size change -> ")
                    num_x := new_grid.size.x
                    num_y := new_grid.size.y

                    index_buffer_size := (num_y - 1) * (num_x * 2 + 1)
                    clear(&graph_grid_indices)
                    reserve(&graph_grid_indices, index_buffer_size)

                    for i in 0..<num_y - 1 {
                        for j in 0..<num_x {
                            append(&graph_grid_indices, u32(i * num_x + j))
                            append(&graph_grid_indices, u32((i + 1) * num_x + j))
                        }
                        append(&graph_grid_indices, RESTART_INDEX)
                    }

                    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, graph_indices_buffer)
                    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(graph_grid_indices) * size_of(u32), raw_data(graph_grid_indices), gl.STATIC_DRAW)

                    // Reallocate the value buffer if the new grid is larger
                    if num_x * num_y > cast(i32)len(graph_values) {
                        fmt.printf("Graph values buffer reallocation -> ")
                        resize(&graph_values, num_x * num_y)
                        gl.BindBuffer(gl.ARRAY_BUFFER, graph_value_buffer)
                        gl.BufferData(gl.ARRAY_BUFFER, len(graph_values) * size_of(f32), raw_data(graph_values), gl.DYNAMIC_DRAW)
                    }
                }
            }

            view_flat := linalg.matrix_flatten(view)
            cutoff_low := center - units_on_screen * 0.5
            cutoff_high := center + units_on_screen * 0.5
            gl.UseProgram(graph_program)
            gl.UniformMatrix4fv(graph_uniforms.view, 1, false, raw_data(view_flat[:]))
            gl.Uniform2f(graph_uniforms.cutoff_low, cutoff_low.x, cutoff_low.y)
            gl.Uniform2f(graph_uniforms.cutoff_high, cutoff_high.x, cutoff_high.y)
            gl.UseProgram(isolines_program)
            gl.UniformMatrix4fv(isolines_uniforms.view, 1, false, raw_data(view_flat[:]))
            gl.Uniform2f(isolines_uniforms.cutoff_low, cutoff_low.x, cutoff_low.y)
            gl.Uniform2f(isolines_uniforms.cutoff_high, cutoff_high.x, cutoff_high.y)

            fmt.printfln("|-")
        }


        // Update the graph values
        for v, i in grid_nodes do graph_values[i] = function(v.x, v.y, plotting_time)
        gl.BindBuffer(gl.ARRAY_BUFFER, graph_value_buffer)
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, len(graph_values) * size_of(f32), raw_data(graph_values))

        edge_count := (grid.size.x - 1) * grid.size.y + grid.size.x * (grid.size.y - 1) + (grid.size.x - 1) * (grid.size.y - 1)
        isolines_used := make([]bit_set[0..<MAX_ISOLINES], edge_count, context.temp_allocator)

        walk_isoline :: proc(
            used: []bit_set[0..<MAX_ISOLINES],
            line_idx: int,
            value: f32,
            size: [2]u32,
            nodes: [][2]f32,
            indices: ^[dynamic]u32,
            positions: ^[dynamic][2]f32,
            values: []f32,
            edge: u32,
        ) {
            if line_idx in used[edge >> 1] do return
            edge := edge
            defer append(indices, RESTART_INDEX)

            cont := edge_continuation(size, edge)
            {
                x, y := nodes[cont.begin], nodes[cont.end]
                fx, fy := values[cont.begin], values[cont.end]
                t := (value - fx) / (fy - fx)
                // assert(t >= 0 && t <= 1)
                append(indices, cast(u32)len(positions))
                append(positions, linalg.lerp(x, y, t))
            }

            for {
                used[edge >> 1] |= {line_idx}
                if !cont.has_next do return

                x, y, z := nodes[cont.begin], nodes[cont.end], nodes[cont.next]
                fx, fy, fz := values[cont.begin], values[cont.end], values[cont.next]
                go_second := false
                if fx <= fy {
                    go_second = value <= fz
                } else {
                    go_second = value >= fz
                }

                p: [2]f32 = ---
                if go_second {
                    t := (value - fx) / (fz - fx)
                    // assert(t >= 0 && t <= 1)
                    p = linalg.lerp(x, z, t)
                } else {
                    t := (value - fy) / (fz - fy)
                    // assert(t >= 0 && t <= 1)
                    p = linalg.lerp(y, z, t)
                }
                append(indices, cast(u32)len(positions))
                append(positions, p)

                edge = go_second ? cont.edge2 : cont.edge1
                if line_idx in used[edge >> 1] do break
                cont = edge_continuation(size, edge)
            }
        }

        walk_all_isolines :: proc(
            used: []bit_set[0..<MAX_ISOLINES],
            x_pos, y_pos: [2]u32,
            isolines_low: f32,
            isolines_high: f32,
            isoline_count: int,
            size: [2]u32,
            nodes: [][2]f32,
            indices: ^[dynamic]u32,
            positions: ^[dynamic][2]f32,
            values: []f32,
        ) {
            isoline_height := (isolines_high - isolines_low) / f32(isoline_count + 1)

            x_ind := x_pos.y * size.x + x_pos.x
            y_ind := y_pos.y * size.x + y_pos.x

            x, y := nodes[x_ind], nodes[y_ind]
            fx, fy := values[x_ind], values[y_ind]
            mn, mx := min(fx, fy), max(fx, fy)

            lowest_isoline_index := int(math.floor((mn - isolines_low) / isoline_height) + 1)
            high_isoline_index := int(math.ceil((mx - isolines_low) / isoline_height) - 1)

            if high_isoline_index < lowest_isoline_index do return
            edge := edge_between(size, x_pos, y_pos)

            for i in lowest_isoline_index..=high_isoline_index {
                value := isolines_low + f32(i) * isoline_height
                walk_isoline(used, i, value, size, nodes, indices, positions, values, edge)
            }
        }

        clear(&isoline_positions)
        clear(&isoline_indices)
        for j in 0..<u32(grid.size.x) - 1 {
            walk_all_isolines(
                isolines_used, {j + 1, u32(grid.size.y) - 1}, {j, u32(grid.size.y) - 1}, isolines_low, isolines_high, isoline_count,
                linalg.to_u32(grid.size), grid_nodes[:], &isoline_indices, &isoline_positions, graph_values[:],
            )
            walk_all_isolines(
                isolines_used, {j, 0}, {j + 1, 0}, isolines_low, isolines_high, isoline_count,
                linalg.to_u32(grid.size), grid_nodes[:], &isoline_indices, &isoline_positions, graph_values[:],
            )
        }
        for i in 0..<u32(grid.size.y) - 1 {
            walk_all_isolines(
                isolines_used, {0, i}, {0, i + 1}, isolines_low, isolines_high, isoline_count,
                linalg.to_u32(grid.size), grid_nodes[:], &isoline_indices, &isoline_positions, graph_values[:],
            )
            walk_all_isolines(
                isolines_used, {u32(grid.size.x) - 1, i + 1}, {u32(grid.size.x) - 1, i}, isolines_low, isolines_high, isoline_count,
                linalg.to_u32(grid.size), grid_nodes[:], &isoline_indices, &isoline_positions, graph_values[:],
            )
        }

        for i in 0..<u32(grid.size.y) - 1 {
            for j in 0..<u32(grid.size.x) {
                walk_all_isolines(
                    isolines_used, {j, i}, {j, i + 1}, isolines_low, isolines_high, isoline_count,
                    linalg.to_u32(grid.size), grid_nodes[:], &isoline_indices, &isoline_positions, graph_values[:],
                )
            }
        }

        if len(isoline_indices) > 4e5 {
            fmt.println("Warning: Too many isolines, reducing the count")
            isoline_count -= 1
            continue
        }

        if len(graph_grid_indices) > 4e5 {
            fmt.println("Warning: Too many grid indices, reducing the grid size")
            grid_nodes_per_unit *= 0.9
            should_update_grid = true
            continue
        }

        gl.BindBuffer(gl.ARRAY_BUFFER, isolines_positions_buffer)
        gl.BufferData(gl.ARRAY_BUFFER, len(isoline_positions) * size_of([2]f32), raw_data(isoline_positions), gl.DYNAMIC_DRAW)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, isolines_indices_buffer)
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(isoline_indices) * size_of(u32), raw_data(isoline_indices), gl.DYNAMIC_DRAW)

        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.UseProgram(graph_program)
        gl.BindVertexArray(graph_vao)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, graph_indices_buffer)
        gl.DrawElements(gl.TRIANGLE_STRIP, cast(i32)len(graph_grid_indices), gl.UNSIGNED_INT, nil)

        gl.UseProgram(isolines_program)
        gl.BindVertexArray(isolines_vao)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, isolines_indices_buffer)
        gl.DrawElements(gl.LINE_STRIP, cast(i32)len(isoline_indices), gl.UNSIGNED_INT, nil)

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
