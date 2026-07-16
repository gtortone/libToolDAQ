cmake_minimum_required(VERSION 3.11)   # required by FetchContent
project(ToolDAQFramework CXX)

# --- External dependencies (ZeroMQ, Boost) -----------------------------------
# NO LONGER searched for here: the search is centralized in the parent
# CMakeLists.txt (libToolDAQ/CMakeLists.txt), which calls find_zeromq() and
# find_boost_dependencies() BEFORE add_subdirectory(ToolDAQFramework).
# The resulting variables/targets are automatically inherited in this
# scope. If ZeroMQ or Boost were not found there, configuration would
# already have failed before reaching this point (find_package(... REQUIRED)).
if(NOT DEFINED ZeroMQ_FOUND OR NOT DEFINED Boost_FOUND)
    message(FATAL_ERROR
        "ZeroMQ/Boost have not been searched for. Make sure the parent "
        "CMakeLists.txt (libToolDAQ) calls find_zeromq()/find_boost_dependencies() "
        "BEFORE add_subdirectory(ToolDAQFramework).")
endif()

# --- General settings --------------------------------------------------------
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_compile_options(-O3 -Wno-unused-result -Wno-deprecated-declarations)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# --- Make executables relocatable (avoid baking absolute build paths into
# the DT_NEEDED entries of the generated binaries) -- see the identical
# block in ToolFrameworkCore/CMakeLists.txt for the full explanation.
set(CMAKE_SKIP_BUILD_RPATH FALSE)
set(CMAKE_BUILD_WITH_INSTALL_RPATH FALSE)
set(CMAKE_INSTALL_RPATH "$ORIGIN:$ORIGIN/../lib")
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
set(CMAKE_BUILD_RPATH_USE_ORIGIN TRUE)

# --- Requires ToolFrameworkCore to already be configured ---------------------
# ToolDAQFramework is built on top of ToolFrameworkCore (see its Makefile:
# ToolFrameworkPath=../ToolFrameworkCore). The TFC_* variables are exported
# by ToolFrameworkCore/CMakeLists.txt: make sure that in the parent
# CMakeLists.txt add_subdirectory(ToolFrameworkCore) comes BEFORE
# add_subdirectory(ToolDAQFramework).
if(NOT DEFINED TFC_SOURCE_DIR)
    message(FATAL_ERROR
        "ToolDAQFramework requires ToolFrameworkCore. Add "
        "add_subdirectory(ToolFrameworkCore) BEFORE "
        "add_subdirectory(ToolDAQFramework) in the parent CMakeLists.txt.")
endif()

include_directories(${TFC_SOURCE_DIR}/include)
include_directories(${TFC_BUILD_INCLUDE_DIR})

# --- Clone ToolDAQFramework ----------------------------------------------------
include(FetchContent)

set(TDF_REPO_URL "https://github.com/ToolDAQ/ToolDAQFramework.git"
    CACHE STRING "URL of the ToolDAQFramework repository")
set(TDF_REPO_TAG "main"
    CACHE STRING "Branch/tag/commit to clone")

if(POLICY CMP0169)
    cmake_policy(SET CMP0169 OLD)
endif()

FetchContent_Declare(
    tooldaqframework_src
    GIT_REPOSITORY ${TDF_REPO_URL}
    GIT_TAG        ${TDF_REPO_TAG}
    GIT_SHALLOW    TRUE
)

# NOTE: FetchContent's <name>_POPULATED flag is an in-memory-only global
# property (resets every "cmake" invocation) -- checking it alone would
# re-clone on every run. Instead we check DIRECTLY on disk, using
# FetchContent's own deterministic default location.
set(TDF_EXPECTED_SOURCE_DIR ${FETCHCONTENT_BASE_DIR}/tooldaqframework_src-src)

if(EXISTS ${TDF_EXPECTED_SOURCE_DIR}/.git)
    message(STATUS "ToolDAQFramework already downloaded, skipping re-clone: ${TDF_EXPECTED_SOURCE_DIR}")
    set(TDF_SOURCE_DIR ${TDF_EXPECTED_SOURCE_DIR})
else()
    message(STATUS "Cloning ${TDF_REPO_URL} (tag: ${TDF_REPO_TAG})...")
    FetchContent_Populate(tooldaqframework_src)
    set(TDF_SOURCE_DIR ${tooldaqframework_src_SOURCE_DIR})
endif()

if(NOT TDF_SOURCE_DIR OR NOT EXISTS ${TDF_SOURCE_DIR})
    message(FATAL_ERROR
        "Cloning ToolDAQFramework failed: TDF_SOURCE_DIR is empty or "
        "does not exist ('${TDF_SOURCE_DIR}').")
endif()

message(STATUS "ToolDAQFramework sources in: ${TDF_SOURCE_DIR}")

# --- "Legacy" headers of the cloned project -----------------------------------
include_directories(${TDF_SOURCE_DIR}/include)
include_directories(${TDF_SOURCE_DIR}/tempinclude)

