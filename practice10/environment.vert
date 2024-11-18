#version 330 core

uniform mat4 view_projection_inverse;

vec2 vertices[3] = vec2[3](
    vec2(0.0, 0.0),
    vec2(2.0, 0.0),
    vec2(0.0, 2.0)
);

out vec2 texcoord;
out vec3 position;

void main() {
    texcoord = vertices[gl_VertexID];
    vec2 ndc_position = texcoord * 2.0 - 1.0;
    gl_Position = vec4(ndc_position, 0.999, 1.0);

    vec4 ndc = vec4(ndc_position, 0.0, 1.0);
    vec4 clip_space = view_projection_inverse * ndc;
    position = clip_space.xyz / clip_space.w;
}
