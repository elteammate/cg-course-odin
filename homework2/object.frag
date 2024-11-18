#version 330 core

uniform bool use_albedo_tex;
uniform vec3 albedo;
uniform sampler2D albedo_tex;

uniform bool use_transparency_tex;
uniform sampler2D transparency_tex;

uniform vec3 glossiness;
uniform float power;

uniform vec3 ambient;

uniform vec3 sun_direction;
uniform vec3 sun_color;
uniform mat4 sun_transform;
uniform sampler2D sun_shadow_map;

uniform vec3 point_position;
uniform vec3 point_color;
uniform vec3 point_attenuation;
uniform float point_near;
uniform float point_far;
uniform samplerCube point_shadow_map;

uniform float shadow_bias;

uniform vec3 camera_position;
uniform vec3 view_direction;

in vec3 position;
in vec3 normal;
in vec2 texcoord;

layout (location = 0) out vec4 out_color;

float diffuse_fac(vec3 direction) {
    return max(0.0, dot(normal, direction));
}

vec3 specular_fac(vec3 direction) {
    vec3 reflected_direction = 2.0 * dot(normal, direction) * normal - direction;
    return glossiness * pow(max(0.0, dot(reflected_direction, normalize(camera_position - position))), power);
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
        cheb = (cheb - DELTA) / (1 - DELTA);
    }
    return (z < mu + shadow_bias) ? 1.0 : cheb;
}

float cubemap_shadow_fac(samplerCube shadow_map, vec4 shadow_pos) {
    vec2 data = texture(shadow_map, shadow_pos.xyz).rg;

    float mu = data.r;
    float sigma = data.g - mu * mu;
    float z = shadow_pos.w;
    float cheb = sigma / (sigma + (z - mu) * (z - mu));
    if (cheb < DELTA) {
        cheb = 0.0;
    } else {
        cheb = (cheb - DELTA) / (1 - DELTA);
    }
    return (z < mu + shadow_bias) ? 1.0 : cheb;
}

void main() {
    float transparency = 1.0;
    if (use_transparency_tex) {
        transparency = texture(transparency_tex, texcoord).r;
    }

    if (transparency < 0.5) {
        discard;
    }

    vec3 l_albedo;

    if (use_albedo_tex) {
        l_albedo = texture(albedo_tex, texcoord).rgb;
    } else {
        l_albedo = albedo;
    }

    vec4 sun_shadow_pos = sun_transform * vec4(position, 1.0);
    sun_shadow_pos /= sun_shadow_pos.w;
    sun_shadow_pos = sun_shadow_pos * 0.5 + 0.5;

    bool in_sun_shadow_texture = (
        sun_shadow_pos.x > 0.0 &&
        sun_shadow_pos.x < 1.0 &&
        sun_shadow_pos.y > 0.0 &&
        sun_shadow_pos.y < 1.0 &&
        sun_shadow_pos.z > 0.0 &&
        sun_shadow_pos.z < 1.0
    );

    float sun_shadow_factor = in_sun_shadow_texture ? shadow_fac(sun_shadow_map, sun_shadow_pos) : 1.0;

    vec3 point_light_vec = point_position - position;
    float point_light_dist2 = dot(point_light_vec, point_light_vec);
    float point_light_dist = sqrt(point_light_dist2);
    vec3 point_light_direction = point_light_vec / point_light_dist;
    vec3 point_attenuation = point_attenuation * vec3(1, point_light_dist, point_light_dist2);
    float point_fraction = 1.0 / (point_attenuation.x + point_attenuation.y + point_attenuation.z);

    float point_light_dist_l_inf = max(abs(point_light_vec.x), max(abs(point_light_vec.y), abs(point_light_vec.z)));
    float w = (point_light_dist_l_inf - point_near) / (point_far - point_near);
    vec4 point_shadow_pos = vec4(-point_light_vec, w);
    float point_shadow_factor = w < 1.0 && w > 0.0 ? cubemap_shadow_fac(point_shadow_map, point_shadow_pos) : 0.0;

    vec3 color = l_albedo * (
        ambient +
        sun_color * (
            diffuse_fac(sun_direction) +
            specular_fac(sun_direction)
        ) * sun_shadow_factor +
        point_color * (
            diffuse_fac(point_light_direction) +
            specular_fac(point_light_direction)
        ) * point_fraction * point_shadow_factor
    );

    out_color = vec4(color, 1.0);
    // out_color = vec4(texture(point_shadow_map, camera_position - position).rgb, 1.0);
}
