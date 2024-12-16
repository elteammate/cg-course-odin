#version 330 core

uniform sampler2D tex;
uniform bool vertical;

in vec2 texcoord;

layout (location = 0) out vec4 out_result;

void main() {
    const int N = 15;
    const float radius = 2.5;
    vec2 sum = vec2(0.0, 0.0);
    float sum_w = 0.0;
    for (int i = -N; i <= N; ++i) {
        vec2 offset = vertical ? vec2(0.0, float(i)) : vec2(float(i), 0.0);
        offset /= vec2(textureSize(tex, 0));
        float c = exp(-float(i * i) / (radius * radius));
        sum += c * texture(tex, texcoord + offset).rg;
        sum_w += c;
    }

    out_result = vec4(sum / sum_w, 0.0, 0.0);
}
