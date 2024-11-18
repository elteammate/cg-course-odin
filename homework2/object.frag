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

uniform vec3 point_position;
uniform vec3 point_color;
uniform vec3 point_attenuation;

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

    vec3 point_light_vec = point_position - position;
    float point_light_dist2 = dot(point_light_vec, point_light_vec);
    float point_light_dist = sqrt(point_light_dist2);
    vec3 point_light_direction = point_light_vec / point_light_dist;
    vec3 point_attenuation = point_attenuation * vec3(1, point_light_dist, point_light_dist2);
    float point_fraction = 1.0 / (point_attenuation.x + point_attenuation.y + point_attenuation.z);

    vec3 color = l_albedo * (
        ambient +
        sun_color * (
            diffuse_fac(sun_direction) +
            specular_fac(sun_direction)
        ) +
        point_color * (
            diffuse_fac(point_light_direction) +
            specular_fac(point_light_direction)
        ) * point_fraction
    );

    out_color = vec4(color, 1.0);
}