# --- Collect ALL headers (src/, DataModel/, UserTools/) --------------------
set(TDF_BUILD_INCLUDE_DIR ${CMAKE_BINARY_DIR}/include)
file(MAKE_DIRECTORY ${TDF_BUILD_INCLUDE_DIR})

file(GLOB_RECURSE TDF_SRC_HEADERS
    ${TDF_SOURCE_DIR}/src/*.h
    ${TDF_SOURCE_DIR}/src/*.hpp
)

if(EXISTS ${TDF_SOURCE_DIR}/DataModel/DataModel.h)
    list(APPEND TDF_SRC_HEADERS ${TDF_SOURCE_DIR}/DataModel/DataModel.h)
endif()

file(GLOB TDF_USERTOOLS_HEADERS ${TDF_SOURCE_DIR}/UserTools/*/*.h)
list(APPEND TDF_SRC_HEADERS ${TDF_USERTOOLS_HEADERS})

if(EXISTS ${TDF_SOURCE_DIR}/UserTools/Unity.h)
    list(APPEND TDF_SRC_HEADERS ${TDF_SOURCE_DIR}/UserTools/Unity.h)
endif()

foreach(HEADER ${TDF_SRC_HEADERS})
    file(COPY ${HEADER} DESTINATION ${TDF_BUILD_INCLUDE_DIR})
endforeach()

include_directories(${TDF_BUILD_INCLUDE_DIR})

message(STATUS "ToolDAQFramework headers collected in: ${TDF_BUILD_INCLUDE_DIR}")

# --- Generate a SHARED + STATIC library for each folder in the map --------
# EXPLICIT mapping of src/ folder -> library name: only these 5, regardless
# of any other folders present under src/, DataModel/ or UserTools/ (which
# are NO LONGER built here).
#
# The library name matches the folder name, EXCEPT for "Store" (renamed to
# "DAQStore" to avoid the collision with the identically named library in
# ToolFrameworkCore, both as a CMake target and as a lib*.so file in the
# same build/lib) -- consistent with the convention used by the original
# Makefile.
set(TDF_LIB_MAP
    "Store:DAQStore"
    "DAQLogging:DAQLogging"
    "ToolDAQChain:ToolDAQChain"
    "DAQDataModelBase:DAQDataModelBase"
    "ServiceDiscovery:ServiceDiscovery"
)

set(TDF_ALL_LIBS "")

