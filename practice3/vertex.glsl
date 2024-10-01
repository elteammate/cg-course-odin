#version 330 core

uniform mat4 view;

layout (location = 0) in vec2 in_position;
layout (location = 1) in vec4 in_color;
layout (location = 2) in float in_dist;

out vec4 color;
out float dist;

void main()
{
    gl_Position = view * vec4(in_position, 0.0, 1.0);
    dist = in_dist;
    color = in_color;
}