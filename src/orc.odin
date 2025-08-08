package main

import "base:runtime"

import "core:log"
import "core:mem"
import "core:math"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

g_ctx: runtime.Context

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
    pos: [3]f32,
    col: [3]f32,
}

cube_rotate :: proc(model: matrix[4,4]f32, y: f32, x: f32, z: f32) -> matrix[4,4]f32 {
    // y -> upright y axis ; heading -> yaw
    // x -> object  x axis ; pitch   -> pitch
    // z -> upright z axis ; bank    -> roll

    B := matrix[4,4]f32{
        math.cos_f32(z), math.sin_f32(z), 0, 0,
        -math.sin_f32(z), math.cos_f32(z), 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    }

    P := matrix[4,4]f32{
        1, 0, 0, 0,
        0, math.cos_f32(x), math.sin_f32(x), 0,
        0, -math.sin_f32(x), math.cos_f32(x), 0,
        0, 0, 0, 1,
    }

    H := matrix[4,4]f32{
        math.cos_f32(y), 0, -math.sin_f32(y), 0,
        0, 1, 0, 0,
        math.sin_f32(y), 0, math.cos_f32(y), 0,
        0, 0, 0, 1,
    }

    return model * B * P * H
}

main :: proc() {
    context.logger = log.create_console_logger()
    g_ctx = context

    if !glfw.Init() { log.panic("glfw: could not be initialized") }
    defer glfw.Terminate()

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)

    win := glfw.CreateWindow(640, 480, "orc", nil, nil)
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
    depth_image: vk.Image
    depth_image_view: vk.ImageView
    depth_image_mem: vk.DeviceMemory
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
        // left face (white)
        {{-.5, -.5, -.5}, {.9, .9, .9}},
        {{-.5, .5, .5}, {.9, .9, .9}},
        {{-.5, -.5, .5}, {.9, .9, .9}},
        {{-.5, .5, -.5}, {.9, .9, .9}},

        // right face (yellow)
        {{.5, -.5, -.5}, {.8, .8, .1}},
        {{.5, .5, .5}, {.8, .8, .1}},
        {{.5, -.5, .5}, {.8, .8, .1}},
        {{.5, .5, -.5}, {.8, .8, .1}},

        // top face (orange, remember y axis points down)
        {{-.5, -.5, -.5}, {.9, .6, .1}},
        {{.5, -.5, .5}, {.9, .6, .1}},
        {{-.5, -.5, .5}, {.9, .6, .1}},
        {{.5, -.5, -.5}, {.9, .6, .1}},

        // bottom face (red)
        {{-.5, .5, -.5}, {.8, .1, .1}},
        {{.5, .5, .5}, {.8, .1, .1}},
        {{-.5, .5, .5}, {.8, .1, .1}},
        {{.5, .5, -.5}, {.8, .1, .1}},

        // nose face (blue)
        {{-.5, -.5, 0.5}, {.1, .1, .8}},
        {{.5, .5, 0.5}, {.1, .1, .8}},
        {{-.5, .5, 0.5}, {.1, .1, .8}},
        {{.5, -.5, 0.5}, {.1, .1, .8}},

        // tail face (green)
        {{-.5, -.5, -0.5}, {.1, .8, .1}},
        {{.5, .5, -0.5}, {.1, .8, .1}},
        {{-.5, .5, -0.5}, {.1, .8, .1}},
        {{.5, -.5, -0.5}, {.1, .8, .1}},
    }
    indices := []u16{0, 1, 2, 0, 3, 1, 4, 5, 6, 4, 7, 5, 8, 9, 10, 8, 11, 9, 12, 13, 14, 12, 15, 13, 16, 17, 18, 16, 19, 17, 20, 21, 22, 20, 23, 21}

    cubes: CubeData
    cube_range: vk.DeviceSize

    ren_create_instance(&instance, &dbg_messenger)
    check(glfw.CreateWindowSurface(instance, win, nil, &surface))
    family_index, queue := ren_create_device(instance, surface, &physical, &device)
    format, extent, images, image_views = ren_create_swapchain(win, device, physical, surface, &swapchain)
    ren_create_descriptor_set_layout(device, &descriptor_set_layout)
    ren_create_graphics_pipeline(device, physical, format, extent, &descriptor_set_layout, &pipeline, &pipeline_layout)
    ren_create_command_structures(device, family_index, &command_pool, &command_buffers[0])
    ren_create_depth_resources(device, physical, extent, &depth_image, &depth_image_view, &depth_image_mem)
    ren_create_vertex_buffer(device, physical, command_pool, queue, vertices, &vertex_buffer, &vertex_buffer_mem)
    ren_create_index_buffer(device, physical, command_pool, queue, indices, &index_buffer, &index_buffer_mem)
    camera_bufs, camera_buf_mems, camera_buf_maps, cube_bufs, cube_buf_mems, cube_buf_maps := ren_create_uniform_buffers(
        device,
        physical,
        &cubes,
        &cube_range)
    ren_create_descriptor_pool(device, &descriptor_pool)
    sets := ren_create_descriptor_sets(device, cube_range, cube_bufs, camera_bufs, descriptor_pool, descriptor_set_layout)
    ren_create_sync_structures(device, &image_avail, &render_done, &fences)

    frame := u32(0)
    angle: f32 = 0

    aspect_ratio := f32(extent.width) / f32(extent.height)
    fovy         := math.to_radians_f32(120)
    tan_half     := math.tan_f32(fovy / 2)
    near         := f32(.1)
    far          := f32(10)

    // TODO: read some more from
    // https://www.gamemath.com/book/matrixmore.html#perspective_projection

    camera := matrix[4,4]f32{
        0, 0, 0, 0,
        0, 0, 0, 0,
        0, 0, 0, 0,
        0, 0, 0, 0,
    } 

    camera[0][0] = 1 / (aspect_ratio * tan_half)
    camera[1][1] = 1 / (tan_half)
    camera[2][2] = far / (far - near)
    camera[2][3] = 1
    camera[3][2] = -(far * near) / (far - near)

    mem.copy(camera_buf_maps[0], raw_data(&camera), size_of(camera))
    mem.copy(camera_buf_maps[1], raw_data(&camera), size_of(camera))

    for !glfw.WindowShouldClose(win) {
        glfw.PollEvents()

        check(vk.WaitForFences(device, 1, &fences[frame], true, max(u64)))
        check(vk.ResetFences(device, 1, &fences[frame]))

        image_index: u32 = 0
        acquire_result := vk.AcquireNextImageKHR(device, swapchain, max(u64), image_avail[frame], 0, &image_index)

        #partial switch acquire_result {
        case .ERROR_OUT_OF_DATE_KHR:
            format, extent, images, image_views = ren_recreate_swapchain(
                win, device, physical, surface, &swapchain, &images, &image_views
            )
            continue
        case .SUCCESS, .SUBOPTIMAL_KHR:
        case:
            log.panicf("vulkan: acquire next image failure: %v", acquire_result)
        }

        check(vk.ResetCommandBuffer(command_buffers[frame], {}))

        ren_record_command_buffer(
            command_buffers[frame], 
            family_index,
            frame,
            u32(cube_range),
            extent, 
            images[image_index], 
            image_views[image_index], 
            depth_image,
            depth_image_view,
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
            format, extent, images, image_views = ren_recreate_swapchain(
                win, device, physical, surface, &swapchain, &images, &image_views
            )
        case present_result == .SUCCESS:
        case:
            log.panicf("vulkan: present failure: %v", present_result)
        }

        check(vk.QueueWaitIdle(queue))
        frame = (frame + 1) % MAX_FRAMES_BETWEEN

        if frame == 0 {
            angle += 0.0001

            cubes.models[0] = { 
                .5,0,0,1,
                0,.5,0,0,
                0,0,.5,1.5,
                0,0,0,1,
            }
            cubes.models[0] = cube_rotate(cubes.models[0], angle, angle, 0)

            cubes.models[1] = { 
                .5,0,0,-1,
                0,.5,0,0,
                0,0,.5,1.5,
                0,0,0,1,
            }
            cubes.models[1] = cube_rotate(cubes.models[1], angle, angle, 0)

            models := []matrix[4,4]f32{cubes.models[0], cubes.models[1]}

            mem.copy(cube_buf_maps[0], raw_data(models), len(models) * size_of(cubes.models[0]))
            mem.copy(cube_buf_maps[1], raw_data(models), len(models) * size_of(cubes.models[0]))
        }
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
    ren_destroy_swapchain(device, swapchain, images, image_views)
    vk.DestroyDevice(device, nil)
    vk.DestroyDebugUtilsMessengerEXT(instance, dbg_messenger, nil)
    vk.DestroySurfaceKHR(instance, surface, nil)
    vk.DestroyInstance(instance, nil)
}

