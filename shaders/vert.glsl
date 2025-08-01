#version 450

layout(binding = 0) uniform UniformBufferObject {
    mat4 model;
    mat4 view;
    mat4 proj;
} ubo;

layout(location = 0) in vec3 in_pos;

void main() {
    gl_Position = vec4(in_pos, 1.0);
}
