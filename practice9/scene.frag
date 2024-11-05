#version 330 core

uniform vec3 ambient;

uniform vec3 light_direction;
uniform vec3 light_color;

uniform mat4 transform;

uniform sampler2D shadow_map;

in vec3 position;
in vec3 normal;

layout (location = 0) out vec4 out_color;

void main()
{
    vec4 shadow_pos = transform * vec4(position, 1.0);
    shadow_pos /= shadow_pos.w;
    shadow_pos = shadow_pos * 0.5 + vec4(0.5);

    bool in_shadow_texture = (shadow_pos.x > 0.0) && (shadow_pos.x < 1.0) && (shadow_pos.y > 0.0) && (shadow_pos.y < 1.0) && (shadow_pos.z > 0.0) && (shadow_pos.z < 1.0);
    float shadow_factor = 1.0;
    if (in_shadow_texture)
        shadow_factor = (texture(shadow_map, shadow_pos.xy).r < shadow_pos.z) ? 0.0 : 1.0;

    vec3 albedo = vec3(1.0, 1.0, 1.0);

    vec3 light = ambient;
    light += light_color * max(0.0, dot(normal, light_direction)) * shadow_factor;
    vec3 color = albedo * light;

    out_color = vec4(color, 1.0);
}