package main

import "base:runtime"

import "core:log"
import "core:mem"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

g_ctx: runtime.Context

VERT_SHADER :: #load("vert.spv")
FRAG_SHADER :: #load("frag.spv")

CUBES :: 3 * 9
MAX_FRAMES_BETWEEN :: 2

UNIFORM_BUFFER_BINDING :: 0
UNIFORM_BUFFER_DYNAMIC_BINDING :: 1

Camera :: struct {
    view : matrix[4,4]f32,
    proj : matrix[4,4]f32,
}

CubeData :: struct {
    models: []matrix[4, 4]f32,
}

Vertex :: struct {
    pos : [3]f32,
    // x, y, z : f32,
}

check :: proc(result: vk.Result, loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("vulkan failure %v", result, location = loc)
	}
}

vk_messenger_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = g_ctx

	level: log.Level
	if .ERROR in messageSeverity {
		level = .Error
	} else if .WARNING in messageSeverity {
		level = .Warning
	} else if .INFO in messageSeverity {
		level = .Info
	} else {
		level = .Debug
	}

	log.logf(level, "vulkan[%v]: %s", messageTypes, pCallbackData.pMessage)
	return false
}

vk_create_instance :: proc(instance: ^vk.Instance, dbg_messenger: ^vk.DebugUtilsMessengerEXT) {
    vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress)) 

    assert(vk.CreateInstance != nil, "vulkan function pointers not loaded") 

    extensions := slice.clone_to_dynamic(glfw.GetRequiredInstanceExtensions(), g_ctx.temp_allocator)
    append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

    severity: vk.DebugUtilsMessageSeverityFlagsEXT
    if context.logger.lowest_level <= .Error {
        severity |= {.ERROR}
    }
    if context.logger.lowest_level <= .Warning {
        severity |= {.WARNING}
    }
    if context.logger.lowest_level <= .Info {
        severity |= {.INFO}
    }
    if context.logger.lowest_level <= .Debug {
        severity |= {.VERBOSE}
    }

    dbg_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
        sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        messageSeverity = severity,
        messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
        pfnUserCallback = vk_messenger_callback,
    }

    create_info := vk.InstanceCreateInfo { sType = .INSTANCE_CREATE_INFO,
        pNext = &dbg_create_info,
        pApplicationInfo = &vk.ApplicationInfo { sType = .APPLICATION_INFO,
            pApplicationName = "vorc",
            applicationVersion = vk.MAKE_VERSION(0, 0, 0),
            pEngineName = "none",
            apiVersion = vk.API_VERSION_1_4,
        },
        enabledLayerCount  = 1,
        ppEnabledLayerNames = raw_data([]cstring{"VK_LAYER_KHRONOS_validation"}),
        enabledExtensionCount = u32(len(extensions)),
        ppEnabledExtensionNames = raw_data(extensions),
    } 

    check(vk.CreateInstance(&create_info, nil, instance))
    vk.load_proc_addresses_instance(instance^)

    check(vk.CreateDebugUtilsMessengerEXT(instance^, &dbg_create_info, nil, dbg_messenger))
}

vk_find_queue_family :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> u32 {
    count : u32 = 0
    vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)

    families := make([]vk.QueueFamilyProperties, count, g_ctx.temp_allocator)
    vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(families))

    for family, i in families {
        supported: b32
        vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &supported)

        if .GRAPHICS in family.queueFlags && supported {
            return u32(i)
        }
    }

    assert(false, "Error: no queue family found that supports present and graphics")
    return 0
}

vk_create_device :: proc(
    instance: vk.Instance, 
    surface: vk.SurfaceKHR, 
    physical: ^vk.PhysicalDevice, 
    device: ^vk.Device
) -> (
    family_index: u32,
    queue: vk.Queue,
) {
    count : u32 = 0

    check(vk.EnumeratePhysicalDevices(instance, &count, nil))
    physical_devices := make([^]vk.PhysicalDevice, count, g_ctx.temp_allocator)
    check(vk.EnumeratePhysicalDevices(instance, &count, physical_devices))

    fallback_device: ^vk.PhysicalDevice = nil

    for i : u32 = 0; i < count; i += 1 {
        ext_count: u32 = 0
        vk.EnumerateDeviceExtensionProperties(physical_devices[i], nil, &ext_count, nil)
    log.info("story")
        exts:= make([^]vk.ExtensionProperties, ext_count, g_ctx.temp_allocator)
        vk.EnumerateDeviceExtensionProperties(physical_devices[i], nil, &ext_count, exts)

        supported := false

        for j : u32 = 0; j < ext_count; j += 1 {
            extension := strings.truncate_to_byte(string(exts[j].extensionName[:]), 0)

            if extension == "VK_KHR_dynamic_rendering" {
                supported = true
                break
            }
        }

        if !supported { continue }

        props : vk.PhysicalDeviceProperties
        feats : vk.PhysicalDeviceFeatures

        vk.GetPhysicalDeviceProperties(physical_devices[i], &props)
        vk.GetPhysicalDeviceFeatures(physical_devices[i], &feats)

        if        props.deviceType & .DISCRETE_GPU   == .DISCRETE_GPU   && feats.geometryShader {
            fallback_device = &physical_devices[i]
            break
        } else if props.deviceType & .INTEGRATED_GPU == .INTEGRATED_GPU && feats.geometryShader {
            fallback_device = &physical_devices[i]
        }
    }

    assert(fallback_device != nil, "Error: no device found")
    physical^ = fallback_device^

    family_index = vk_find_queue_family(physical^, surface)

    queue_create_info := vk.DeviceQueueCreateInfo { sType = .DEVICE_QUEUE_CREATE_INFO,
        queueFamilyIndex = family_index,
        queueCount = 1,
        pQueuePriorities = raw_data([]f32{1}),
    }

    dynamic_rendering_feature := vk.PhysicalDeviceDynamicRenderingFeaturesKHR { 
        sType = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR,
        dynamicRendering = true
    }

    create_info := vk.DeviceCreateInfo { sType = .DEVICE_CREATE_INFO,
        pNext = &dynamic_rendering_feature,
        queueCreateInfoCount = 1,
        pQueueCreateInfos = &queue_create_info,
        enabledLayerCount = 1,
        ppEnabledLayerNames = raw_data([]cstring{"VK_LAYER_KHRONOS_validation"}),
        enabledExtensionCount = 2,
        ppEnabledExtensionNames = raw_data([]cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME, "VK_KHR_dynamic_rendering"}),
    }

    check(vk.CreateDevice(physical^, &create_info, nil, device))

    vk.GetDeviceQueue(device^, family_index, 0, &queue)
    return
}

