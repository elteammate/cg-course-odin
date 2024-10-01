package glew

foreign import glew "system:GLEW"
import "core:c"
import gl "vendor:OpenGL"

@(link_prefix="glew", default_calling_convention="c")
foreign glew {
    Init :: proc() -> gl.GL_Enum ---
    GetErrorString :: proc(err: gl.GL_Enum) -> cstring ---
}
