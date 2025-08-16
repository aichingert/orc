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

UNIT                :: 1.5
SIZE                :: 3
CUBES               :: SIZE * SIZE * SIZE
WINDOW_OFFSET       :: 5

HIGHLIGHTING        :: 0.3
ROTATION_SPEED      :: 0.13

MAX_FRAMES_BETWEEN  :: 2

CUBE                :: []Vertex{
    {{-.5, -.5, -.5},   {196.0 / 255.0, 30 / 255.0, 58. / 255.0}},
    {{-.5, .5, .5},     {196.0 / 255.0, 30 / 255.0, 58. / 255.0}},
    {{-.5, -.5, .5},    {196.0 / 255.0, 30 / 255.0, 58. / 255.0}},
    {{-.5, .5, -.5},    {196.0 / 255.0, 30 / 255.0, 58. / 255.0}},
    {{.5, -.5, -.5},    {0, 158.0 / 255.0, 96.0 / 255.0}},
    {{.5, .5, .5},      {0, 158.0 / 255.0, 96.0 / 255.0}},
    {{.5, -.5, .5},     {0, 158.0 / 255.0, 96.0 / 255.0}},
    {{.5, .5, -.5},     {0, 158.0 / 255.0, 96.0 / 255.0}},
    {{-.5, -.5, -.5},   {0, 81.0 / 255.0, 186.0 / 255.0}},
    {{.5, -.5, .5},     {0, 81.0 / 255.0, 186.0 / 255.0}},
    {{-.5, -.5, .5},    {0, 81.0 / 255.0, 186.0 / 255.0}},
    {{.5, -.5, -.5},    {0, 81.0 / 255.0, 186.0 / 255.0}},
    {{-.5, .5, -.5},    {1, 88.0 / 255.0, 0}},
    {{.5, .5, .5},      {1, 88.0 / 255.0, 0}},
    {{-.5, .5, .5},     {1, 88.0 / 255.0, 0}},
    {{.5, .5, -.5},     {1, 88.0 / 255.0, 0}},
    {{-.5, -.5, 0.5},   {1, 213.0 / 255.0, 0}},
    {{.5, .5, 0.5},     {1, 213.0 / 255.0, 0}},
    {{-.5, .5, 0.5},    {1, 213.0 / 255.0, 0}},
    {{.5, -.5, 0.5},    {1, 213.0 / 255.0, 0}},
    {{-.5, -.5, -0.5},  {1, 1, 1}},
    {{.5, .5, -0.5},    {1, 1, 1}},
    {{-.5, .5, -0.5},   {1, 1, 1}},
    {{.5, -.5, -0.5},   {1, 1, 1}},
}
INDICES             :: []u16{
    0, 1, 2, 0, 3, 1, 4, 5, 6, 4, 7, 5, 8, 9, 10, 8, 11, 9, 12, 13, 
    14, 12, 15, 13, 16, 17, 18, 16, 19, 17, 20, 21, 22, 20, 23, 21,
}

UNIFORM_BUFFER_BINDING          :: 0
UNIFORM_BUFFER_DYNAMIC_BINDING  :: 1

Camera :: struct {
    view: matrix[4,4]f32,
    proj: matrix[4,4]f32,
}

InstanceData :: struct {
    model: matrix[4,4]f32,
    highlight: f32,
    padding: [32]u8, 
}

RubiksCube :: struct {
    cubes: []InstanceData,
}

Vertex :: struct {
    pos: [3]f32,
    col: [3]f32,
}

SelectionData :: struct {
    is_row_selected: bool,
    row: i16,
    col: i16,
}

AnimationData :: struct {
    angles: [3]f32,
    change: [3]f32,
    turn_proc: proc(bool),
}

g_rubiks: ^RubiksCube = nil
g_camera: Camera
g_selection: SelectionData
g_animation: AnimationData
g_animate_turn: bool
g_has_selection: bool

g_cube_buf_maps: [MAX_FRAMES_BETWEEN]rawptr
g_camera_buf_maps: [MAX_FRAMES_BETWEEN]rawptr

g_previous_x_point: f64 = 0
g_previous_y_point: f64 = 0
g_has_previous_point: bool = false