SwapchainSupport :: struct {
	capabilities:   vk.SurfaceCapabilitiesKHR,
	formats:        []vk.SurfaceFormatKHR,
	present_modes:  []vk.PresentModeKHR,
}

vk_query_swapchain_support :: proc(physical: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (support: SwapchainSupport) {
    check(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical, surface, &support.capabilities))

    {
        count: u32
        check(vk.GetPhysicalDeviceSurfaceFormatsKHR(physical, surface, &count, nil))
        support.formats = make([]vk.SurfaceFormatKHR, count, g_ctx.temp_allocator)
        check(vk.GetPhysicalDeviceSurfaceFormatsKHR(physical, surface, &count, raw_data(support.formats)))
    }
    {
        count: u32
        check(vk.GetPhysicalDeviceSurfacePresentModesKHR(physical, surface, &count, nil))
        support.present_modes = make([]vk.PresentModeKHR, count, g_ctx.temp_allocator)
        check(vk.GetPhysicalDeviceSurfacePresentModesKHR(physical, surface, &count, raw_data(support.present_modes)))
    }

    return
}


choose_swapchain_surface_format :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	for format in formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}

	return formats[0]
}

choose_swapchain_present_mode :: proc(modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	for mode in modes {
		if mode == .MAILBOX {
			return .MAILBOX
		}
	}

	return .FIFO
}

