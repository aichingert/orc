#include <stdio.h>
#include <assert.h>

#define VOLK_IMPLEMENTATION
#include "volk.h"
#define GLFW_INCLUDE_NONE
#include "GLFW/glfw3.h"

static const uint8_t VERT[] = {
    #embed "shaders/vert.spv"
};

#define VK_CHECK(call) \
	do \
	{ \
		VkResult result_ = call; \
		assert(result_ == VK_SUCCESS); \
	} while (0)

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
