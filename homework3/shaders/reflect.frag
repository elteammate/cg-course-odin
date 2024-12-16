#version 330 core

#define MAX_LIGHTS 8

uniform samplerCube cubemap;

uniform float fog_half_distance;
uniform vec3 fog_color;

uniform int tone_mapping;
uniform vec3 ambient;
uniform vec3 camera_position;
uniform vec3 view_direction;
uniform mat4 model;

in vec3 position;
in vec3 normal;

layout (location = 0) out vec4 out_color;

const float PI = 3.14159265358979323846;

void main() {
    vec3 center = (model * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    vec3 camera_ray = position - camera_position;
    vec3 n = normalize(normal);
    vec3 reflected_direction = reflect(normalize(camera_ray), n);

    vec4 texture_value = texture(cubemap, reflected_direction);
    vec3 hdr = texture_value.rgb;
    float depth = texture_value.a;

    float optical_depth = depth + length(camera_ray);
    hdr = mix(fog_color, hdr, pow(0.5, optical_depth / fog_half_distance));

    vec3 color;

    if (tone_mapping == 0) { // none
        color = hdr;
    } else if (tone_mapping == 1) { // reinhard
        color = hdr / (hdr + vec3(1.0));
    } else if (tone_mapping == 2) { // arctan
        color = atan(hdr) * (2.0 / PI);
    } else if (tone_mapping == 3) { // ACES
        const float a = 2.51;
        const float b = 0.03;
        const float c = 2.43;
        const float d = 0.59;
        const float e = 0.14;
        color = clamp((hdr * (a * hdr + b)) / (hdr * (c * hdr + d) + e), 0.0, 1.0);
    } else if (tone_mapping == 4) { // Uncharted 2
        const float A = 0.15;
        const float B = 0.50;
        const float C = 0.10;
        const float D = 0.20;
        const float E = 0.02;
        const float F = 0.30;
        const float W = 11.2;
        const float exposureBias = 2.0;
        hdr *= exposureBias;
        vec3 cur = ((hdr * (A * hdr + C * B) + D * E) / (hdr * (A * hdr + B) + D * F)) - E / F;
        const float whiteScale = ((W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F)) - E / F;
        color = cur / whiteScale;
    }

    out_color = vec4(color, 1.0);
}