choose_swapchain_extent :: proc(win: glfw.WindowHandle, capabilities: vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	width, height := glfw.GetFramebufferSize(win)
	return(
		vk.Extent2D {
			width = clamp(u32(width), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
			height = clamp(u32(height), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
		}
	)
}


vk_create_swapchain :: proc(
    win: glfw.WindowHandle, 
    device: vk.Device,
    physical: vk.PhysicalDevice,
    surface: vk.SurfaceKHR, 
    swapchain: ^vk.SwapchainKHR
) -> (
     format: vk.SurfaceFormatKHR, 
     extent: vk.Extent2D,
     images: []vk.Image,
     image_views: []vk.ImageView
) {
    family_index := vk_find_queue_family(physical, surface)

    support := vk_query_swapchain_support(physical, surface)

    format = choose_swapchain_surface_format(support.formats)
    present_mode := choose_swapchain_present_mode(support.present_modes)
    extent = choose_swapchain_extent(win, support.capabilities)

    image_count := support.capabilities.minImageCount + 1
    if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
        image_count = support.capabilities.maxImageCount
    }

    create_info := vk.SwapchainCreateInfoKHR { sType = .SWAPCHAIN_CREATE_INFO_KHR,
        surface = surface,
        minImageCount = image_count,
        imageFormat = format.format,
        imageColorSpace = format.colorSpace,
        imageExtent = extent,
        imageArrayLayers = 1,
        imageUsage = {.COLOR_ATTACHMENT},
        preTransform = support.capabilities.currentTransform,
        compositeAlpha = {.OPAQUE},
        presentMode = present_mode,
        clipped = true,
    }

    check(vk.CreateSwapchainKHR(device, &create_info, nil, swapchain))

    count: u32
    check(vk.GetSwapchainImagesKHR(device, swapchain^, &count, nil))

    images = make([]vk.Image, count)
    image_views = make([]vk.ImageView, count)

    check(vk.GetSwapchainImagesKHR(device, swapchain^, &count, raw_data(images)))

    for image, i in images {
        view_create_info := vk.ImageViewCreateInfo { sType = .IMAGE_VIEW_CREATE_INFO,
            image = image,
            viewType = .D2,
            format = format.format,
            subresourceRange = { aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
        }
        check(vk.CreateImageView(device, &view_create_info, nil, &image_views[i]))
    }

    return
}

vk_destroy_swapchain :: proc(
    device: vk.Device, 
    swapchain: vk.SwapchainKHR, 
    images: []vk.Image, 
    image_views: []vk.ImageView) 
{
    for view in image_views {
        vk.DestroyImageView(device, view, nil)
    }

    delete(images)
    delete(image_views)
    vk.DestroySwapchainKHR(device, swapchain, nil)
}

vk_recreate_swapchain :: proc(
    win: glfw.WindowHandle, 
    device: vk.Device, 
    physical: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    swapchain: ^vk.SwapchainKHR,
    images: ^[]vk.Image,
    image_views: ^[]vk.ImageView
) -> (
     format: vk.SurfaceFormatKHR, 
     extent: vk.Extent2D,
     imgs: []vk.Image,
     img_views: []vk.ImageView
) {
    for w, h := glfw.GetFramebufferSize(win); w == 0 || h == 0; w, h = glfw.GetFramebufferSize(win) {
        glfw.WaitEvents()
        if glfw.WindowShouldClose(win) { break }
    }

    vk.DeviceWaitIdle(device)
    vk_destroy_swapchain(device, swapchain^, images^, image_views^)
    vk_create_swapchain(win, device, physical, surface, swapchain)
    return
}

vk_create_shader_module :: proc(device: vk.Device, code: []byte) -> (module: vk.ShaderModule) {
    as_u32 := slice.reinterpret([]u32, code)

    create_info := vk.ShaderModuleCreateInfo { sType = .SHADER_MODULE_CREATE_INFO,
        codeSize    = len(code),
        pCode       = raw_data(as_u32),
    }

    check(vk.CreateShaderModule(device, &create_info, nil, &module))
    return
}

find_memory_type :: proc(physical: vk.PhysicalDevice, filter: u32, props: vk.MemoryPropertyFlags) -> u32 {
    mem_props: vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(physical, &mem_props)

    for i in 0 ..< mem_props.memoryTypeCount {
        if (filter & (1 << i)) != 0 && (mem_props.memoryTypes[i].propertyFlags & props == props) {
            return i
        }
    }

    assert(false, "vulkan: error no memory type found")
    return 0
}

vk_create_buffer :: proc(
    device: vk.Device,
    physical: vk.PhysicalDevice,
    size: vk.DeviceSize, 
    usage: vk.BufferUsageFlags, 
    props: vk.MemoryPropertyFlags, 
    buffer: ^vk.Buffer, 
    buffer_mem: ^vk.DeviceMemory)
{
    create_info := vk.BufferCreateInfo { sType = .BUFFER_CREATE_INFO,
        size = size,
        usage = usage,
        sharingMode = .EXCLUSIVE,
    }

    check(vk.CreateBuffer(device, &create_info, nil, buffer))

    mem_reqs: vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(device, buffer^, &mem_reqs)

    alloc_info := vk.MemoryAllocateInfo { sType = .MEMORY_ALLOCATE_INFO,
        allocationSize = mem_reqs.size,
        memoryTypeIndex = find_memory_type(physical, mem_reqs.memoryTypeBits, props),
    }
    check(vk.AllocateMemory(device, &alloc_info, nil, buffer_mem))
    vk.BindBufferMemory(device, buffer^, buffer_mem^, 0)
}

vk_copy_buffer :: proc(
    device: vk.Device, 
    pool: vk.CommandPool, 
    queue: vk.Queue,
    src: vk.Buffer, 
    dst: vk.Buffer, 
    size: vk.DeviceSize) 
{
    cmd_buf := vk_begin_single_time_commands(device, pool)

    copy_region := vk.BufferCopy {size = size}
    vk.CmdCopyBuffer(cmd_buf, src, dst, 1, &copy_region)

    vk_end_single_time_commands(device, pool, queue, cmd_buf)
}

vk_create_vertex_buffer :: proc(
    device: vk.Device, 
    physical: vk.PhysicalDevice, 
    pool: vk.CommandPool,
    queue: vk.Queue,
    vertices: []Vertex,
    vertex_buffer: ^vk.Buffer,
    vertex_buffer_mem: ^vk.DeviceMemory) 
{
    size := size_of(Vertex) * vk.DeviceSize(len(vertices))
    staging_buf: vk.Buffer
    staging_buf_mem: vk.DeviceMemory
    vk_create_buffer(device, physical, size, {.TRANSFER_SRC},  {.HOST_VISIBLE, .HOST_COHERENT}, &staging_buf, &staging_buf_mem)

    data: rawptr
    vk.MapMemory(device, staging_buf_mem, 0, size, {}, &data)
    mem.copy(data, raw_data(vertices), int(size))
    vk.UnmapMemory(device, staging_buf_mem)

    vk_create_buffer(device, physical, size, {.TRANSFER_DST, .VERTEX_BUFFER}, {.DEVICE_LOCAL}, vertex_buffer, vertex_buffer_mem)
    vk_copy_buffer(device, pool, queue, staging_buf, vertex_buffer^, size)

    vk.DestroyBuffer(device, staging_buf, nil)
    vk.FreeMemory(device, staging_buf_mem, nil)
}

vk_create_index_buffer :: proc(
    device: vk.Device, 
    physical: vk.PhysicalDevice, 
    pool: vk.CommandPool,
    queue: vk.Queue,
    indices: []u16,
    index_buffer: ^vk.Buffer,
    index_buffer_mem: ^vk.DeviceMemory) 
{
    size := size_of(indices[0]) * vk.DeviceSize(len(indices))
    staging_buf: vk.Buffer
    staging_buf_mem: vk.DeviceMemory
    vk_create_buffer(device, physical, size, {.TRANSFER_SRC},  {.HOST_VISIBLE, .HOST_COHERENT}, &staging_buf, &staging_buf_mem)

    data: rawptr
    vk.MapMemory(device, staging_buf_mem, 0, size, {}, &data)
    mem.copy(data, raw_data(indices), int(size))
    vk.UnmapMemory(device, staging_buf_mem)

    vk_create_buffer(device, physical, size, {.TRANSFER_DST, .INDEX_BUFFER}, {.DEVICE_LOCAL}, index_buffer, index_buffer_mem)
    vk_copy_buffer(device, pool, queue, staging_buf, index_buffer^, size)

    vk.DestroyBuffer(device, staging_buf, nil)
    vk.FreeMemory(device, staging_buf_mem, nil)
}

vk_create_uniform_buffers :: proc(
    device: vk.Device,
    physical: vk.PhysicalDevice,
    cubes: ^CubeData,
    cube_range: ^vk.DeviceSize,
) -> (
    camera_buffers: [MAX_FRAMES_BETWEEN]vk.Buffer,
    camera_buffer_mems: [MAX_FRAMES_BETWEEN]vk.DeviceMemory,
    camera_buffer_maps: [MAX_FRAMES_BETWEEN]rawptr,

    cube_buffers: [MAX_FRAMES_BETWEEN]vk.Buffer,
    cube_buffer_mems: [MAX_FRAMES_BETWEEN]vk.DeviceMemory,
    cube_buffer_maps: [MAX_FRAMES_BETWEEN]rawptr,
) {
    props: vk.PhysicalDeviceProperties
    vk.GetPhysicalDeviceProperties(physical, &props)

    min_ubo_align := props.limits.minUniformBufferOffsetAlignment
    dynamic_align := vk.DeviceSize(size_of(matrix[4,4]f32))
    log.info(min_ubo_align)
    if min_ubo_align > 0 {
        dynamic_align = (dynamic_align + min_ubo_align - 1) & ~(min_ubo_align - 1)
    }
    cube_range^ = vk.DeviceSize(dynamic_align)

    buffer_size := vk.DeviceSize(CUBES * dynamic_align)
    models, err := mem.make_aligned([]matrix[4,4]f32, CUBES, int(dynamic_align))
    assert(err == .None, "Error: failed to allocate")

    cubes.models = models
    size := vk.DeviceSize(size_of(Camera))

    for i in 0 ..< MAX_FRAMES_BETWEEN {
        vk_create_buffer(
            device, 
            physical, 
            size, 
            {.UNIFORM_BUFFER}, 
            {.HOST_VISIBLE, .HOST_COHERENT}, 
            &camera_buffers[i], 
            &camera_buffer_mems[i])
        check(vk.MapMemory(device, camera_buffer_mems[i], 0, size, {}, &camera_buffer_maps[i]))

        vk_create_buffer(
            device, 
            physical, 
            buffer_size, 
            {.UNIFORM_BUFFER}, 
            {.HOST_VISIBLE, .HOST_COHERENT}, 
            &cube_buffers[i],
            &cube_buffer_mems[i],
            )
        check(vk.MapMemory(device, cube_buffer_mems[i], 0, buffer_size, {}, &cube_buffer_maps[i]))
    }

    return
}

vk_create_graphics_pipeline :: proc(
    device: vk.Device, 
    format: vk.SurfaceFormatKHR,
    extent: vk.Extent2D,
    set_layout: ^vk.DescriptorSetLayout,
    pipeline: ^vk.Pipeline, 
    pipeline_layout: ^vk.PipelineLayout) 
{
    vert_shader_module := vk_create_shader_module(device, VERT_SHADER)
    frag_shader_module := vk_create_shader_module(device, FRAG_SHADER)
    defer vk.DestroyShaderModule(device, vert_shader_module, nil)
    defer vk.DestroyShaderModule(device, frag_shader_module, nil)

    shader_stages := [2]vk.PipelineShaderStageCreateInfo{
        { sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
            stage = {.VERTEX},
            module = vert_shader_module,
            pName = "main",
        },
        { sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
            stage = {.FRAGMENT},
            module = frag_shader_module,
            pName = "main",
        },
    }

    dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
        sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount = u32(len(dynamic_states)),
        pDynamicStates    = raw_data(dynamic_states),
    }

    binding_desc := vk.VertexInputBindingDescription {
        binding = 0,
        stride = size_of(Vertex),
        inputRate = .VERTEX,
    }
    attribute_desc := vk.VertexInputAttributeDescription {
        binding = 0,
        location = 0,
        format = .R32G32B32_SFLOAT,
        offset = 0,
    }

    vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount = 1,
        pVertexBindingDescriptions    = &binding_desc,
        vertexAttributeDescriptionCount = 1,
        pVertexAttributeDescriptions  = &attribute_desc,
    }

    input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
        sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
    }

    viewport := vk.Viewport {
        x = 0.0,
        y = 0.0,
        width = f32(extent.width),
        height = f32(extent.height),
        minDepth = 0.0,
        maxDepth = 1.0,
    }
    scissor := vk.Rect2D {
        offset = { 0, 0 },
        extent = extent,
    }

    viewport_state := vk.PipelineViewportStateCreateInfo {
        sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        pViewports = &viewport,
        scissorCount  = 1,
        pScissors = &scissor,
    }

    rasterizer := vk.PipelineRasterizationStateCreateInfo {
        sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        polygonMode = .FILL,
        lineWidth   = 1.0,
        cullMode    = {.BACK},
        frontFace   = .CLOCKWISE,
    }

    multisampling := vk.PipelineMultisampleStateCreateInfo {
        sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        rasterizationSamples = {._1},
        minSampleShading     = 1,
    }

    color_blend_attachment := vk.PipelineColorBlendAttachmentState {
        colorWriteMask = {.R, .G, .B, .A},
    }

    color_blending := vk.PipelineColorBlendStateCreateInfo {
        sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        attachmentCount = 1,
        pAttachments    = &color_blend_attachment,
    }

    pipeline_layout_info := vk.PipelineLayoutCreateInfo { sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = 1,
        pSetLayouts    = set_layout,
    }
    check(vk.CreatePipelineLayout(device, &pipeline_layout_info, nil, pipeline_layout))

    surface_format := format.format
    pipeline_rendering_info := vk.PipelineRenderingCreateInfoKHR { sType = .PIPELINE_RENDERING_CREATE_INFO_KHR,
        colorAttachmentCount = 1,
        pColorAttachmentFormats = &surface_format,
    }

    create_info := vk.GraphicsPipelineCreateInfo {
        sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
        pNext               = &pipeline_rendering_info,
        stageCount          = 2,
        pStages             = &shader_stages[0],
        pVertexInputState   = &vertex_input_info,
        pInputAssemblyState = &input_assembly,
        pViewportState      = &viewport_state,
        pRasterizationState = &rasterizer,
        pMultisampleState   = &multisampling,
        pColorBlendState    = &color_blending,
        pDynamicState       = &dynamic_state,
        layout              = pipeline_layout^,
    }
    check(vk.CreateGraphicsPipelines(device, 0, 1, &create_info, nil, pipeline))
}

