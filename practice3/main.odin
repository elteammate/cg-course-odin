package main

import "core:fmt"
import "core:strings"
import "core:c"

import "../glew"
import gl "vendor:OpenGL"
import sdl "vendor:sdl2"

glew_fail :: proc(msg: string, err: gl.GL_Enum) -> string {
    return strings.concatenate({
        "GLEW Error (", msg, "): ", string(glew.GetErrorString(err))
    })
}

sdl2_fail :: proc(msg: string) -> string {
    return strings.concatenate({
        "SDL2 Error (", msg, "): ", string(sdl.GetError())
    })
}

application :: proc() -> Maybe(string) {
    if (sdl.Init(sdl.INIT_VIDEO) != 0) do return sdl2_fail("sdl.Init")
    defer sdl.Quit()

    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_MAJOR_VERSION, 3)
    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_MINOR_VERSION, 3)
    sdl.GL_SetAttribute(sdl.GLattr.CONTEXT_PROFILE_MASK, c.int(sdl.GLprofile.CORE))
    sdl.GL_SetAttribute(sdl.GLattr.DOUBLEBUFFER, 1)
    sdl.GL_SetAttribute(sdl.GLattr.MULTISAMPLESAMPLES, 1)
    sdl.GL_SetAttribute(sdl.GLattr.MULTISAMPLESAMPLES, 4)
    // sdl.GL_SetAttribute(sdl.GLattr.RED_SIZE, 8)
    // sdl.GL_SetAttribute(sdl.GLattr.GREEN_SIZE, 8)
    // sdl.GL_SetAttribute(sdl.GLattr.BLUE_SIZE, 8)
    // sdl.GL_SetAttribute(sdl.GLattr.DEPTH_SIZE, 24)

    window := sdl.CreateWindow(
        "Graphics course practice 4",
        sdl.WINDOWPOS_CENTERED,
        sdl.WINDOWPOS_CENTERED,
        800, 600,
        sdl.WINDOW_OPENGL | sdl.WINDOW_RESIZABLE,
    )
    if window == nil do return sdl2_fail("sdl.CreateWindow")
    defer sdl.DestroyWindow(window)

    width, height: i32 = ---, ---
    sdl.GetWindowSize(window, &width, &height)

    ctx := sdl.GL_CreateContext(window)
    if ctx == nil do return sdl2_fail("sdl.GL_CreateContext")
    defer sdl.GL_DeleteContext(ctx)

    sdl.GL_SetSwapInterval(0)

    if result := glew.Init(); result != gl.GL_Enum.NO_ERROR {
        return glew_fail("glew.Init", result)
    }

    fmt.println("a")
    gl.ClearColor(0.8, 0.8, 1.0, 0.0)
    fmt.println("b")

    return nil
}

main :: proc() {
    err, has_err := application().?
    if has_err {
        fmt.println(err)
    }
}
