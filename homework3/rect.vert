#version 330 core

vec2 vertices[6] = vec2[6](
    vec2(-1.0, -1.0),
    vec2( 1.0, -1.0),
    vec2( 1.0,  1.0),
    vec2(-1.0, -1.0),
    vec2( 1.0,  1.0),
    vec2(-1.0,  1.0)
);

uniform vec2 center;
uniform vec2 size;

out vec2 texcoord;

void main()
{
    vec2 position = vertices[gl_VertexID];
    gl_Position = vec4(position * size * 0.5 + center, 0.0, 1.0);
    texcoord = position * 0.5 + vec2(0.5);
}
