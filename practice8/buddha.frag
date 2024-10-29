#version 330 core

uniform vec3 camera_position;

uniform vec3 albedo;

uniform vec3 sun_direction;
uniform vec3 sun_color;

uniform mat4 model;
uniform mat4 shadow_projection;
// uniform sampler2D shadow_map;
uniform sampler2DShadow shadow_map;

in vec3 position;
in vec3 normal;

layout (location = 0) out vec4 out_color;

vec3 diffuse(vec3 direction) {
    return albedo * max(0.0, dot(normal, direction));
}

vec3 specular(vec3 direction) {
    float power = 64.0;
    vec3 reflected_direction = 2.0 * normal * dot(normal, direction) - direction;
    vec3 view_direction = normalize(camera_position - position);
    return albedo * pow(max(0.0, dot(reflected_direction, view_direction)), power);
}

vec3 phong(vec3 direction) {
    return diffuse(direction) + specular(direction);
}

void main()
{
    vec4 ndc = shadow_projection * model * vec4(position, 1.0);
    float exposure = 1.0;
    if (abs(ndc.x) <= 1.0 && abs(ndc.y) <= 1.0 && abs(ndc.z) <= 1.0) {
        // vec2 shadow_texcoord = ndc.xy * 0.5 + 0.5;
        // float shadow_depth = ndc.z * 0.5 + 0.5;
        // if (texture(shadow_map, shadow_texcoord).r < shadow_depth) {
        //     exposure = 0.0;
        // }

        // exposure = texture(shadow_map, ndc.xyz * 0.5 + 0.5);

        const int N = 7;
        float radius = 5.0;
        float sum = 0.0;
        float sum_w = 0.0;
        for (int dx = -N; dx <= N; ++dx) {
            for (int dy = -N; dy <= N; ++dy) {
                vec2 offset = vec2(dx, dy) / vec2(textureSize(shadow_map, 0));
                float c = exp(-float(dx * dx + dy * dy) / (radius * radius));
                sum += c * texture(shadow_map, ndc.xyz * 0.5 + 0.5 + vec3(offset, 0.0));
                sum_w += c;
            }
        }

        exposure = sum / sum_w;
    }

    float ambient_light = 0.2;
    vec3 color = albedo * ambient_light + sun_color * phong(sun_direction) * exposure;
    out_color = vec4(color, 1.0);
}