cmake_minimum_required(VERSION 3.11)   # required by FetchContent
project(ToolFrameworkCore CXX)

# --- External dependencies (ZeroMQ, Boost) -----------------------------------
# NO LONGER searched for here: the search is centralized in the parent
# CMakeLists.txt (libToolDAQ/CMakeLists.txt), which calls find_zeromq() and
# find_boost_dependencies() BEFORE add_subdirectory(ToolFrameworkCore).
# The resulting variables/targets (ZeroMQ_FOUND, ZMQ_INCLUDE_DIRS,
# ZMQ_LIBRARIES, ToolFramework::ZeroMQ, Boost_FOUND, Boost_INCLUDE_DIRS,
# Boost_LIBRARIES) are automatically inherited in this scope.
#
# If instead you are configuring this CMakeLists.txt on its own (without the
# libToolDAQ parent), copy cmake/FindDependencies.cmake from libToolDAQ/cmake/
# into ToolFrameworkCore/cmake/ and uncomment the following lines:
# list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)
# include(FindDependencies)
# find_zeromq()
# find_boost_dependencies()

# --- General settings ---------------------------------------------------
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)   # needed to link .a files into .so files

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Global compile options
add_compile_options(-O3 -Wno-unused-result -Wno-deprecated-declarations)

# All libraries end up in lib/, executables in bin/, inside the build dir
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# --- Make executables relocatable (avoid baking absolute build paths into
# the DT_NEEDED entries of the generated binaries) ------------------------
# Without an explicit SOVERSION, a shared library has no SONAME, so the
# linker embeds the full absolute path used at link time into every
# executable that links against it. Setting VERSION/SOVERSION (done below,
# on each add_library(SHARED ...) call) fixes the SONAME to a plain
# "lib<Name>.so". Combined with an $ORIGIN-relative RPATH, executables can
# then find their libraries relative to their own location (bin/../lib)
# instead of a hardcoded build-tree path.
set(CMAKE_SKIP_BUILD_RPATH FALSE)
set(CMAKE_BUILD_WITH_INSTALL_RPATH FALSE)
set(CMAKE_INSTALL_RPATH "$ORIGIN:$ORIGIN/../lib")
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
set(CMAKE_BUILD_RPATH_USE_ORIGIN TRUE)

# --- Clone ToolFrameworkCore ---------------------------------------------
include(FetchContent)

set(TFC_REPO_URL "https://github.com/ToolFramework/ToolFrameworkCore.git"
    CACHE STRING "URL of the ToolFrameworkCore repository")
set(TFC_REPO_TAG "main"
    CACHE STRING "Branch/tag/commit to clone")

FetchContent_Declare(
    toolframeworkcore_src
    GIT_REPOSITORY ${TFC_REPO_URL}
    GIT_TAG        ${TFC_REPO_TAG}
    GIT_SHALLOW    TRUE
)

# Using Populate (instead of MakeAvailable) because the repo has its own
# CMakeLists.txt/Makefile that we do NOT want to run: we only need the
# sources, the build logic is the one defined below.
# CMP0169=OLD suppresses the deprecation warning for FetchContent_Populate
# (introduced in CMake 3.30) while keeping the current behavior.
if(POLICY CMP0169)
    cmake_policy(SET CMP0169 OLD)
endif()

# NOTE: FetchContent's <name>_POPULATED flag is tracked via an in-memory
# global property, NOT persisted to disk -- it resets on every single
# "cmake" invocation, so checking it alone would call FetchContent_Populate()
# (and therefore re-clone) every time. Instead, we check DIRECTLY on disk
# whether the sources are already there, using FetchContent's own default,
# deterministic location (${FETCHCONTENT_BASE_DIR}/<name>-src, where
# FETCHCONTENT_BASE_DIR defaults to ${CMAKE_BINARY_DIR}/_deps and is set by
# include(FetchContent) above).
set(TFC_EXPECTED_SOURCE_DIR ${FETCHCONTENT_BASE_DIR}/toolframeworkcore_src-src)

if(EXISTS ${TFC_EXPECTED_SOURCE_DIR}/.git)
    message(STATUS "ToolFrameworkCore already downloaded, skipping re-clone: ${TFC_EXPECTED_SOURCE_DIR}")
    set(TFC_SOURCE_DIR ${TFC_EXPECTED_SOURCE_DIR})