vk_create_command_structures :: proc(
    device: vk.Device, 
    family_index: u32, 
    pool: ^vk.CommandPool, 
    buffers: ^vk.CommandBuffer) 
{
    pool_info := vk.CommandPoolCreateInfo { sType = .COMMAND_POOL_CREATE_INFO,
        flags = {.RESET_COMMAND_BUFFER},
        queueFamilyIndex = family_index,
    }

    check(vk.CreateCommandPool(device, &pool_info, nil, pool))

    alloc_info := vk.CommandBufferAllocateInfo { sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool = pool^,
        level = .PRIMARY,
        commandBufferCount = MAX_FRAMES_BETWEEN,
    }
    check(vk.AllocateCommandBuffers(device, &alloc_info, buffers))
}

vk_create_descriptor_set_layout :: proc(device: vk.Device, layout: ^vk.DescriptorSetLayout) {
    uniform_buffer_binding := vk.DescriptorSetLayoutBinding {
        binding = UNIFORM_BUFFER_BINDING,
        descriptorType = .UNIFORM_BUFFER,
        descriptorCount = 1,
        stageFlags = {.VERTEX},
    }

    dynamic_uniform_buffer_binding := vk.DescriptorSetLayoutBinding {
        binding = UNIFORM_BUFFER_DYNAMIC_BINDING,
        descriptorType = .UNIFORM_BUFFER_DYNAMIC,
        descriptorCount = 1,
        stageFlags = {.VERTEX},
    }

    bindings := []vk.DescriptorSetLayoutBinding{
        uniform_buffer_binding,
        dynamic_uniform_buffer_binding,
    }

    create_info := vk.DescriptorSetLayoutCreateInfo { sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        bindingCount = u32(len(bindings)),
        pBindings    = raw_data(bindings),
    }

    check(vk.CreateDescriptorSetLayout(device, &create_info, nil, layout))
}

