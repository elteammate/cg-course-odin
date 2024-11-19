#version 330 core

uniform bool use_transparency_tex;
uniform sampler2D transparency_tex;

in vec2 texcoord;
in vec3 position;

uniform mat4 view;
uniform mat4 projection;

layout (location = 0) out vec4 out_depth_info;

void main() {
    float transparency = 1.0;
    if (use_transparency_tex) {
        transparency = texture(transparency_tex, texcoord).r;
    }

    if (transparency < 0.5) {
        discard;
    }

    vec3 ndc = (projection * view * vec4(position, 1.0)).xyz;

    float z = ndc.z * 0.5 + 0.5;
    float dzdx = dFdx(z);
    float dzdy = dFdy(z);
    out_depth_info = vec4(z, z * z + (dzdx * dzdx + dzdy * dzdy) / 4.0, 0.0, 0.0);
    // out_depth_info = vec4(gl_FragCoord.x * 0.005, z * z + (dzdx * dzdx + dzdy * dzdy) / 4.0, 0.0, 0.0);
}
