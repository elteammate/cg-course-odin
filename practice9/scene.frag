#version 330 core

uniform vec3 ambient;

uniform vec3 light_direction;
uniform vec3 light_color;

uniform mat4 transform;

uniform sampler2D shadow_map;

in vec3 position;
in vec3 normal;

layout (location = 0) out vec4 out_color;

const float SHADOW_BIAS = 1e-2;
const float DELTA = 0.125;

void main()
{
    vec4 shadow_pos = transform * vec4(position, 1.0);
    shadow_pos /= shadow_pos.w;
    shadow_pos = shadow_pos * 0.5 + vec4(0.5);

    bool in_shadow_texture = (shadow_pos.x > 0.0) && (shadow_pos.x < 1.0) && (shadow_pos.y > 0.0) && (shadow_pos.y < 1.0) && (shadow_pos.z > 0.0) && (shadow_pos.z < 1.0);
    float shadow_factor = 1.0;
    if (in_shadow_texture) {
        // vec2 data = texture(shadow_map, shadow_pos.xy).rg;

        const int N = 7;
        float radius = 2.5;
        vec2 sum = vec2(0.0, 0.0);
        float sum_w = 0.0;
        for (int dx = -N; dx <= N; ++dx) {
            for (int dy = -N; dy <= N; ++dy) {
                vec2 offset = vec2(dx, dy) / vec2(textureSize(shadow_map, 0));
                float c = exp(-float(dx * dx + dy * dy) / (radius * radius));
                sum += c * texture(shadow_map, shadow_pos.xy + offset).rg;
                sum_w += c;
            }
        }

        vec2 data = sum / sum_w;

        float mu = data.r;
        float sigma = data.g - mu * mu;
        float z = shadow_pos.z;
        float cheb = sigma / (sigma + (z - mu) * (z - mu));
        if (cheb < DELTA) {
            cheb = 0.0;
        } else {
            cheb = (cheb - DELTA) / (1 - DELTA);
        }
        shadow_factor = (z < mu + SHADOW_BIAS) ? 1.0 : cheb;
        // shadow_factor = (texture(shadow_map, shadow_pos.xy).r < shadow_pos.z - SHADOW_BIAS) ? 0.0 : 1.0;
    }

    vec3 albedo = vec3(1.0, 1.0, 1.0);

    vec3 light = ambient;
    light += light_color * max(0.0, dot(normal, light_direction)) * shadow_factor;
    vec3 color = albedo * light;

    out_color = vec4(color, 1.0);
}