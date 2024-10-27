#version 330 core

uniform vec3 camera_position;

uniform vec3 albedo;

uniform vec3 sun_direction;
uniform vec3 sun_color;

in vec3 position;
in vec3 normal;

layout (location = 0) out vec4 out_color;

vec3 diffuse(vec3 direction) {
    return albedo * max(0.0, dot(normal, direction));
}

vec3 specular(vec3 direction) {
    float power = 64.0;
    vec3 reflected_direction = 2.0 * normal * dot(normal, direction) - direction;
    vec3 view_direction = normalize(camera_position - position);
    return albedo * pow(max(0.0, dot(reflected_direction, view_direction)), power);
}

vec3 phong(vec3 direction) {
    return diffuse(direction) + specular(direction);
}

void main()
{
    float ambient_light = 0.2;
    vec3 color = albedo * ambient_light + sun_color * phong(sun_direction);
    out_color = vec4(color, 1.0);
}