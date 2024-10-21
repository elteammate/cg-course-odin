#version 330 core

uniform vec3 camera_position;

in vec3 normal;
in vec3 position;

layout (location = 0) out vec4 out_color;

void main()
{
    vec3 light_direction = vec3(normalize(vec3(1.0, 2.0, 3.0)));
    vec3 light_color = vec3(0.8, 0.3, 0.0);
    vec3 ambient_light = vec3(0.2, 0.2, 0.4);

    vec3 reflected = 2.0 * normal * dot(normal, light_direction) - light_direction;
    vec3 camera_direction = normalize(camera_position - position);

    vec3 albedo = vec3(1.0, 1.0, 1.0);

    vec3 light = ambient_light + light_color * (max(0.0, dot(normal, light_direction)) + pow(max(0.0, dot(camera_direction, reflected)), 64.0));
    vec3 color = albedo * light;
    out_color = vec4(color, 1.0);
}