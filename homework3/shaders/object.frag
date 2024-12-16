#version 330 core

#define MAX_LIGHTS 8

uniform bool use_albedo_tex;
uniform vec3 albedo;
uniform sampler2D albedo_tex;

uniform bool use_transparency_tex;
uniform bool use_albedo_for_transparency;
uniform sampler2D transparency_tex;

uniform vec3 glossiness;
uniform float power;

uniform vec3 ambient;

uniform vec3 sun_direction;
uniform vec3 sun_color;
uniform mat4 sun_transform;
uniform sampler2D sun_shadow_map;

uniform int tone_mapping;
uniform int point_light_count;
uniform vec3 point_position[MAX_LIGHTS];
uniform vec3 point_color[MAX_LIGHTS];
uniform vec3 point_attenuation[MAX_LIGHTS];

uniform bool point_zero_has_shadow;
uniform samplerCube point_zero_shadow_map;

uniform float shadow_bias;

uniform vec3 camera_position;
uniform vec3 view_direction;

in vec3 position;
in vec3 normal;
in vec2 texcoord;

layout (location = 0) out vec4 out_color;

const float PI = 3.14159265358979323846;

float diffuse_fac(vec3 direction) {
    return max(0.0, dot(normal, direction));
}

vec3 specular_fac(vec3 direction) {
    vec3 reflected_direction = 2.0 * dot(normal, direction) * normal - direction;
    if (power == 0.0) {
        return glossiness * pow(max(0.0, dot(reflected_direction, normalize(camera_position - position))), power);
    } else {
        return vec3(0.0);
    }
}

const float DELTA = 0.125;

float shadow_fac(sampler2D shadow_map, vec4 shadow_pos) {
    vec2 data = texture(shadow_map, shadow_pos.xy).rg;

    float mu = data.r;
    float sigma = data.g - mu * mu;
    float z = shadow_pos.z;
    float cheb = sigma / (sigma + (z - mu) * (z - mu));
    if (cheb < DELTA) {
        cheb = 0.0;
    } else {
        cheb = (cheb - DELTA) / (1.0 - DELTA);
    }
    return (z < mu + shadow_bias) ? 1.0 : cheb;
}

float cubemap_shadow_fac(samplerCube shadow_map, vec3 point_light_vec) {
    float light_direction_inf_norm = max(
        abs(point_light_vec.x),
        max(
            abs(point_light_vec.y),
            abs(point_light_vec.z)
        )
    );
    vec3 light_direction = -point_light_vec / light_direction_inf_norm;

    const int N = 7;
    float radius = 2.5;
    vec2 sum = vec2(0.0);
    float sum_w = 0.0;
    for (int dx = -N; dx <= N; ++dx) {
        for (int dy = -N; dy <= N; ++dy) {
            vec2 offset_2d = vec2(dx, dy) / vec2(textureSize(shadow_map, 0));
            vec3 offset;
            if (abs(light_direction.x) > 0.999) {
                offset = vec3(0.0, offset_2d);
            } else if (abs(light_direction.y) > 0.999) {
                offset = vec3(offset_2d.x, 0.0, offset_2d.y);
            } else {
                offset = vec3(offset_2d, 0.0);
            }
            float c = exp(-float(dx * dx + dy * dy) / (radius * radius));
            sum += c * texture(shadow_map, light_direction + offset * 2.0).rg;
            sum_w += c;
        }
    }

    vec2 data = sum / sum_w;

    float mu = data.r;
    float sigma = data.g - mu * mu;
    float z = length(point_light_vec);
    float cheb = sigma / (sigma + (z - mu) * (z - mu));
    if (cheb < DELTA) {
        cheb = 0.0;
    } else {
        cheb = (cheb - DELTA) / (1.0 - DELTA);
    }
    return (z < mu + shadow_bias * (z + 1.0)) ? 1.0 : cheb;
}

