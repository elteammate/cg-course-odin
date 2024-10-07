#version 330 core

layout(location = 0) in vec2 position;
layout(location = 1) in float value;

uniform vec3 low_color;
uniform vec3 high_color;
uniform float low_value;
uniform float high_value;
uniform mat4 view;

out vec3 color;

void main() {
    gl_Position = view * vec4(position, 0.0, 1.0);
    float t = (value - low_value) / (high_value - low_value);
    color = low_color + (high_color - low_color) * t;
}
