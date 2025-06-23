cmake_minimum_required(VERSION 4.0 FATAL_ERROR)

project(ren LANGUAGES C)

file(GLOB_RECURSE GLSL_SOURCE_FILES "src/shaders/*.glsl")
file(GLOB_RECURSE C_SOURCE_FILES    "src/*.h" "src/*.c")

add_executable(ren
    ${C_SOURCE_FILES}
    ${GLSL_SOURCE_FILES})

add_subdirectory(extern/volk)
add_subdirectory(extern/glfw)

target_link_libraries(ren
    PRIVATE
        glfw
        volk)

set(GLSL_VALIDATOR "glslangValidator")
set(GLSL_FLAGS --target-env vulkan1.3)
set(SPIRV_OUTPUT_DIR "${PROJECT_BINARY_DIR}/spirv/")

foreach(GLSL ${GLSL_SOURCE_FILES})
    get_filename_component(STEM ${GLSL} NAME_WLE)
    set(SPIRV "${SPIRV_OUTPUT_DIR}${STEM}.spv")
    add_custom_command(
        OUTPUT ${SPIRV}
        COMMAND ${CMAKE_COMMAND} -E make_directory "${SPIRV_OUTPUT_DIR}"
        COMMAND ${GLSL_VALIDATOR} -V ${GLSL_FLAGS} --quiet ${GLSL} -o ${SPIRV}
        DEPENDS ${GLSL})
    list(APPEND SPIRV_BINARY_FILES ${SPIRV})
endforeach()

add_custom_target(compile_shaders DEPENDS ${SPIRV_BINARY_FILES})
add_dependencies(ren compile_shaders)
