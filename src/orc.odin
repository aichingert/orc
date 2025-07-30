package main

import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

g_ctx: runtime.Context

VERT_SHADER :: #load("vert.spv")
FRAG_SHADER :: #load("frag.spv")

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
    device: ^vk.Device) 
{
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

    family_index := vk_find_queue_family(physical^, surface)

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

    log.info("CREATING")
    check(vk.CreateDevice(physical^, &create_info, nil, device))
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

    vk_create_instance(&instance, &dbg_messenger)

    defer vk.DestroyDebugUtilsMessengerEXT(instance, dbg_messenger, nil)
    defer vk.DestroyInstance(instance, nil)

    check(glfw.CreateWindowSurface(instance, win, nil, &surface))
    defer vk.DestroySurfaceKHR(instance, surface, nil)

    vk_create_device(instance, surface, &physical, &device)
    defer vk.DestroyDevice(device, nil)

    format, extent, images, image_views = vk_create_swapchain(win, device, physical, surface, &swapchain)
    defer vk_destroy_swapchain(device, swapchain, images, image_views)

    for !glfw.WindowShouldClose(win) {

        glfw.PollEvents()

    }
}



