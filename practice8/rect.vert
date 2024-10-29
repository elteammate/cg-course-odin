#version 330 core

out vec2 uv;

const vec2 positions[6] = vec2[6](
    vec2(-1.0, -1.0),
    vec2(-0.5, -1.0),
    vec2(-1.0, -0.5),
    vec2(-1.0, -0.5),
    vec2(-0.5, -1.0),
    vec2(-0.5, -0.5)
);

const vec2 uvs[6] = vec2[6](
    vec2(0.0, 0.0),
    vec2(1.0, 0.0),
    vec2(0.0, 1.0),
    vec2(0.0, 1.0),
    vec2(1.0, 0.0),
    vec2(1.0, 1.0)
);

void main() {
    gl_Position = vec4(positions[gl_VertexID], 0.0, 1.0);
    uv = uvs[gl_VertexID];
}
