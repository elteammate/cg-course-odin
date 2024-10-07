#version 330 core

uniform mat4 view;

layout(location = 0) in vec2 position;
out vec2 pos;

void main() {
    gl_Position = view * vec4(position, 0.0, 1.0);
    pos = position;
}