else()
    message(STATUS "Cloning ${TFC_REPO_URL} (tag: ${TFC_REPO_TAG})...")
    FetchContent_Populate(toolframeworkcore_src)
    set(TFC_SOURCE_DIR ${toolframeworkcore_src_SOURCE_DIR})
endif()

if(NOT TFC_SOURCE_DIR OR NOT EXISTS ${TFC_SOURCE_DIR})
    message(FATAL_ERROR
        "Cloning ToolFrameworkCore failed: TFC_SOURCE_DIR is empty or "
        "does not exist ('${TFC_SOURCE_DIR}').")
endif()

message(STATUS "ToolFrameworkCore sources in: ${TFC_SOURCE_DIR}")

# --- "Legacy" headers of the cloned project -------------------------------
include_directories(${TFC_SOURCE_DIR}/include)
include_directories(${TFC_SOURCE_DIR}/tempinclude)

# --- Collect ALL headers from src/ into <build>/include -------------------
# Physically copies (no symlinks) every header from src/*/*.h into
# build/include.
set(TFC_BUILD_INCLUDE_DIR ${CMAKE_BINARY_DIR}/include)
file(MAKE_DIRECTORY ${TFC_BUILD_INCLUDE_DIR})

file(GLOB_RECURSE TFC_SRC_HEADERS
    ${TFC_SOURCE_DIR}/src/*.h
    ${TFC_SOURCE_DIR}/src/*.hpp
)

# DataModel/ is a "sibling" folder of src/ (not covered by the glob above),
# but its main header is still needed in the build include/ directory
if(EXISTS ${TFC_SOURCE_DIR}/DataModel/DataModel.h)
    list(APPEND TFC_SRC_HEADERS ${TFC_SOURCE_DIR}/DataModel/DataModel.h)
endif()

# UserTools/<Tool>/*.h -- each Tool has its own header, these also need to
# be copied into the build include/ directory
file(GLOB USERTOOLS_HEADERS ${TFC_SOURCE_DIR}/UserTools/*/*.h)
list(APPEND TFC_SRC_HEADERS ${USERTOOLS_HEADERS})

# UserTools/Unity.h -- aggregator header at the UserTools/ level, not
# covered by the glob above because it sits directly in UserTools/ and not
# in one of its subfolders
if(EXISTS ${TFC_SOURCE_DIR}/UserTools/Unity.h)
    list(APPEND TFC_SRC_HEADERS ${TFC_SOURCE_DIR}/UserTools/Unity.h)
endif()

foreach(HEADER ${TFC_SRC_HEADERS})
    file(COPY ${HEADER} DESTINATION ${TFC_BUILD_INCLUDE_DIR})
endforeach()

include_directories(${TFC_BUILD_INCLUDE_DIR})

message(STATUS "Headers collected in: ${TFC_BUILD_INCLUDE_DIR} (${TFC_SRC_HEADERS})")

# EXPLICIT list of the subdirectories to build as libraries: only these 4,
# regardless of any other folders that might exist under src/ or the
# DataModel/ folder (which is NO LONGER built here).
set(SRC_ENTRIES
    ${TFC_SOURCE_DIR}/src/Store
    ${TFC_SOURCE_DIR}/src/Logging
    ${TFC_SOURCE_DIR}/src/ToolChain
    ${TFC_SOURCE_DIR}/src/DataModelBase
)

# --- Generate a SHARED + STATIC library for each subdirectory of src ----
set(TFC_ALL_LIBS "")