vk_create_descriptor_pool :: proc(device: vk.Device, pool: ^vk.DescriptorPool) {
    pool_sizes := []vk.DescriptorPoolSize {
        {
            type = .UNIFORM_BUFFER,
            descriptorCount = MAX_FRAMES_BETWEEN,
        },
        {
            type = .UNIFORM_BUFFER_DYNAMIC,
            descriptorCount = MAX_FRAMES_BETWEEN,
        }
    }

    create_info := vk.DescriptorPoolCreateInfo { sType = .DESCRIPTOR_POOL_CREATE_INFO,
        maxSets = MAX_FRAMES_BETWEEN,
        poolSizeCount = u32(len(pool_sizes)),
        pPoolSizes    = raw_data(pool_sizes),
    }

    check(vk.CreateDescriptorPool(device, &create_info, nil, pool))
}

vk_create_descriptor_sets :: proc(
    device: vk.Device, 
    cube_range: vk.DeviceSize,
    cube_buffers: [MAX_FRAMES_BETWEEN]vk.Buffer,
    camera_buffers: [MAX_FRAMES_BETWEEN]vk.Buffer,
    pool: vk.DescriptorPool,
    set_layout: vk.DescriptorSetLayout
) -> (
    sets: [MAX_FRAMES_BETWEEN]vk.DescriptorSet
) {
    layouts: [MAX_FRAMES_BETWEEN]vk.DescriptorSetLayout
    for &layout in layouts {
        layout = set_layout
    }

    alloc_info := vk.DescriptorSetAllocateInfo { sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool = pool,
        descriptorSetCount = MAX_FRAMES_BETWEEN,
        pSetLayouts = raw_data(&layouts),
    }
    check(vk.AllocateDescriptorSets(device, &alloc_info, raw_data(&sets)))

    write_descs: [2 * MAX_FRAMES_BETWEEN]vk.WriteDescriptorSet

    for i in 0 ..< MAX_FRAMES_BETWEEN {
        buffer_info := vk.DescriptorBufferInfo {
            buffer = camera_buffers[i],
            offset = 0,
            range = size_of(Camera),
        }
        dynamic_buffer_info := vk.DescriptorBufferInfo {
            buffer = cube_buffers[i],
            offset = 0,
            range = cube_range,
        }

        write_descs[i * 2] = vk.WriteDescriptorSet { sType = .WRITE_DESCRIPTOR_SET,
            dstSet = sets[i],
            dstBinding = 0,
            dstArrayElement = 0,
            descriptorType = .UNIFORM_BUFFER,
            descriptorCount = 1,
            pBufferInfo = &buffer_info,
        }
        write_descs[i * 2 + 1] = vk.WriteDescriptorSet { sType = .WRITE_DESCRIPTOR_SET,
            dstSet = sets[i],
            dstBinding = 0,
            dstArrayElement = 0,
            descriptorType = .UNIFORM_BUFFER,
            descriptorCount = 1,
            pBufferInfo = &buffer_info,
        }
    }

    vk.UpdateDescriptorSets(device, len(write_descs), raw_data(&write_descs), 0, nil)
    return
}

