#version 330 core

uniform vec2 cutoff_low;
uniform vec2 cutoff_high;

in vec3 color;
in vec2 pos;

layout (location = 0) out vec4 out_color;

void main() {
    if (pos.x < cutoff_low.x || pos.x > cutoff_high.x || pos.y < cutoff_low.y || pos.y > cutoff_high.y) {
        discard;
    }
    out_color = vec4(color, 1.0);
}