key_pressed :: proc "c" (win: glfw.WindowHandle, key: i32, scancode: i32, action: i32, mods: i32) {
    context = g_ctx

    if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
        g_has_selection = false
    }
    if key == glfw.KEY_LEFT && action & (glfw.REPEAT | glfw.PRESS) != 0 {
        g_has_selection = true
        g_selection.is_row_selected = false
        g_selection.col = (g_selection.col - 1) %% i16(SIZE)
    }
    if key == glfw.KEY_RIGHT && action & (glfw.REPEAT | glfw.PRESS) != 0 {
        g_has_selection = true
        g_selection.is_row_selected = false
        g_selection.col = (g_selection.col + 1) %% i16(SIZE)
    }
    if key == glfw.KEY_UP && action & (glfw.REPEAT | glfw.PRESS) != 0 {
        g_has_selection = true
        g_selection.is_row_selected = true
        g_selection.row = (g_selection.row - 1) %% i16(SIZE)
    }
    if key == glfw.KEY_DOWN && action & (glfw.REPEAT | glfw.PRESS) != 0 {
        g_has_selection = true
        g_selection.is_row_selected = true 
        g_selection.row = (g_selection.row + 1) %% i16(SIZE)
    }

    if g_animate_turn {
        return
    }
    if key == glfw.KEY_D && action & (glfw.REPEAT | glfw.PRESS) != 0 {
        g_animate_turn = true
        g_animation.angles = {0, 0, -90}
        g_animation.change = {0, 0, -01}
        g_animation.turn_proc = rubiks_cube_turn_x
    } 
    if key == glfw.KEY_A && action & (glfw.REPEAT | glfw.PRESS) != 0 {
        g_animate_turn = true
        g_animation.angles = {0, 0, 90}
        g_animation.change = {0, 0, 01}
        g_animation.turn_proc = rubiks_cube_turn_x
    } 
    if key == glfw.KEY_W && action & (glfw.REPEAT | glfw.PRESS) != 0 {
        g_animate_turn = true
        g_animation.angles = {0, 90, 0}
        g_animation.change = {0, 01, 0}
        g_animation.turn_proc = rubiks_cube_turn_y
    } 
    if key == glfw.KEY_S && action & (glfw.REPEAT | glfw.PRESS) != 0 {
        g_animate_turn = true
        g_animation.angles = {0, -90, 0}
        g_animation.change = {0, -01, 0}
        g_animation.turn_proc = rubiks_cube_turn_y
    }
}

scroll_callback :: proc "c" (win: glfw.WindowHandle, xoffset: f64, yoffset: f64) {
    g_camera.view[2, 3] -= f32(yoffset / 10.0)
    mem.copy(g_camera_buf_maps[0], &g_camera, size_of(g_camera))
    mem.copy(g_camera_buf_maps[1], &g_camera, size_of(g_camera))
}

