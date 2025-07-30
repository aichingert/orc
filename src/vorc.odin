package main

import "base:runtime"

import "core:log"
import "core:slice"

import "vendor:glfw"
import vk "vendor:vulkan"

g_ctx: runtime.Context

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

main :: proc() {
    context.logger = log.create_console_logger()
    g_ctx = context

    if !glfw.Init() { log.panic("glfw: could not be initialized") }
    defer glfw.Terminate()

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)

    win := glfw.CreateWindow(640, 480, "vorc", nil, nil)
    defer glfw.DestroyWindow(win)

    vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
    assert(vk.CreateInstance != nil, "vulkan function pointers not loaded")

    extensions := slice.clone_to_dynamic(glfw.GetRequiredInstanceExtensions(), context.temp_allocator)
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

    instance: vk.Instance
    check(vk.CreateInstance(&create_info, nil, &instance))
    defer vk.DestroyInstance(instance, nil)

    vk.load_proc_addresses_instance(instance)

    dbg_messenger: vk.DebugUtilsMessengerEXT
    check(vk.CreateDebugUtilsMessengerEXT(instance, &dbg_create_info, nil, &dbg_messenger))
    defer vk.DestroyDebugUtilsMessengerEXT(instance, dbg_messenger, nil)

    surface: vk.SurfaceKHR
    check(glfw.CreateWindowSurface(instance, win, nil, &surface))
    defer vk.DestroySurfaceKHR(instance, surface, nil)

    for !glfw.WindowShouldClose(win) {
        free_all(context.temp_allocator)

        glfw.PollEvents()
    }
}