foreach(ENTRY ${SRC_ENTRIES})
    if(NOT IS_DIRECTORY ${ENTRY})
        message(WARNING "ToolFrameworkCore: expected folder not found, skipped: ${ENTRY}")
        continue()
    endif()

    get_filename_component(LIB_NAME ${ENTRY} NAME)

    file(GLOB LIB_SOURCES
        ${ENTRY}/*.cpp
        ${ENTRY}/*.cc
        ${ENTRY}/*.c
    )

    if(LIB_SOURCES)
        # --- shared object: libNAME.so ---
        add_library(${LIB_NAME} SHARED ${LIB_SOURCES})
        target_include_directories(${LIB_NAME} PUBLIC ${ENTRY})
        set_target_properties(${LIB_NAME} PROPERTIES
            VERSION   1.0
            SOVERSION 1
        )
        strip_target(${LIB_NAME})

        # --- static library: libNAME.a ---
        add_library(${LIB_NAME}_static STATIC ${LIB_SOURCES})
        target_include_directories(${LIB_NAME}_static PUBLIC ${ENTRY})
        set_target_properties(${LIB_NAME}_static PROPERTIES
            OUTPUT_NAME ${LIB_NAME}
            ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
        )
        strip_target(${LIB_NAME}_static)

        list(APPEND TFC_ALL_LIBS ${LIB_NAME})
        message(STATUS "Configured library: ${LIB_NAME} (${LIB_SOURCES})")
    endif()
endforeach()

# --- Dependencies between internal libraries -----------------------------
# Some ToolFrameworkCore libraries depend on others (e.g. ToolChain uses
# Store/Logging/DataModelBase). Link them explicitly if needed, e.g.:
if(TARGET ToolChain AND TARGET Store)
    target_link_libraries(ToolChain PUBLIC Store Logging DataModelBase)
endif()

# --- Linking ZeroMQ / Boost to the libraries that need them ---------------
# Example: if a library generated above (e.g. ServiceDiscovery) uses ZMQ
# and/or Boost, link it like this:
# if(TARGET ServiceDiscovery)
#     target_link_libraries(ServiceDiscovery PUBLIC ToolFramework::ZeroMQ ${Boost_LIBRARIES})
#     target_include_directories(ServiceDiscovery PUBLIC ${Boost_INCLUDE_DIRS})
# endif()

# --- Main executable (src/main.cpp) --------------------------------------
# Built together with UserTools/Factory/Factory.cpp, UserTools/DummyTool/
# DummyTool.cpp (directly referenced by Factory.cpp) and
# DataModel/DataModel.cpp, NOT as standalone libraries but as extra sources
# of the executable itself.
set(TFC_EXTRA_EXE_SOURCES "")
if(EXISTS ${TFC_SOURCE_DIR}/UserTools/Factory/Factory.cpp)
    list(APPEND TFC_EXTRA_EXE_SOURCES ${TFC_SOURCE_DIR}/UserTools/Factory/Factory.cpp)
else()
    message(WARNING "ToolFrameworkCore: UserTools/Factory/Factory.cpp not found")
endif()
if(EXISTS ${TFC_SOURCE_DIR}/UserTools/DummyTool/DummyTool.cpp)
    list(APPEND TFC_EXTRA_EXE_SOURCES ${TFC_SOURCE_DIR}/UserTools/DummyTool/DummyTool.cpp)
else()
    message(WARNING "ToolFrameworkCore: UserTools/DummyTool/DummyTool.cpp not found")
endif()
if(EXISTS ${TFC_SOURCE_DIR}/DataModel/DataModel.cpp)
    list(APPEND TFC_EXTRA_EXE_SOURCES ${TFC_SOURCE_DIR}/DataModel/DataModel.cpp)
else()
    message(WARNING "ToolFrameworkCore: DataModel/DataModel.cpp not found")
endif()

if(EXISTS ${TFC_SOURCE_DIR}/src/main.cpp)
    add_executable(main ${TFC_SOURCE_DIR}/src/main.cpp ${TFC_EXTRA_EXE_SOURCES})
    target_include_directories(main PRIVATE
        ${TFC_SOURCE_DIR}/UserTools/Factory
        ${TFC_SOURCE_DIR}/UserTools/DummyTool
        ${TFC_SOURCE_DIR}/DataModel
    )
    target_link_libraries(main PRIVATE ${TFC_ALL_LIBS} pthread)
    strip_target(main)
endif()

message(STATUS "Libraries generated (shared + static): ${TFC_ALL_LIBS}")

# --- Export to the parent CMakeLists.txt -----------------------------------
# Allows other subprojects (e.g. ToolDAQFramework, which depends on
# ToolFrameworkCore) to reuse sources, headers and libraries without having
# to re-clone or re-discover them.
set(TFC_SOURCE_DIR        ${TFC_SOURCE_DIR}        PARENT_SCOPE)
set(TFC_BUILD_INCLUDE_DIR ${TFC_BUILD_INCLUDE_DIR} PARENT_SCOPE)
set(TFC_ALL_LIBS          ${TFC_ALL_LIBS}          PARENT_SCOPE)
