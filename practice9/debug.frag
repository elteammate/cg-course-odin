#version 330 core

uniform sampler2D shadow_map;

in vec2 texcoord;

layout (location = 0) out vec4 out_color;

void main()
{
    out_color = vec4(texture(shadow_map, texcoord).rg, 0.0, 1.0);
}