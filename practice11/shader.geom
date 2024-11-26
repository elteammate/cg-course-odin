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
    vec3 z = normalize(camera_position - world.xyz);
    // vec3 x = normalize(cross(vec3(1.0, z.y + floor(abs(z.x + z.x)), z.z), z));
    vec3 x = normalize(cross(vec3(0.568374, 0.298576, 0.458673), z));
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