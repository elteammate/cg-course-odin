#version 330 core

uniform vec3 light_direction;
uniform vec3 camera_position;

uniform sampler2D albedo_texture;

in vec3 position;
in vec3 tangent;
in vec3 normal;
in vec2 texcoord;

layout (location = 0) out vec4 out_color;

const float PI = 3.141592653589793;

void main()
{
    float ambient_light = 0.2;

    float lightness = ambient_light + max(0.0, dot(normalize(normal), light_direction));

    vec3 albedo = texture(albedo_texture, texcoord).rgb;

    out_color = vec4(lightness * albedo, 1.0);
}