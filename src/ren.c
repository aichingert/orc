#include <stdio.h>
#include <assert.h>

#include "vulkan.h"

static const uint8_t VERT[] = {
    #embed "shaders/vert.spv"
};

int main(void) {
    volkInitialize();

    glfwInit();
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    GLFWwindow *window = glfwCreateWindow(800, 600, "ren", NULL, NULL);

    uint32_t glfwExtCount;
    const char** glfwExts = glfwGetRequiredInstanceExtensions(&glfwExtCount);

    VkInstanceCreateInfo instanceInfo = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .enabledExtensionCount = glfwExtCount,
        .ppEnabledExtensionNames = glfwExts
    };

    VkInstance instance;
    VK_CHECK(vkCreateInstance(&instanceInfo, NULL, &instance));

    volkLoadInstance(instance);
    VkSurfaceKHR surface;
    VK_CHECK(glfwCreateWindowSurface(instance, window, NULL, &surface));

    while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();
    }

    vkDestroySurfaceKHR(instance, surface, NULL);
    vkDestroyInstance(instance, NULL);
    glfwDestroyWindow(window);
    glfwTerminate();
    return 0;
}
