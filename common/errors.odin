package common

import "core:strings"
import sdl "vendor:sdl2"


sdl2_panic :: proc(msg: string) -> string {
    return strings.concatenate({
        "SDL2 Error (", msg, "): ", string(sdl.GetError())
    })
}
