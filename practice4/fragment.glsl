#version 330 core

in vec3 normal;

layout (location = 0) out vec4 out_color;

void main()
{
    vec3 ambient_dir = vec3(0.0, 1.0, 0.0);
    vec3 ambient_color = vec3(0.2);

    vec3 light1_dir = normalize(vec3( 3.0, 2.0,  1.0));
    vec3 light2_dir = normalize(vec3(-3.0, 2.0, -1.0));

    vec3 light1_color = vec3(1.0,  0.5, 0.25);
    vec3 light2_color = vec3(0.25, 0.5, 1.0 );

    vec3 n = normalize(normal);

    vec3 color = (0.5 + 0.5 * dot(n, ambient_dir)) * ambient_color
        + max(0.0, dot(n, light1_dir)) * light1_color
        + max(0.0, dot(n, light2_dir)) * light2_color
        ;

    float gamma = 1.0 / 2.2;
    out_color = vec4(pow(min(vec3(1.0), color), vec3(gamma)), 1.0);
}