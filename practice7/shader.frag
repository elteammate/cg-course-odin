#version 330 core

uniform vec3 camera_position;
uniform vec3 view_direction;
uniform vec3 albedo;
uniform vec3 ambient_light;
uniform vec3 sun_direction;
uniform vec3 sun_color;
uniform vec3 point_light_position;
uniform vec3 point_light_color;
uniform vec3 point_light_attenuation;
uniform float glossiness;
uniform float roughness;

in vec3 position;
in vec3 normal;

layout (location = 0) out vec4 out_color;

vec3 diffuse(vec3 direction) {
    return albedo * max(0.0, dot(normal, direction));
}

vec3 specular(vec3 direction) {
    float cosine = dot(normal, direction);
    vec3 reflected_direction = 2.0 * normal * cosine - direction;
    float power = 1 / (roughness * roughness) - 1;
    return glossiness * albedo * pow(max(0.0, dot(reflected_direction, view_direction)), power);
}

void main() {
    vec3 ambient = albedo * ambient_light;

    vec3 color = ambient;

    color += (diffuse(sun_direction) + specular(sun_direction)) * sun_color;

    vec3 point_light_vec = point_light_position - position;
    float point_light_dist = length(point_light_vec);
    vec3 point_light_direction = point_light_vec / point_light_dist;
    vec3 coeffs = point_light_attenuation * vec3(point_light_dist * point_light_dist, point_light_dist, 1);
    float fraction = 1 / (coeffs.x + coeffs.y + coeffs.z);
    //dot(coeffs,vec3(1.0))
    color += (diffuse(point_light_direction) + specular(point_light_direction)) * point_light_color * fraction;

    out_color = vec4(color, 0.5);
}