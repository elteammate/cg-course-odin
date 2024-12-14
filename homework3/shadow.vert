#version 330 core

uniform mat4 model;
uniform mat4 transform;

layout (location = 0) in vec3 in_position;
layout (location = 2) in vec2 in_texcoord;

out vec2 texcoord;
out vec3 position;

void main() {
    position = (model * vec4(in_position, 1.0)).xyz;
    gl_Position = transform * vec4(position, 1.0);
    texcoord = in_texcoord;
}