vk_create_sync_structures :: proc(
    device: vk.Device, 
    image_avail: ^[MAX_FRAMES_BETWEEN]vk.Semaphore, 
    render_done: ^[MAX_FRAMES_BETWEEN]vk.Semaphore,
    fences: ^[MAX_FRAMES_BETWEEN]vk.Fence) 
{
    sema_info := vk.SemaphoreCreateInfo { sType = .SEMAPHORE_CREATE_INFO }
    fence_info := vk.FenceCreateInfo { sType = .FENCE_CREATE_INFO,
        flags = {.SIGNALED},
    }

    for i in 0 ..< MAX_FRAMES_BETWEEN {
        check(vk.CreateSemaphore(device, &sema_info, nil, &image_avail[i]))
        check(vk.CreateSemaphore(device, &sema_info, nil, &render_done[i]))
        check(vk.CreateFence(device, &fence_info, nil, &fences[i]))
    }
}

vk_begin_single_time_commands :: proc(device: vk.Device, pool: vk.CommandPool) -> vk.CommandBuffer {
    alloc_info := vk.CommandBufferAllocateInfo { sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        level = .PRIMARY,
        commandPool = pool,
        commandBufferCount = 1,
    }

    cmd_buf: vk.CommandBuffer
    vk.AllocateCommandBuffers(device, &alloc_info, &cmd_buf)

    begin_info := vk.CommandBufferBeginInfo { sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT}
    }

    vk.BeginCommandBuffer(cmd_buf, &begin_info)
    return cmd_buf
}

vk_end_single_time_commands :: proc(
    device: vk.Device, 
    pool: vk.CommandPool, 
    queue: vk.Queue, 
    cmd_buf: vk.CommandBuffer)
{
    buffer := cmd_buf
    vk.EndCommandBuffer(buffer)

    submit_info := vk.SubmitInfo{ sType = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = &buffer,
    }

    vk.QueueSubmit(queue, 1, &submit_info, {})
    vk.QueueWaitIdle(queue)
    vk.FreeCommandBuffers(device, pool, 1, &buffer)
}

