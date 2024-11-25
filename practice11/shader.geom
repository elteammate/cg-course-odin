#version 330 core

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;
uniform vec3 camera_position;

layout (points) in;
layout (triangle_strip, max_vertices = 4) out;

in float size[];
in float rotation[];

out float gsize;
out vec2 texcoord;

void main() {
    vec3 center = gl_in[0].gl_Position.xyz;
    mat4 transform = projection * view * model;

    vec3 world = (model * vec4(center, 1.0)).xyz;
    vec3 z = camera_position - world.xyz;
    vec3 x = cross(vec3(0.0, 1.0, 0.0), z);
    float len_x = length(x);
    x = len_x == 0.0 ? vec3(1.0, 0.0, 0.0) : x / len_x;
    vec3 y = normalize(cross(z, x));

    float cos_rotation = cos(rotation[0]);
    float sin_rotation = sin(rotation[0]);
    mat3 basis = mat3(cos_rotation * x + sin_rotation * y, -sin_rotation * x + cos_rotation * y, z);

    mat4 projection_view = projection * view;

    gsize = size[0];
    texcoord = vec2(0.0, 0.0);
    gl_Position = projection_view * vec4(world + basis * vec3(-size[0], -size[0], 0.0), 1.0);
    EmitVertex();
    texcoord = vec2(1.0, 0.0);
    gl_Position = projection_view * vec4(world + basis * vec3(+size[0], -size[0], 0.0), 1.0);
    EmitVertex();
    texcoord = vec2(0.0, 1.0);
    gl_Position = projection_view * vec4(world + basis * vec3(-size[0], +size[0], 0.0), 1.0);
    EmitVertex();
    texcoord = vec2(1.0, 1.0);
    gl_Position = projection_view * vec4(world + basis * vec3(+size[0], +size[0], 0.0), 1.0);
    EmitVertex();

    EndPrimitive();
}