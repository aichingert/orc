#include <assert.h>

#define VOLK_IMPLEMENTATION
#include "volk.h"
#define GLFW_INCLUDE_NONE
#include "GLFW/glfw3.h"

#define VK_CHECK(call) \
	do \
	{ \
		VkResult result_ = call; \
		assert(result_ == VK_SUCCESS); \
	} while (0)


