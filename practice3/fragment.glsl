#version 330 core

in vec4 color;
in float dist;

layout (location = 0) out vec4 out_color;

uniform bool use_dist;
uniform float time;

const float speed = 20.0;

void main()
{
    if (!use_dist || mod(dist + time * speed, 40.0) < 20.0) {
        out_color = color;
    } else {
        discard;
    }
}