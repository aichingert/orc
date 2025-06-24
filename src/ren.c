#include <stdio.h>
#include <assert.h>

#include "vulkan.h"

static const uint8_t VERT[] = {
    #embed "../build/spirv/mesh.vert.spv"
};
static const uint8_t FRAG[] = {
    #embed "../build/spirv/mesh.frag.spv"
};

#define COUNT(ARR) sizeof(ARR) / sizeof(ARR[0])

VkRenderPass create_render_pass(VkDevice device, VkFormat format) {
    VkAttachmentReference color_attachments = {
        .attachment = 0,
        .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    VkSubpassDescription subpass = {
        .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachments,
    };
    VkAttachmentDescription attachments[1] = {{
        .format = format,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    }};
    VkRenderPassCreateInfo pass_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = COUNT(attachments),
        .pAttachments = attachments,
        .subpassCount = 1,
        .pSubpasses = &subpass,
    };
    VkRenderPass render_pass = {0};
    VK_CHECK(vkCreateRenderPass(device, &pass_info, NULL, &render_pass));

    return render_pass;
}

VkFramebuffer create_framebuffer(VkDevice device, VkRenderPass render_pass, VkImageView image_view, uint32_t width, uint32_t height) {
    VkFramebufferCreateInfo frame_info = {
        .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        .renderPass = render_pass,
        .attachmentCount = 1,
        .pAttachments = &image_view,
        .width = width,
        .height = height,
        .layers = 1,
    };
    VkFramebuffer framebuffer = {0};
    VK_CHECK(vkCreateFramebuffer(device, &frame_info, NULL, &framebuffer));

    return framebuffer;
}

VkImageView create_image_view(VkDevice device, VkImage image, VkFormat format) {
    VkImageViewCreateInfo view_info = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .viewType = VK_IMAGE_VIEW_TYPE_2D,
        .image = image,
        .format = format,
        .subresourceRange = {
            .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
            .levelCount = 1,
            .layerCount = 1,
        },
    };
    VkImageView image_view = {0};
    VK_CHECK(vkCreateImageView(device, &view_info, NULL, &image_view));

    return image_view;
}

VkFormat get_swapchain_format(VkPhysicalDevice physical_device, VkSurfaceKHR surface) {
    VkSurfaceFormatKHR formats[16] = {0};
    uint32_t format_count = COUNT(formats);

    VK_CHECK(vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, formats));

    // TODO: might need more error handling because of special return format
    assert(format_count > 0 && "no swapchain format found");
    return formats[0].format;
}

VkShaderModule load_shader(VkDevice device, uint8_t const *shader) {

    VkShaderModuleCreateInfo shader_info = {
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = COUNT(shader) / 4,
        .pCode = (uint32_t*)shader,
    };
    VkShaderModule shader_module = {0};
    VK_CHECK(vkCreateShaderModule(device, &shader_info, NULL, &shader_module));

    return shader_module;
}

VkPipeline create_graphics_pipeline(VkDevice device, VkRenderPass render_pass, VkShaderModule vs, VkShaderModule fs) {
    VkPipelineLayoutCreateInfo layout_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, 
    };
    VkPipelineLayout layout = 0;
    VK_CHECK(vkCreatePipelineLayout(device, &layout_info, 0, &layout));

    // TODO: do this properly
    VkPipelineCache cache = {0};

    VkPipelineShaderStageCreateInfo stages[2] = {
        {
            .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_VERTEX_BIT,
            .module = vs,
            .pName = "main",
        },
        {
            .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = fs,
            .pName = "main",
        },
    };
    VkPipelineVertexInputStateCreateInfo vertex_input = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    };
    VkPipelineInputAssemblyStateCreateInfo input_assembly = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    };

    VkPipelineViewportStateCreateInfo viewport_state = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };
    VkPipelineRasterizationStateCreateInfo rasterization_state = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .lineWidth = 1.f,
    };
    
    VkPipelineMultisampleStateCreateInfo multisample_state = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
    };

    VkPipelineDepthStencilStateCreateInfo depth_stencil_state = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    };

    VkPipelineColorBlendStateCreateInfo color_blend_state = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    };
    VkDynamicState dynamic_states[] = { VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };
    VkPipelineDynamicStateCreateInfo dynamic_state = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = COUNT(dynamic_states),
        .pDynamicStates = dynamic_states,
    };

    VkGraphicsPipelineCreateInfo pipeline_info = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = COUNT(stages),
        .pStages = stages,
        .pVertexInputState = &vertex_input,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterization_state,
        .pMultisampleState = &multisample_state,
        .pDepthStencilState = &depth_stencil_state,
        .pColorBlendState = &color_blend_state,
        .pDynamicState = &dynamic_state,
        .layout = layout,
        .renderPass = render_pass,
    };
    VkPipeline pipeline = {0};
    VK_CHECK(vkCreateGraphicsPipelines(device, cache, 1, &pipeline_info, NULL, &pipeline));

    return pipeline;
}

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

    VkFormat format = get_swapchain_format(physical_device, surface);
    int width = 0, height = 0;
    glfwGetWindowSize(window, &width, &height);

    VkSwapchainCreateInfoKHR swap_info = {
        .sType =VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = 2,
        .imageFormat = format,
        .imageColorSpace = VK_COLORSPACE_SRGB_NONLINEAR_KHR,
        .imageExtent = {
            .width = width,
            .height = height,
        },
        .imageArrayLayers = 1,
        .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .queueFamilyIndexCount = 1,
        .pQueueFamilyIndices = &family_index,
        .preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
        .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
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

    VkShaderModule mesh_vs = load_shader(device, VERT);
    VkShaderModule mesh_fs = load_shader(device, FRAG);

    VkRenderPass render_pass = create_render_pass(device, format);
    VkPipeline mesh_pipeline = create_graphics_pipeline(device, render_pass, mesh_vs, mesh_fs);

    VkImage swapchain_images[16];
    uint32_t swapchain_image_count = COUNT(swapchain_images);
    VK_CHECK(vkGetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, swapchain_images));

    VkImageView swapchain_image_views[16];
    VkFramebuffer swapchain_framebuffers[16];

    for (uint32_t i = 0; i < swapchain_image_count; i++) {
        swapchain_image_views[i] = create_image_view(device, swapchain_images[i], format);
    }

    for (uint32_t i = 0; i < swapchain_image_count; i++) {
        swapchain_framebuffers[i] = create_framebuffer(device, render_pass, swapchain_image_views[i], width, height);
    }

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
            .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };

        VK_CHECK(vkBeginCommandBuffer(command_buffer, &begin_info));

        VkClearColorValue color = { 48.f / 255.f, 10.f / 255.f, 36.f / 255.f, 1};
        VkClearValue clear_color = { color };
        VkRenderPassBeginInfo render_pass_info = {
            .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = render_pass,
            .framebuffer = swapchain_framebuffers[image_index],
            .renderArea.extent = {
                .width = width,
                .height = height,
            },
            .clearValueCount = 1,
            .pClearValues = &clear_color,
        };
        vkCmdBeginRenderPass(command_buffer, &render_pass_info, VK_SUBPASS_CONTENTS_INLINE);

        VkViewport viewport = { 0, 0, (float)width, (float)height, 0, 1};
        VkRect2D scissor = { { 0, 0 },  { width, height } };
        
        vkCmdSetViewport(command_buffer, 0, 1, &viewport);
        vkCmdSetScissor(command_buffer, 0, 1, &scissor);

        // draw :)
        vkCmdBindPipeline(command_buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, mesh_pipeline);

        vkCmdEndRenderPass(command_buffer);
        
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
