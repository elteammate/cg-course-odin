#version 330 core

uniform sampler2D render_result;
uniform int mode;
uniform float time;

in vec2 texcoord;

layout (location = 0) out vec4 out_color;

void main()
{
    if (mode == 1) {
        out_color = floor(texture(render_result, texcoord) * 4.0) / 3.0;
    } else if (mode == 2) {
        vec2 offset = texcoord - 0.5;
        float dist = sqrt(offset.x * offset.x + offset.y * offset.y);
        float f = sin(dist * 30.0 + time) * 0.01;
        vec2 texc = texcoord + normalize(offset) * f;
        out_color = texture(render_result, texc);
    } else if (mode == 3) {
        const int N = 7;
        float radius = 2.5 * (sin(time * 2.0) + 1.0);
        vec4 sum = vec4(0.0);
        float sum_w = 0.0;
        for (int dx = -N; dx <= N; ++dx) {
            for (int dy = -N; dy <= N; ++dy) {
                vec2 offset = vec2(dx, dy) / vec2(textureSize(render_result, 0));
                float c = exp(-float(dx * dx + dy * dy) / (radius * radius));
                sum += c * texture(render_result, texcoord + offset);
                sum_w += c;
            }
        }

        out_color = sum / sum_w;
    } else {
        out_color = texture(render_result, texcoord);
    }
}