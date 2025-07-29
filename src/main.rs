use std::ffi::CString;

use ash::vk;

use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::window::{Window, WindowAttributes, WindowId};

unsafe extern "system" fn vulkan_debug_utils_callback(
    message_severity: vk::DebugUtilsMessageSeverityFlagsEXT,
    message_type: vk::DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: *const vk::DebugUtilsMessengerCallbackDataEXT,
    _p_user_data: *mut std::ffi::c_void,
) -> vk::Bool32 {
    let message = std::ffi::CStr::from_ptr((*p_callback_data).p_message);
    let severity = format!("{:?}", message_severity).to_lowercase();
    let ty = format!("{:?}", message_type).to_lowercase();
    println!("[Debug][{}][{}] {:?}", severity, ty, message);
    vk::FALSE
}

struct Vrc {
    win: Option<Window>,
}

impl ApplicationHandler for Vrc {
    fn resumed(&mut self, el: &ActiveEventLoop) {
        self.win = Some(el.create_window(Window::default_attributes()).unwrap());
    }

    fn window_event(&mut self, el: &ActiveEventLoop, _: WindowId, ev: WindowEvent) {
        match ev {
            WindowEvent::CloseRequested => { el.exit(); },
            _ => {},
        }
    }

}

fn main() {
    let el = EventLoop::new();
    let mut vrc = Vrc { win: None };

    let app_info = vk::ApplicationInfo::default()
        .application_name(c"vrk")
        .application_version(0)
        .engine_name(c"none")
        .engine_version(0)
        .api_version(vk::make_api_version(0, 1, 4, 0));

    /*
    let create_info = vk::InstanceCreateInfo::default()
        .application_info(&app_info)
        .enabled_layer_names(&[c"VK_LAYER_KHRONOS_validation"].iter().map(|l| l.as_ptr().collect::<Vec<_>>()))
        .enabled_extension_names(&[c"

    dbg!(&create_info);

    let instance = unsafe { 
        let entry = ash::Entry::load().expect("Error: could not load vulkan");
        entry.create_instance(&create_info, None).unwrap()
    };

    unsafe { instance.destroy_instance(None) };
    */
}
