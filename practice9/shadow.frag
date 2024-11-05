#version 330 core

layout (location = 0) out vec4 out_depth_info;

void main() {
    float z = gl_FragCoord.z;
    float dzdx = dFdx(z);
    float dzdy = dFdy(z);
    out_depth_info = vec4(z, z * z + (dzdx * dzdx + dzdy * dzdy) / 4.0, 0.0, 0.0);
}
