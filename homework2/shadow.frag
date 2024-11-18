#version 330 core

uniform bool use_transparency_tex;
uniform sampler2D transparency_tex;

in vec2 texcoord;

layout (location = 0) out vec4 out_depth_info;

void main() {
    float transparency = 1.0;
    if (use_transparency_tex) {
        transparency = texture(transparency_tex, texcoord).r;
    }

    if (transparency < 0.5) {
        discard;
    }

    float z = gl_FragCoord.z;
    float dzdx = dFdx(z);
    float dzdy = dFdy(z);
    out_depth_info = vec4(z, z * z + (dzdx * dzdx + dzdy * dzdy) / 4.0, 0.0, 0.0);
}