vk_record_command_buffer :: proc(
    buffer: vk.CommandBuffer, 
    image: u32,
    frame: u32,
    dynamic_align: [^]u32,
    extent: vk.Extent2D,
    images: []vk.Image,
    image_views: []vk.ImageView,
    descriptor_sets: [MAX_FRAMES_BETWEEN]vk.DescriptorSet,
    index_cnt: u32,
    vertex_buf: vk.Buffer,
    index_buf: vk.Buffer,
    pipeline: vk.Pipeline,
    pipeline_layout: vk.PipelineLayout) 
{
    begin_info := vk.CommandBufferBeginInfo { sType = .COMMAND_BUFFER_BEGIN_INFO }
    check(vk.BeginCommandBuffer(buffer, &begin_info))

    image_to_draw_barrier := vk.ImageMemoryBarrier { sType = .IMAGE_MEMORY_BARRIER,
        dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
        oldLayout = .UNDEFINED,
        newLayout = .COLOR_ATTACHMENT_OPTIMAL,
        image = images[image],
        subresourceRange = { aspectMask =  {.COLOR}, levelCount = 1, layerCount = 1, },
    }
    vk.CmdPipelineBarrier(buffer, {.TOP_OF_PIPE}, {.COLOR_ATTACHMENT_OUTPUT}, {}, 0, nil, 0, nil, 1, &image_to_draw_barrier)

    gray : f32 = 0.008
    clear_color := vk.ClearValue{}
    clear_color.color.float32 = { gray, gray, gray, 1.0 }

    color_attachment_info := vk.RenderingAttachmentInfoKHR { sType = .RENDERING_ATTACHMENT_INFO_KHR,
        imageView = image_views[image],
        imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
        loadOp = .CLEAR,
        storeOp = .STORE,
        clearValue = clear_color,
    }

    rendering_info := vk.RenderingInfoKHR { sType = .RENDERING_INFO_KHR,
        renderArea = {
            offset = { 0, 0 },
            extent = extent,
        },
        layerCount = 1,
        colorAttachmentCount = 1,
        pColorAttachments = &color_attachment_info,
    }

    vk.CmdBeginRenderingKHR(buffer, &rendering_info)
    vk.CmdBindPipeline(buffer, .GRAPHICS, pipeline)

    viewport := vk.Viewport {
        x = 0.0,
        y = 0.0,
        width = f32(extent.width),
        height = f32(extent.height),
        minDepth = 0.0,
        maxDepth = 1.0,
    }
    scissor := vk.Rect2D {
        offset = { 0, 0 },
        extent = extent,
    }

    vk.CmdSetViewport(buffer, 0, 1, &viewport)
    vk.CmdSetScissor(buffer, 0, 1, &scissor)

    set := descriptor_sets[frame]
    vk.CmdBindDescriptorSets(buffer, .GRAPHICS, pipeline_layout, 0, 1, &set, 1, dynamic_align)

    vertex_buffers := []vk.Buffer{vertex_buf}
    offsets := []vk.DeviceSize{0}
    vk.CmdBindVertexBuffers(buffer, 0, 1, raw_data(vertex_buffers), raw_data(offsets))
    vk.CmdBindIndexBuffer(buffer, index_buf, 0, .UINT16)

    vk.CmdDrawIndexed(buffer, index_cnt, 1, 0, 0, 0)
    vk.CmdEndRenderingKHR(buffer)
    
    image_memory_barrier := vk.ImageMemoryBarrier{ sType = .IMAGE_MEMORY_BARRIER,
        srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
        oldLayout = .COLOR_ATTACHMENT_OPTIMAL,
        newLayout = .PRESENT_SRC_KHR,
        image = images[image],
        subresourceRange = { aspectMask = {.COLOR}, levelCount = 1, layerCount = 1, },
    }
    vk.CmdPipelineBarrier(buffer, {.COLOR_ATTACHMENT_OUTPUT}, {.BOTTOM_OF_PIPE}, {}, 0, nil, 0, nil, 1, &image_memory_barrier)

    check(vk.EndCommandBuffer(buffer))
}