void main() {
    float transparency = 1.0;
    if (use_transparency_tex) {
        transparency = texture(transparency_tex, texcoord).r;
    }

    vec3 l_albedo;

    if (use_albedo_tex) {
        vec4 tex = texture(albedo_tex, texcoord);
        l_albedo = tex.rgb;
        if (use_albedo_for_transparency) {
            transparency = tex.a;
        }
    } else {
        l_albedo = albedo;
    }
    if (transparency < 0.5) {
        discard;
    }

    vec4 sun_shadow_pos = sun_transform * vec4(position, 1.0);
    sun_shadow_pos /= sun_shadow_pos.w;
    sun_shadow_pos = sun_shadow_pos * 0.5 + 0.5;

    bool in_sun_shadow_texture = (
        sun_shadow_pos.x >= 0.0 &&
        sun_shadow_pos.x <= 1.0 &&
        sun_shadow_pos.y >= 0.0 &&
        sun_shadow_pos.y <= 1.0 &&
        sun_shadow_pos.z >= 0.0 &&
        sun_shadow_pos.z <= 1.0
    );

    float sun_shadow_factor = in_sun_shadow_texture ? shadow_fac(sun_shadow_map, sun_shadow_pos) : 1.0;

    vec3 total_light = ambient;

    total_light += sun_color * (
        diffuse_fac(sun_direction) +
        specular_fac(sun_direction)
    ) * sun_shadow_factor;

    int i = 0;
    if (point_zero_has_shadow) {
        i++;

        vec3 point_light_vec = point_position[0] - position;
        float point_light_dist2 = dot(point_light_vec, point_light_vec);
        float point_light_dist = sqrt(point_light_dist2);
        vec3 point_light_direction = point_light_vec / point_light_dist;
        vec3 attenuation = point_attenuation[0] * vec3(1, point_light_dist, point_light_dist2);
        float point_fraction = 1.0 / (attenuation.x + attenuation.y + attenuation.z);
        float point_shadow_factor = cubemap_shadow_fac(point_zero_shadow_map, point_light_vec);

        total_light += point_color[0] * (
            diffuse_fac(point_light_direction) +
            specular_fac(point_light_direction)
        ) * point_fraction * point_shadow_factor;
    }

    for (; i < point_light_count; ++i) {
        vec3 point_light_vec = point_position[i] - position;
        float point_light_dist2 = dot(point_light_vec, point_light_vec);
        float point_light_dist = sqrt(point_light_dist2);
        vec3 point_light_direction = point_light_vec / point_light_dist;
        vec3 attenuation = point_attenuation[i] * vec3(1, point_light_dist, point_light_dist2);
        float point_fraction = 1.0 / (attenuation.x + attenuation.y + attenuation.z);

        total_light += point_color[i] * (
            diffuse_fac(point_light_direction) +
            specular_fac(point_light_direction)
        ) * point_fraction;
    }

    vec3 hdr = l_albedo * total_light;
    vec3 color;

    if (tone_mapping == 0) { // none
        color = hdr;
    } else if (tone_mapping == 1) { // reinhard
        color = hdr / (hdr + vec3(1.0));
    } else if (tone_mapping == 2) { // arctan
        color = atan(hdr) * (2.0 / PI);
    } else if (tone_mapping == 3) { // ACES
        const float a = 2.51;
        const float b = 0.03;
        const float c = 2.43;
        const float d = 0.59;
        const float e = 0.14;
        color = clamp((hdr * (a * hdr + b)) / (hdr * (c * hdr + d) + e), 0.0, 1.0);
    } else if (tone_mapping == 4) { // Uncharted 2
        const float A = 0.15;
        const float B = 0.50;
        const float C = 0.10;
        const float D = 0.20;
        const float E = 0.02;
        const float F = 0.30;
        const float W = 11.2;
        const float exposureBias = 2.0;
        hdr *= exposureBias;
        vec3 cur = ((hdr * (A * hdr + C * B) + D * E) / (hdr * (A * hdr + B) + D * F)) - E / F;
        const float whiteScale = ((W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F)) - E / F;
        color = cur / whiteScale;
    }

    out_color = vec4(color, 1.0);
}
