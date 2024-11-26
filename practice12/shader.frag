#version 330 core

uniform vec3 camera_position;
uniform vec3 light_direction;
uniform vec3 bbox_min;
uniform vec3 bbox_max;
uniform sampler3D cloud;

layout (location = 0) out vec4 out_color;

void sort(inout float x, inout float y)
{
    if (x > y)
    {
        float t = x;
        x = y;
        y = t;
    }
}

float vmin(vec3 v)
{
    return min(v.x, min(v.y, v.z));
}

float vmax(vec3 v)
{
    return max(v.x, max(v.y, v.z));
}

vec2 intersect_bbox(vec3 origin, vec3 direction)
{
    vec3 tmin = (bbox_min - origin) / direction;
    vec3 tmax = (bbox_max - origin) / direction;

    sort(tmin.x, tmax.x);
    sort(tmin.y, tmax.y);
    sort(tmin.z, tmax.z);

    return vec2(vmax(tmin), vmin(tmax));
}

const float PI = 3.1415926535;

in vec3 position;

vec3 spatial_to_texture(vec3 p) {
    return (p - bbox_min) / (bbox_max - bbox_min);
}

float density_at(vec3 p) {
    return texture(cloud, spatial_to_texture(p)).r;
}

void main()
{
    vec3 cam_dir = normalize(position - camera_position);
    vec2 bbox_intersection = intersect_bbox(camera_position, cam_dir);
    float tmax = bbox_intersection.y;
    float tmin = max(bbox_intersection.x, 0.0);

    // float absorption = 1.0;
    // float optical_depth = (tmax - tmin) * absorption;
    // float opacity = 1.0 - exp(-optical_depth);

    // vec3 spatial_coords = camera_position + cam_dir * (tmin - tmax) * 0.5;
    // vec3 texture_coords = (spatial_coords - bbox_min) / (bbox_max - bbox_min);

    // /*
    const int NUM_STEPS = 64;
    const int NUM_SCATTERING_STEPS = 16;

    const float absorption = 0.0;
    const float scattering = 16.0;
    const float extinction = absorption + scattering;
    const vec3 light_color = vec3(16.0);
    const vec3 ambient_light = 4.0 * vec3(0.6, 0.8, 1.0);

    vec3 color = vec3(0.0);
    float optical_depth = 0.0;
    float dt = (tmax - tmin) / float(NUM_STEPS);
    for (int i = 0; i < NUM_STEPS; ++i) {
        float t = tmin + (float(i) + 0.5) * dt;
        vec3 p = camera_position + t * cam_dir;
        float density = density_at(p);
        optical_depth += extinction * density * dt;

        bbox_intersection = intersect_bbox(p, light_direction);
        float wmax = bbox_intersection.y;
        float wmin = max(bbox_intersection.x, 0.0); // TODO: 0.0?
        float dw = (wmax - wmin) / float(NUM_SCATTERING_STEPS);
        float light_optical_depth = 0.0;
        for (int j = 0; j < NUM_SCATTERING_STEPS; ++j) {
            float w = wmin + (float(j) + 0.5) * dw;
            vec3 q = p + w * light_direction;
            float q_density = density_at(q);
            light_optical_depth += extinction * q_density * dw;
        }
        color += (
            light_color * exp(-light_optical_depth) + ambient_light
        ) * exp(-optical_depth) * dt * density * scattering / (PI * 4.0);
    }
    float opacity = 1.0 - exp(-optical_depth);
    out_color = vec4(color, opacity);
    // */

    /*
    const int NUM_STEPS = 64;
    const int NUM_SCATTERING_STEPS = 16;

    const vec3 absorption = vec3(0.1, 0.3, 2.0);
    const vec3 scattering = vec3(2.0, 4.0, 8.0);
    const vec3 extinction = absorption + scattering;
    const vec3 light_color = vec3(16.0);
    const vec3 ambient_light = 4.0 * vec3(0.6, 0.8, 1.0);

    vec3 color = vec3(0.0);
    vec3 optical_depth = vec3(0.0);
    float dt = (tmax - tmin) / float(NUM_STEPS);
    for (int i = 0; i < NUM_STEPS; ++i) {
        float t = tmin + (float(i) + 0.5) * dt;
        vec3 p = camera_position + t * cam_dir;
        float density = density_at(p);
        optical_depth += extinction * density * dt;

        bbox_intersection = intersect_bbox(p, light_direction);
        float wmax = bbox_intersection.y;
        float wmin = max(bbox_intersection.x, 0.0); // TODO: 0.0?
        float dw = (wmax - wmin) / float(NUM_SCATTERING_STEPS);
        vec3 light_optical_depth = vec3(0.0);
        for (int j = 0; j < NUM_SCATTERING_STEPS; ++j) {
            float w = wmin + (float(j) + 0.5) * dw;
            vec3 q = p + w * light_direction;
            float q_density = density_at(q);
            light_optical_depth += extinction * q_density * dw;
        }
        color += (
            light_color * exp(-light_optical_depth) + ambient_light
        ) * exp(-optical_depth) * dt * density * scattering / (PI * 4.0);
    }
    vec3 opacity = 1.0 - exp(-optical_depth);
    color += vec3(0.6, 0.8, 1.0) * (1.0 - opacity);
    out_color = vec4(color, 1.0);
    */


    // out_color = vec4(1.0, 0.5, 0.5, 1.0);
    // out_color = vec4(vec3((tmax - tmin) / 4.0), 1.0);
    // out_color = vec4(1.0, 1.0, 0.3, opacity);
    // out_color = vec4(vec3(texture(cloud, texture_coords).r), 1.0);
    // out_color = vec4(color, opacity);
    // out_color = vec4(color, 1.0);
}