foreach(_entry ${TDF_LIB_MAP})
    string(REPLACE ":" ";" _entry_pair "${_entry}")
    list(GET _entry_pair 0 DIR_NAME)
    list(GET _entry_pair 1 LIB_NAME)

    set(ENTRY ${TDF_SOURCE_DIR}/src/${DIR_NAME})

    if(NOT IS_DIRECTORY ${ENTRY})
        message(WARNING "ToolDAQFramework: expected folder not found, skipped: ${ENTRY}")
        continue()
    endif()

    file(GLOB LIB_SOURCES
        ${ENTRY}/*.cpp
        ${ENTRY}/*.cc
        ${ENTRY}/*.c
    )

    if(LIB_SOURCES)
        # --- shared object: lib<Name>.so ---
        add_library(${LIB_NAME} SHARED ${LIB_SOURCES})
        target_include_directories(${LIB_NAME} PUBLIC ${ENTRY})
        set_target_properties(${LIB_NAME} PROPERTIES
            VERSION   1.0
            SOVERSION 1
        )
        target_link_libraries(${LIB_NAME} PUBLIC ${Boost_LIBRARIES})
        if(TARGET ToolFramework::ZeroMQ)
            target_link_libraries(${LIB_NAME} PUBLIC ToolFramework::ZeroMQ)
        endif()
        strip_target(${LIB_NAME})

        # --- static library: lib<Name>.a ---
        add_library(${LIB_NAME}_static STATIC ${LIB_SOURCES})
        target_include_directories(${LIB_NAME}_static PUBLIC ${ENTRY})
        set_target_properties(${LIB_NAME}_static PROPERTIES
            OUTPUT_NAME ${LIB_NAME}
            ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
        )
        strip_target(${LIB_NAME}_static)

        list(APPEND TDF_ALL_LIBS ${LIB_NAME})
        message(STATUS "Configured library: ${LIB_NAME} (${LIB_SOURCES})")
    endif()
endforeach()

# --- Dependencies between internal libraries -------------------------------
# ToolDAQChain uses libraries from both ToolDAQFramework and ToolFrameworkCore.
if(TARGET ToolDAQChain)
    target_link_libraries(ToolDAQChain PUBLIC
        DAQStore DAQLogging DAQDataModelBase          # ToolDAQFramework libraries
        ToolChain Store Logging DataModelBase)        # ToolFrameworkCore libraries
endif()

# --- Executables ---------------------------------------------------------------
set(TDF_LINK_LIBS ${TDF_ALL_LIBS} ${TFC_ALL_LIBS} ${Boost_LIBRARIES} pthread)
if(TARGET ToolFramework::ZeroMQ)
    list(APPEND TDF_LINK_LIBS ToolFramework::ZeroMQ)
endif()

# Built together with UserTools/Factory/Factory.cpp, UserTools/DummyTool/
# DummyTool.cpp, UserTools/ServiceAdd/ServiceAdd.cpp, UserTools/Logger/
# Logger.cpp (Factory.cpp directly references these Tools), and
# DataModel/DataModel.cpp (needed to instantiate the DataModel), NOT as
# standalone libraries but as extra sources of each executable (recompiled
# per executable, by choice -- no shared "glue" library).
set(TDF_EXTRA_EXE_SOURCES "")
if(EXISTS ${TDF_SOURCE_DIR}/UserTools/Factory/Factory.cpp)
    list(APPEND TDF_EXTRA_EXE_SOURCES ${TDF_SOURCE_DIR}/UserTools/Factory/Factory.cpp)
else()
    message(WARNING "ToolDAQFramework: UserTools/Factory/Factory.cpp not found")
endif()
if(EXISTS ${TDF_SOURCE_DIR}/UserTools/DummyTool/DummyTool.cpp)
    list(APPEND TDF_EXTRA_EXE_SOURCES ${TDF_SOURCE_DIR}/UserTools/DummyTool/DummyTool.cpp)
else()
    message(WARNING "ToolDAQFramework: UserTools/DummyTool/DummyTool.cpp not found")
endif()
if(EXISTS ${TDF_SOURCE_DIR}/UserTools/ServiceAdd/ServiceAdd.cpp)
    list(APPEND TDF_EXTRA_EXE_SOURCES ${TDF_SOURCE_DIR}/UserTools/ServiceAdd/ServiceAdd.cpp)
else()
    message(WARNING "ToolDAQFramework: UserTools/ServiceAdd/ServiceAdd.cpp not found")
endif()
if(EXISTS ${TDF_SOURCE_DIR}/UserTools/Logger/Logger.cpp)
    list(APPEND TDF_EXTRA_EXE_SOURCES ${TDF_SOURCE_DIR}/UserTools/Logger/Logger.cpp)
else()
    message(WARNING "ToolDAQFramework: UserTools/Logger/Logger.cpp not found")
endif()
if(EXISTS ${TDF_SOURCE_DIR}/DataModel/DataModel.cpp)
    list(APPEND TDF_EXTRA_EXE_SOURCES ${TDF_SOURCE_DIR}/DataModel/DataModel.cpp)
else()
    message(WARNING "ToolDAQFramework: DataModel/DataModel.cpp not found")
endif()

macro(tdf_add_executable TARGET_NAME MAIN_SOURCE)
    add_executable(${TARGET_NAME} ${MAIN_SOURCE} ${TDF_EXTRA_EXE_SOURCES})
    target_include_directories(${TARGET_NAME} PRIVATE
        ${TDF_SOURCE_DIR}/UserTools/Factory
        ${TDF_SOURCE_DIR}/UserTools/DummyTool
        ${TDF_SOURCE_DIR}/UserTools/ServiceAdd
        ${TDF_SOURCE_DIR}/UserTools/Logger
        ${TDF_SOURCE_DIR}/DataModel
    )
    target_link_libraries(${TARGET_NAME} PRIVATE ${TDF_LINK_LIBS})
    strip_target(${TARGET_NAME})
endmacro()

# NOTE: the target is called "DAQmain" (not "main") to avoid colliding with
# the "main" executable already defined by ToolFrameworkCore/CMakeLists.txt.
if(EXISTS ${TDF_SOURCE_DIR}/src/main.cpp)
    tdf_add_executable(DAQmain ${TDF_SOURCE_DIR}/src/main.cpp)
endif()

if(EXISTS ${TDF_SOURCE_DIR}/src/NodeDaemon/NodeDaemon.cpp)
    tdf_add_executable(NodeDaemon ${TDF_SOURCE_DIR}/src/NodeDaemon/NodeDaemon.cpp)
endif()

if(EXISTS ${TDF_SOURCE_DIR}/src/RemoteControl/RemoteControl.cpp)
    tdf_add_executable(RemoteControl ${TDF_SOURCE_DIR}/src/RemoteControl/RemoteControl.cpp)
endif()

if(EXISTS ${TDF_SOURCE_DIR}/src/RemoteControl/MCDebug.cpp)
    tdf_add_executable(MCDebug ${TDF_SOURCE_DIR}/src/RemoteControl/MCDebug.cpp)
endif()

message(STATUS "ToolDAQFramework libraries generated: ${TDF_ALL_LIBS}")

# --- Export to the parent CMakeLists.txt -----------------------------------
# Allows other subprojects (e.g. libDAQInterface, which depends on
# ToolDAQFramework) to reuse sources, headers and libraries without having
# to re-clone or re-discover them.
set(TDF_SOURCE_DIR        ${TDF_SOURCE_DIR}        PARENT_SCOPE)
set(TDF_BUILD_INCLUDE_DIR ${TDF_BUILD_INCLUDE_DIR} PARENT_SCOPE)
set(TDF_ALL_LIBS          ${TDF_ALL_LIBS}          PARENT_SCOPE)
