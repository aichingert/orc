#include <stdio.h>
#include <assert.h>

#include "vulkan.h"

static const uint8_t VERT[] = {
    #embed "shaders/vert.spv"
};

#define COUNT(ARR) sizeof(ARR) / sizeof(ARR[0])

int main(void) {
    VK_CHECK(volkInitialize());

    assert(glfwInit() && "glfw init failed");
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    GLFWwindow *window = glfwCreateWindow(800, 600, "ren", NULL, NULL);

    uint32_t glfwExtCount;
    const char **glfwExts = glfwGetRequiredInstanceExtensions(&glfwExtCount);

    VkApplicationInfo app_info = { .apiVersion = VK_API_VERSION_1_3 };

    const char *layers[] = { "VK_LAYER_KHRONOS_validation" };
    VkInstanceCreateInfo instanceInfo = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .ppEnabledLayerNames = layers,
        .enabledLayerCount = COUNT(layers),
        .enabledExtensionCount = glfwExtCount,
        .ppEnabledExtensionNames = glfwExts,
    };

    VkInstance instance;
    VK_CHECK(vkCreateInstance(&instanceInfo, NULL, &instance));
    volkLoadInstanceOnly(instance);

    VkPhysicalDevice physical_devices[16];
    uint32_t physical_device_count = COUNT(physical_devices);
    VK_CHECK(vkEnumeratePhysicalDevices(instance, &physical_device_count, physical_devices));

    assert(COUNT(physical_devices) > 0 && "No phyiscal device found");
    VkPhysicalDevice physical_device = physical_devices[0];

    uint32_t family_index = 0;
    float queue_priorities[] = { 1.0f };
    VkDeviceQueueCreateInfo queue_info = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = family_index,
        .queueCount = 1,
        .pQueuePriorities = queue_priorities,
    };

    const char *extensions[] = {
        VK_KHR_SWAPCHAIN_EXTENSION_NAME,
    };

    VkDeviceCreateInfo device_info = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_info,
        .queueCreateInfoCount = 1,
        .ppEnabledExtensionNames = extensions,
        .enabledExtensionCount = COUNT(extensions),
    };

    VkDevice device = {0};
    VK_CHECK(vkCreateDevice(physical_device, &device_info, NULL, &device));
    volkLoadDevice(device);

    VkSurfaceKHR surface;
    VK_CHECK(glfwCreateWindowSurface(instance, window, NULL, &surface));

    int width = 0, height = 0;
    glfwGetWindowSize(window, &width, &height);

    VkSwapchainCreateInfoKHR swap_info = {
        .sType =VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = 2,
        .imageFormat = VK_FORMAT_R8G8B8A8_UNORM,
        .imageColorSpace = VK_COLORSPACE_SRGB_NONLINEAR_KHR,
        .imageExtent = {
            .width = width,
            .height = height,
        },
        .imageArrayLayers = 1,
        .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .queueFamilyIndexCount = 1,
        .pQueueFamilyIndices = &family_index,
        .presentMode = VK_PRESENT_MODE_FIFO_KHR,
    };

    VkSwapchainKHR swapchain = {0};
    VK_CHECK(vkCreateSwapchainKHR(device, &swap_info, NULL, &swapchain));

    VkSemaphoreCreateInfo acq_sema_info = {
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    VkSemaphore acq_semaphore = {0};
    VK_CHECK(vkCreateSemaphore(device, &acq_sema_info, NULL, &acq_semaphore));

    VkSemaphoreCreateInfo rel_sema_info = {
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    VkSemaphore rel_semaphore = {0};
    VK_CHECK(vkCreateSemaphore(device, &rel_sema_info, NULL, &rel_semaphore));

    VkQueue queue = {0};
    vkGetDeviceQueue(device, family_index, 0, &queue);

    VkImage swapchain_images[16];
    uint32_t swapchain_image_count = COUNT(swapchain_images);
    VK_CHECK(vkGetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, swapchain_images));

    VkCommandPoolCreateInfo pool_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
        .queueFamilyIndex = family_index,
    };
    VkCommandPool command_pool = {0};
    VK_CHECK(vkCreateCommandPool(device, &pool_info, NULL, &command_pool));

    VkCommandBufferAllocateInfo allocate_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    VkCommandBuffer command_buffer = {0};
    VK_CHECK(vkAllocateCommandBuffers(device, &allocate_info, &command_buffer));

    while (!glfwWindowShouldClose(window)) {
        uint32_t image_index = 0;
        VK_CHECK(vkAcquireNextImageKHR(device, swapchain, ~0ull, acq_semaphore, VK_NULL_HANDLE, &image_index));
        VK_CHECK(vkResetCommandPool(device, command_pool, 0));

        VkCommandBufferBeginInfo begin_info = {
            .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };

        VK_CHECK(vkBeginCommandBuffer(command_buffer, &begin_info));

        VkClearColorValue color = {0.2, 0.1, 0.1, 1};
        VkImageSubresourceRange range = {
            .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
            .levelCount = 1,
            .layerCount = 1,
        };
        vkCmdClearColorImage(command_buffer, swapchain_images[image_index], VK_IMAGE_LAYOUT_GENERAL, &color, 1, &range);
        VK_CHECK(vkEndCommandBuffer(command_buffer));

        VkPipelineStageFlags submit_stage_mask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        VkSubmitInfo submit_info = {
            .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &acq_semaphore,
            .pWaitDstStageMask = &submit_stage_mask,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffer,
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &rel_semaphore,
        };
        vkQueueSubmit(queue, 1, &submit_info, VK_NULL_HANDLE);

        VkPresentInfoKHR present_info = {
            .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .swapchainCount = 1,
            .pSwapchains = &swapchain,
            .pImageIndices = &image_index,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &rel_semaphore,
        };

        VK_CHECK(vkQueuePresentKHR(queue, &present_info));
        VK_CHECK(vkDeviceWaitIdle(device));

        glfwPollEvents();
    }

    vkDestroySurfaceKHR(instance, surface, NULL);
    vkDestroyInstance(instance, NULL);
    glfwDestroyWindow(window);
    glfwTerminate();
    return 0;
}