mouse_position :: proc "c" (win: glfw.WindowHandle, xpos: f64, ypos: f64) {
    context = g_ctx

    state := glfw.GetMouseButton(win, glfw.MOUSE_BUTTON_LEFT);

    if g_has_previous_point && state == 1 {
        x_angle := math.to_radians_f32(f32(xpos - g_previous_x_point))
        y_angle := math.to_radians_f32(f32(g_previous_y_point - ypos))

        for i in 0..< SIZE * SIZE * SIZE {
            g_rubiks.cubes[i].model = cube_rotate(x_angle, y_angle, 0) * g_rubiks.cubes[i].model
        }

        mem.copy(g_cube_buf_maps[0], raw_data(g_rubiks.cubes), CUBES * size_of(g_rubiks.cubes[0]))
        mem.copy(g_cube_buf_maps[1], raw_data(g_rubiks.cubes), CUBES * size_of(g_rubiks.cubes[0]))
    }

    g_previous_x_point = xpos
    g_previous_y_point = ypos
    g_has_previous_point = state == 1
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

    glfw.SetKeyCallback(win, key_pressed)
    glfw.SetScrollCallback(win, scroll_callback)
    glfw.SetCursorPosCallback(win, mouse_position)

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

    rubik: RubiksCube 
    cube_range: vk.DeviceSize

    ren_create_instance(&instance, &dbg_messenger)
    check(glfw.CreateWindowSurface(instance, win, nil, &surface))
    family_index, queue := ren_create_device(instance, surface, &physical, &device)
    format, extent, images, image_views = ren_create_swapchain(win, device, physical, surface, &swapchain)
    ren_create_descriptor_set_layout(device, &descriptor_set_layout)
    ren_create_graphics_pipeline(device, physical, format, extent, &descriptor_set_layout, &pipeline, &pipeline_layout)
    ren_create_command_structures(device, family_index, &command_pool, &command_buffers[0])
    ren_create_depth_resources(device, physical, extent, &depth_image, &depth_image_view, &depth_image_mem)
    ren_create_vertex_buffer(device, physical, command_pool, queue, CUBE, &vertex_buffer, &vertex_buffer_mem)
    ren_create_index_buffer(device, physical, command_pool, queue, INDICES, &index_buffer, &index_buffer_mem)
    camera_bufs, camera_buf_mems, camera_buf_maps, cube_bufs, cube_buf_mems, cube_buf_maps := ren_create_uniform_buffers(
        device,
        physical,
        &rubik,
        &cube_range)
    g_cube_buf_maps = cube_buf_maps
    g_camera_buf_maps = camera_buf_maps
    ren_create_descriptor_pool(device, &descriptor_pool)
    sets := ren_create_descriptor_sets(device, cube_range, cube_bufs, camera_bufs, descriptor_pool, descriptor_set_layout)
    ren_create_sync_structures(device, &image_avail, &render_done, &fences)

    frame := u32(0)
    angles: [3]f32 = {0, 0, 0}

    aspect_ratio := f32(extent.width) / f32(extent.height)
    fovy         := math.to_radians_f32(120)
    tan_half     := math.tan_f32(fovy / 2)
    near         := f32(.1)
    far          := f32(10)

    g_camera.view = {
        1, 0, 0, 0, 
        0, 1, 0, 0,
        0, 0, 1, WINDOW_OFFSET,
        0, 0, 0, 1,
    }

    g_camera.proj[0][0] = 1 / (aspect_ratio * tan_half)
    g_camera.proj[1][1] = 1 / (tan_half)
    g_camera.proj[2][2] = far / (far - near)
    g_camera.proj[2][3] = 1
    g_camera.proj[3][2] = -(far * near) / (far - near)

    mem.copy(camera_buf_maps[0], &g_camera, size_of(g_camera))
    mem.copy(camera_buf_maps[1], &g_camera, size_of(g_camera))

    g_rubiks = &rubik
    rubiks_cube_init()

    for !glfw.WindowShouldClose(win) {
        glfw.PollEvents()

        /*
        if g_has_selection {
            for d in 0..< i16(SIZE) {
                side := d * i16(SIZE * SIZE)

                for r in 0..< i16(SIZE) {
                    for c in 0..< i16(SIZE) {
                        if g_selection.is_row_selected && r == g_selection.row {
                            g_rubiks.cubes[d + r * SIZE + c].highlight = HIGHLIGHTING
                        } else if !g_selection.is_row_selected && c == g_selection.col {
                            g_rubiks.cubes[d + r * SIZE + c].highlight = HIGHLIGHTING
                        }
                    }
                }
            }
        }
        mem.copy(g_cube_buf_maps[0], raw_data(g_rubiks.cubes), CUBES / SIZE * size_of(g_rubiks.cubes[0]))
        mem.copy(g_cube_buf_maps[1], raw_data(g_rubiks.cubes), CUBES / SIZE * size_of(g_rubiks.cubes[0]))
        */

        if g_animate_turn {
            animate_cube_turn(&angles)
        }

        image_index, successful := ren_begin_frame(device, swapchain, &fences, &image_avail, &command_buffers, frame)
        if !successful {
            format, extent, images, image_views = ren_recreate_swapchain(
                win, device, physical, surface, &swapchain, &images, &image_views
            )
            continue
        }

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
            u32(len(INDICES)),
            vertex_buffer, 
            index_buffer,
            pipeline,
            pipeline_layout)

        successful = ren_end_frame(device, &swapchain, frame, &image_index, &fences, &image_avail, &render_done, &command_buffers, queue)
        if !successful {
            format, extent, images, image_views = ren_recreate_swapchain(
                win, device, physical, surface, &swapchain, &images, &image_views
            )
        }

        frame = (frame + 1) % MAX_FRAMES_BETWEEN
    }

    vk.DeviceWaitIdle(device)
    for sem in image_avail { vk.DestroySemaphore(device, sem, nil) }
    for sem in render_done { vk.DestroySemaphore(device, sem, nil) }
    for fence in fences    { vk.DestroyFence(device, fence, nil  ) }

    for frame in 0..<MAX_FRAMES_BETWEEN {
        vk.DestroyBuffer(device, camera_bufs[frame], nil)
        vk.FreeMemory(device, camera_buf_mems[frame], nil)

        vk.DestroyBuffer(device, cube_bufs[frame], nil)
        vk.FreeMemory(device, cube_buf_mems[frame], nil)
    }

    vk.DestroyImageView(device, depth_image_view, nil)
    vk.DestroyImage(device, depth_image, nil)
    vk.FreeMemory(device, depth_image_mem, nil)

    vk.DestroyDescriptorPool(device, descriptor_pool, nil)
    vk.DestroyDescriptorSetLayout(device, descriptor_set_layout, nil)

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


