# Strips debug/unneeded symbols from a target's output file right after it
# is built.
#
# Usage: strip_target(<target_name>)
#
# The stripping mode is chosen automatically based on the target type:
# - STATIC_LIBRARY: "--strip-debug" only. Static libraries still need their
#   full symbol table intact for future linking (whoever links against
#   them later needs to resolve symbols), so we must NOT remove symbols,
#   only debug info.
# - Anything else (SHARED_LIBRARY, EXECUTABLE, MODULE_LIBRARY): finished
#   link products, safe to use "--strip-unneeded" (keeps the dynamic
#   symbol table needed at runtime, e.g. a shared library's exported API,
#   but removes local symbols and all debug info).
#
# No-op if CMAKE_STRIP is not available (e.g. some cross-compilation
# toolchains that don't provide a strip binary).
function(strip_target TARGET_NAME)
    if(NOT CMAKE_STRIP)
        message(STATUS "strip_target(${TARGET_NAME}): CMAKE_STRIP not available, skipping")
        return()
    endif()

    get_target_property(_strip_target_type ${TARGET_NAME} TYPE)
    if(_strip_target_type STREQUAL "STATIC_LIBRARY")
        set(_strip_args --strip-debug)
    else()
        set(_strip_args --strip-unneeded)
    endif()

    add_custom_command(TARGET ${TARGET_NAME} POST_BUILD
        COMMAND ${CMAKE_STRIP} ${_strip_args} $<TARGET_FILE:${TARGET_NAME}>
        COMMENT "Stripping ${TARGET_NAME} (${_strip_args})"
        VERBATIM
    )
endfunction()
