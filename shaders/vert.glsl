#version 450

layout(binding = 0) uniform CameraObj {
    mat4 view;
    mat4 proj;
} camera;

layout(binding = 1) uniform CubeInstance {
    mat4 model;
} cube;

layout(location = 0) in vec3 in_pos;

void main() {
    gl_Position = (camera.view * cube.model) * vec4(in_pos, 1.0);
}
