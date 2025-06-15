cmake_minimum_required(VERSION 4.0 FATAL_ERROR)

project(ren LANGUAGES C)

add_executable(ren src/ren.c)

add_subdirectory(extern/volk)
add_subdirectory(extern/glfw)

target_link_libraries(ren
    PRIVATE
        glfw
        volk)

