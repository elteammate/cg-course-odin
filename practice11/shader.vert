#version 330 core

layout (location = 0) in vec3 in_position;
layout (location = 1) in float in_size;
layout (location = 2) in float in_rotation;

out float size;
out float rotation;

void main() {
    gl_Position = vec4(in_position, 1.0);
    size = in_size;
    rotation = in_rotation;
}