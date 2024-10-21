#version 330 core

uniform vec3 camera_position;
uniform vec3 albedo;
uniform vec3 ambient_light;

in vec3 position;
in vec3 normal;

layout (location = 0) out vec4 out_color;

void main()
{
    vec3 ambient = albedo * ambient_light;
    vec3 color = ambient;
    out_color = vec4(color, 1.0);
}