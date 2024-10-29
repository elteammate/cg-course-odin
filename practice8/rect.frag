#version 330 core

uniform sampler2D tex;

in vec2 uv;
layout (location = 0) out vec4 out_color;

void main() {
    float c = texture(tex, uv).r;
    out_color = vec4(c, c, c, 1.0);
}
