#version 330 core

uniform samplerCube tex;
uniform int side;

in vec2 texcoord;

layout (location = 0) out vec4 out_result;

void main() {
    const int N = 15;
    const float radius = 2.5;
    vec2 sum = vec2(0.0, 0.0);
    float sum_w = 0.0;
    for (int i = -N; i <= N; ++i) {
        float offset = float(i) / float(textureSize(tex, 0).x);
        vec2 texcoord = vec2(texcoord.x, texcoord.y + offset) * 2.0 - 1.0;

        vec3 query;
        if (side == 0) query = vec3(1.0, -texcoord.y, -texcoord.x);
        if (side == 1) query = vec3(-1.0, texcoord.y, texcoord.x);
        // if (side == 1) query = vec3(-1.0, texcoord.y, -texcoord.x);
        if (side == 2) query = vec3(texcoord.x, 1.0, texcoord.y);
        if (side == 3) query = vec3(texcoord.x, -1.0, texcoord.y);
        if (side == 4) query = vec3(texcoord, 1.0);
        if (side == 5) query = vec3(texcoord, -1.0);

        float c = exp(-float(i * i) / (radius * radius));
        sum += c * texture(tex, query).rg;
        sum_w += c;
    }

    out_result = vec4(sum / sum_w * 0.001, 0.0, 0.0);
}
