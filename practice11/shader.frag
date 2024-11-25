#version 330 core

uniform sampler2D tex;
uniform sampler1D palette;

layout (location = 0) out vec4 out_color;

in vec2 texcoord;
in float gsize;

void main() {
    float alpha = texture(tex, texcoord).r;
    float fac = pow(max(1.0 - abs(gsize * 10 - 1.0), 0.4), 2.0);
    vec3 color = texture(palette, alpha * fac).rgb;
    out_color = vec4(color, alpha);
}
