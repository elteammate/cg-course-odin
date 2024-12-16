#version 330 core

uniform bool use_albedo_for_transparency;
uniform bool use_transparency_tex;
uniform sampler2D transparency_tex;
uniform bool use_albedo_tex;
uniform sampler2D albedo_tex;
uniform bool is_point;
uniform vec3 point_position;

in vec2 texcoord;
in vec3 position;

layout (location = 0) out vec4 out_depth_info;

void main() {
    float transparency = 1.0;
    if (use_transparency_tex) {
        transparency = texture(transparency_tex, texcoord).r;
    }

    if (use_albedo_tex) {
        vec4 tex = texture(albedo_tex, texcoord);
        if (use_albedo_for_transparency) {
            transparency = tex.a;
        }
    } if (transparency < 0.5) {
        discard;
    }

    float z = is_point ? length(position - point_position) : gl_FragCoord.z;
    float dzdx = dFdx(z);
    float dzdy = dFdy(z);
    out_depth_info = vec4(z, z * z + (dzdx * dzdx + dzdy * dzdy) / 4.0, 0.0, 0.0);
}
