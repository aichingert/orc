#version 450

layout(binding = 0) uniform CameraObj {
    mat4 view;
    mat4 proj;
} camera;

layout(binding = 1) uniform CubeInstance {
    mat4 model;
} cube;

layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec3 in_col;

layout(location = 0) out vec3 out_col;

void main() {
    gl_Position = /* camera.view */ cube.model * vec4(in_pos, 1.0);
    out_col = in_col;
}