main :: proc() {
    context.logger = log.create_console_logger()
    g_ctx = context

    if !glfw.Init() { log.panic("glfw: could not be initialized") }
    defer glfw.Terminate()

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)

    win := glfw.CreateWindow(640, 480, "vorc", nil, nil)
    defer glfw.DestroyWindow(win)

    instance: vk.Instance
    dbg_messenger: vk.DebugUtilsMessengerEXT

    surface: vk.SurfaceKHR
    physical: vk.PhysicalDevice
    device: vk.Device
    swapchain: vk.SwapchainKHR
    format: vk.SurfaceFormatKHR
    extent: vk.Extent2D
    images: []vk.Image
    image_views: []vk.ImageView
    descriptor_pool: vk.DescriptorPool
    descriptor_set_layout: vk.DescriptorSetLayout
    pipeline: vk.Pipeline
    pipeline_layout: vk.PipelineLayout
    command_pool: vk.CommandPool
    command_buffers: [MAX_FRAMES_BETWEEN]vk.CommandBuffer
    vertex_buffer: vk.Buffer
    index_buffer : vk.Buffer
    vertex_buffer_mem: vk.DeviceMemory
    index_buffer_mem : vk.DeviceMemory
    image_avail: [MAX_FRAMES_BETWEEN]vk.Semaphore
    render_done: [MAX_FRAMES_BETWEEN]vk.Semaphore
    fences:      [MAX_FRAMES_BETWEEN]vk.Fence

    vertices := []Vertex{
        {{-0.5, -0.5, 0.0}},
        {{0.5,  -0.5, 0.0}},
        {{0.5,  0.5 , 0.0}},
        {{-0.5, 0.5 , 0.0}}
    }
    indices := []u16{0, 1, 2, 2, 3, 0}

    cubes: CubeData
    cube_range: vk.DeviceSize

    vk_create_instance(&instance, &dbg_messenger)
    check(glfw.CreateWindowSurface(instance, win, nil, &surface))
    family_index, queue := vk_create_device(instance, surface, &physical, &device)
    format, extent, images, image_views = vk_create_swapchain(win, device, physical, surface, &swapchain)
    vk_create_descriptor_set_layout(device, &descriptor_set_layout)
    vk_create_graphics_pipeline(device, format, extent, &descriptor_set_layout, &pipeline, &pipeline_layout)
    vk_create_command_structures(device, family_index, &command_pool, &command_buffers[0])
    vk_create_vertex_buffer(device, physical, command_pool, queue, vertices, &vertex_buffer, &vertex_buffer_mem)
    vk_create_index_buffer(device, physical, command_pool, queue, indices, &index_buffer, &index_buffer_mem)
    camera_bufs, camera_buf_mems, camera_buf_maps, cube_bufs, cube_buf_mems, cube_buf_maps := vk_create_uniform_buffers(
        device,
        physical,
        &cubes,
        &cube_range)
    vk_create_descriptor_pool(device, &descriptor_pool)
    sets := vk_create_descriptor_sets(device, cube_range, cube_bufs, camera_bufs, descriptor_pool, descriptor_set_layout)
    vk_create_sync_structures(device, &image_avail, &render_done, &fences)

    frame := u32(0)

    for !glfw.WindowShouldClose(win) {
        glfw.PollEvents()

        check(vk.WaitForFences(device, 1, &fences[frame], true, max(u64)))
        check(vk.ResetFences(device, 1, &fences[frame]))

        image_index: u32 = 0
        acquire_result := vk.AcquireNextImageKHR(device, swapchain, max(u64), image_avail[frame], 0, &image_index)

        #partial switch acquire_result {
        case .ERROR_OUT_OF_DATE_KHR:
            format, extent, images, image_views = vk_recreate_swapchain(
                win, device, physical, surface, &swapchain, &images, &image_views
            )
            continue
        case .SUCCESS, .SUBOPTIMAL_KHR:
        case:
            log.panicf("vulkan: acquire next image failure: %v", acquire_result)
        }

        check(vk.ResetCommandBuffer(command_buffers[frame], {}))
        dynamic_offset := []u32{u32(cube_range)}

        vk_record_command_buffer(
            command_buffers[frame], 
            image_index, 
            frame,
            raw_data(dynamic_offset),
            extent, 
            images, 
            image_views, 
            sets,
            u32(len(indices)),
            vertex_buffer, 
            index_buffer,
            pipeline,
            pipeline_layout)

        submit_info := vk.SubmitInfo { sType = .SUBMIT_INFO,
            waitSemaphoreCount = 1,
            pWaitSemaphores    = &image_avail[frame],
            pWaitDstStageMask  = &vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
            commandBufferCount = 1,
            pCommandBuffers    = &command_buffers[frame],
            signalSemaphoreCount = 1,
            pSignalSemaphores  = &render_done[frame]
        }

        check(vk.QueueSubmit(queue, 1, &submit_info, fences[frame]))

        present_info := vk.PresentInfoKHR { sType = .PRESENT_INFO_KHR,
            waitSemaphoreCount = 1,
            pWaitSemaphores = &render_done[frame],
            swapchainCount = 1,
            pSwapchains = &swapchain,
            pImageIndices = &image_index,
        }

        present_result := vk.QueuePresentKHR(queue, &present_info)
        switch {
        case present_result == .ERROR_OUT_OF_DATE_KHR || present_result == .SUBOPTIMAL_KHR:
            format, extent, images, image_views = vk_recreate_swapchain(
                win, device, physical, surface, &swapchain, &images, &image_views
            )
        case present_result == .SUCCESS:
        case:
            log.panicf("vulkan: present failure: %v", present_result)
        }

        check(vk.QueueWaitIdle(queue))
        frame = (frame + 1) % MAX_FRAMES_BETWEEN
    }

    vk.DeviceWaitIdle(device)
    for sem in image_avail { vk.DestroySemaphore(device, sem, nil) }
    for sem in render_done { vk.DestroySemaphore(device, sem, nil) }
    for fence in fences    { vk.DestroyFence(device, fence, nil  ) }

    vk.DestroyDescriptorPool(device, descriptor_pool, nil)
    vk.DestroyBuffer(device, vertex_buffer, nil)
    vk.FreeMemory(device, vertex_buffer_mem, nil)
    vk.DestroyBuffer(device, index_buffer, nil)
    vk.FreeMemory(device, index_buffer_mem, nil)
    vk.DestroyCommandPool(device, command_pool, nil)
    vk.DestroyPipeline(device, pipeline, nil)
    vk.DestroyPipelineLayout(device, pipeline_layout, nil)
    vk_destroy_swapchain(device, swapchain, images, image_views)
    vk.DestroyDevice(device, nil)
    vk.DestroyDebugUtilsMessengerEXT(instance, dbg_messenger, nil)
    vk.DestroySurfaceKHR(instance, surface, nil)
    vk.DestroyInstance(instance, nil)
}

