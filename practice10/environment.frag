#version 330 core

uniform sampler2D environment_map;
uniform vec3 camera_position;

in vec2 texcoord;
in vec3 position;

layout (location = 0) out vec4 out_color;

const float PI = 3.141592653589793;

void main() {
    vec3 dir = normalize(position - camera_position);

    vec2 env_texcoords = vec2(
        atan(dir.z, dir.x) / PI * 0.5 + 0.5,
        -atan(dir.y, length(dir.xz)) / PI + 0.5
    );

    vec3 environment = texture(environment_map, env_texcoords).rgb;
    out_color = vec4(environment, 1.0);
}
