#version 450

layout(binding = 0) uniform CameraObj {
    mat4 view;
    mat4 proj;
} camera;

layout(binding = 1) uniform CubeInstance {
    mat4 model;
    float highlight;
} cube;

layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec3 in_col;

layout(location = 0) out vec3 out_col;

void main() {
    gl_Position = camera.proj * camera.view * cube.model * vec4(in_pos, 1.0);
    out_col = vec3(cube.highlight + in_col.x, cube.highlight + in_col.y, cube.highlight + in_col.z); 
}
