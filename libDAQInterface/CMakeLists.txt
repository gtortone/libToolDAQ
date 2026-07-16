cmake_minimum_required(VERSION 3.11)   # required by FetchContent
project(libDAQInterface CXX)

# --- External dependencies (ZeroMQ, Boost) -----------------------------------
# Searched for once in the parent CMakeLists.txt (libToolDAQ), inherited here.
if(NOT DEFINED ZeroMQ_FOUND OR NOT DEFINED Boost_FOUND)
    message(FATAL_ERROR
        "ZeroMQ/Boost have not been searched for. Make sure the parent "
        "CMakeLists.txt (libToolDAQ) calls find_zeromq()/find_boost_dependencies() "
        "BEFORE add_subdirectory(libDAQInterface).")
endif()

# --- Requires ToolFrameworkCore and ToolDAQFramework to already be configured -
# libDAQInterface is built on top of both libraries (see its Makefile:
# ToolFrameworkLib/ToolDAQLib). The TFC_*/TDF_* variables are exported by
# their respective CMakeLists.txt: make sure the order in the parent
# CMakeLists.txt is ToolFrameworkCore -> ToolDAQFramework -> libDAQInterface.
if(NOT DEFINED TFC_SOURCE_DIR)
    message(FATAL_ERROR
        "libDAQInterface requires ToolFrameworkCore. Add "
        "add_subdirectory(ToolFrameworkCore) BEFORE "
        "add_subdirectory(libDAQInterface) in the parent CMakeLists.txt.")
endif()
if(NOT DEFINED TDF_SOURCE_DIR)
    message(FATAL_ERROR
        "libDAQInterface requires ToolDAQFramework. Add "
        "add_subdirectory(ToolDAQFramework) BEFORE "
        "add_subdirectory(libDAQInterface) in the parent CMakeLists.txt.")
endif()

# --- General settings --------------------------------------------------------
# NOTE: libDAQInterface requires C++20 (unlike ToolFrameworkCore and
# ToolDAQFramework, which use C++11). Setting it here only affects the
# targets defined in this file, not the ones already created by the
# sibling subprojects.
set(CMAKE_CXX_STANDARD 20)
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

# --- Clone libDAQInterface ------------------------------------------------------
include(FetchContent)

set(TDI_REPO_URL "https://github.com/ToolDAQ/libDAQInterface.git"
    CACHE STRING "URL of the libDAQInterface repository")
set(TDI_REPO_TAG "main"
    CACHE STRING "Branch/tag/commit to clone")

if(POLICY CMP0169)
    cmake_policy(SET CMP0169 OLD)
endif()

# NOTE: all-lowercase name, required by FetchContent (the generated
# <name>_SOURCE_DIR/_POPULATED variables are always lower-case).
#
# PATCH_COMMAND: applies libDAQInterface/patches/0001-add-cstdint-to-DAQHeader.patch
# (adds "#include <cstdint>" to include/DAQHeader.h) with "git apply".
# It is run by ExternalProject/FetchContent with working directory =
# <SOURCE_DIR> (the freshly cloned sources, which are a git repo), so
# "git apply" works directly on the relative path given in the patch.
FetchContent_Declare(
    libdaqinterface_src
    GIT_REPOSITORY ${TDI_REPO_URL}
    GIT_TAG        ${TDI_REPO_TAG}
    GIT_SHALLOW    TRUE
    PATCH_COMMAND  git apply --ignore-whitespace
                   ${CMAKE_CURRENT_SOURCE_DIR}/patches/0001-add-cstdint-to-DAQHeader.patch
)

# NOTE: FetchContent's <name>_POPULATED flag is an in-memory-only global
# property (resets every "cmake" invocation) -- checking it alone would
# re-clone (and re-apply the patch) on every run. Instead we check DIRECTLY
# on disk, using FetchContent's own deterministic default location.
# Skipping FetchContent_Populate() when already present also skips
# re-applying PATCH_COMMAND (git apply), since the patch step only runs as
# part of the initial download/populate step, not on every configure.
set(TDI_EXPECTED_SOURCE_DIR ${FETCHCONTENT_BASE_DIR}/libdaqinterface_src-src)

if(EXISTS ${TDI_EXPECTED_SOURCE_DIR}/.git)
    message(STATUS "libDAQInterface already downloaded, skipping re-clone/re-patch: ${TDI_EXPECTED_SOURCE_DIR}")
    set(TDI_SOURCE_DIR ${TDI_EXPECTED_SOURCE_DIR})
else()
    message(STATUS "Cloning ${TDI_REPO_URL} (tag: ${TDI_REPO_TAG})...")
    FetchContent_Populate(libdaqinterface_src)
    set(TDI_SOURCE_DIR ${libdaqinterface_src_SOURCE_DIR})
endif()

if(NOT TDI_SOURCE_DIR OR NOT EXISTS ${TDI_SOURCE_DIR})
    message(FATAL_ERROR
        "Cloning libDAQInterface failed: TDI_SOURCE_DIR is empty or "
        "does not exist ('${TDI_SOURCE_DIR}').")
endif()

message(STATUS "libDAQInterface sources in: ${TDI_SOURCE_DIR}")

# --- Own headers + headers from dependencies --------------------------------
include_directories(${TDI_SOURCE_DIR}/include)
include_directories(${TFC_SOURCE_DIR}/include)
include_directories(${TFC_BUILD_INCLUDE_DIR})
include_directories(${TDF_SOURCE_DIR}/include)
include_directories(${TDF_BUILD_INCLUDE_DIR})

# --- DAQInterface library: SHARED + STATIC -----------------------------------
# The original Makefile explicitly compiles only src/DAQInterface.cpp
# (excluding the ROOT-generated DAQInterfaceClassDict.cpp, not needed for
# plain C++ usage). Here we replicate the same filter over every .cpp
# found in src/.
file(GLOB TDI_LIB_SOURCES ${TDI_SOURCE_DIR}/src/*.cpp)
list(FILTER TDI_LIB_SOURCES EXCLUDE REGEX ".*ClassDict\\.cpp$")

set(TDI_LINK_LIBS
    # ToolDAQFramework (real names generated by our CMakeLists.txt with the
    # "DAQ" prefix, see ToolDAQFramework/CMakeLists.txt)
    ServiceDiscovery
    DAQDataModelBase
    DAQStore
    # ToolFrameworkCore
    Store
    DataModelBase
    ${Boost_LIBRARIES}
    pthread
)
if(TARGET ToolFramework::ZeroMQ)
    list(APPEND TDI_LINK_LIBS ToolFramework::ZeroMQ)
endif()

if(TDI_LIB_SOURCES)
    # DAQInterface.cpp references Factory directly, so the library needs
    # Factory.cpp and its sibling Tools/DataModel compiled in directly
    # (recompiled here, by choice -- no shared "glue" library with
    # ToolDAQFramework).
    set(TDI_LIB_EXTRA_SOURCES "")
    if(EXISTS ${TDF_SOURCE_DIR}/UserTools/Factory/Factory.cpp)
        list(APPEND TDI_LIB_EXTRA_SOURCES ${TDF_SOURCE_DIR}/UserTools/Factory/Factory.cpp)
    else()
        message(WARNING "libDAQInterface: UserTools/Factory/Factory.cpp (from ToolDAQFramework) not found")
    endif()
    if(EXISTS ${TDF_SOURCE_DIR}/UserTools/DummyTool/DummyTool.cpp)
        list(APPEND TDI_LIB_EXTRA_SOURCES ${TDF_SOURCE_DIR}/UserTools/DummyTool/DummyTool.cpp)
    else()
        message(WARNING "libDAQInterface: UserTools/DummyTool/DummyTool.cpp (from ToolDAQFramework) not found")
    endif()
    if(EXISTS ${TDF_SOURCE_DIR}/UserTools/ServiceAdd/ServiceAdd.cpp)
        list(APPEND TDI_LIB_EXTRA_SOURCES ${TDF_SOURCE_DIR}/UserTools/ServiceAdd/ServiceAdd.cpp)
    else()
        message(WARNING "libDAQInterface: UserTools/ServiceAdd/ServiceAdd.cpp (from ToolDAQFramework) not found")
    endif()
    if(EXISTS ${TDF_SOURCE_DIR}/UserTools/Logger/Logger.cpp)
        list(APPEND TDI_LIB_EXTRA_SOURCES ${TDF_SOURCE_DIR}/UserTools/Logger/Logger.cpp)
    else()
        message(WARNING "libDAQInterface: UserTools/Logger/Logger.cpp (from ToolDAQFramework) not found")
    endif()
    if(EXISTS ${TDF_SOURCE_DIR}/DataModel/DataModel.cpp)
        list(APPEND TDI_LIB_EXTRA_SOURCES ${TDF_SOURCE_DIR}/DataModel/DataModel.cpp)
    else()
        message(WARNING "libDAQInterface: DataModel/DataModel.cpp (from ToolDAQFramework) not found")
    endif()

    set(TDI_EXTRA_INCLUDE_DIRS
        ${TDF_SOURCE_DIR}/UserTools/Factory
        ${TDF_SOURCE_DIR}/UserTools/DummyTool
        ${TDF_SOURCE_DIR}/UserTools/ServiceAdd
        ${TDF_SOURCE_DIR}/UserTools/Logger
        ${TDF_SOURCE_DIR}/DataModel
    )

    # --- shared object: libDAQInterface.so ---
    add_library(DAQInterface SHARED ${TDI_LIB_SOURCES} ${TDI_LIB_EXTRA_SOURCES})
    target_include_directories(DAQInterface PUBLIC ${TDI_SOURCE_DIR}/include ${TDI_EXTRA_INCLUDE_DIRS})
    target_link_libraries(DAQInterface PUBLIC ${TDI_LINK_LIBS})
    set_target_properties(DAQInterface PROPERTIES
        VERSION   1.0
        SOVERSION 1
    )
    strip_target(DAQInterface)

    # --- static library: libDAQInterface.a ---
    add_library(DAQInterface_static STATIC ${TDI_LIB_SOURCES} ${TDI_LIB_EXTRA_SOURCES})
    target_include_directories(DAQInterface_static PUBLIC ${TDI_SOURCE_DIR}/include ${TDI_EXTRA_INCLUDE_DIRS})
    target_link_libraries(DAQInterface_static PUBLIC ${TDI_LINK_LIBS})
    set_target_properties(DAQInterface_static PROPERTIES
        OUTPUT_NAME DAQInterface
        ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
    )
    strip_target(DAQInterface_static)

    message(STATUS "Configured library: DAQInterface (${TDI_LIB_SOURCES} ${TDI_LIB_EXTRA_SOURCES})")
else()
    message(WARNING "No sources found in ${TDI_SOURCE_DIR}/src, DAQInterface not generated")
endif()

# --- Companion executables ----------------------------------------------------
# These need UserTools/Factory/Factory.cpp, UserTools/DummyTool/DummyTool.cpp,
# UserTools/ServiceAdd/ServiceAdd.cpp, UserTools/Logger/Logger.cpp and
# DataModel/DataModel.cpp (to instantiate the Tools and the DataModel).
# libDAQInterface has no UserTools/DataModel folders of its own: we reuse
# those from ToolDAQFramework (recompiled per executable, by choice -- no
# shared "glue" library).
macro(tdi_add_executable TARGET_NAME MAIN_SOURCE)
    add_executable(${TARGET_NAME} ${MAIN_SOURCE} ${TDI_LIB_EXTRA_SOURCES})
    target_include_directories(${TARGET_NAME} PRIVATE ${TDI_EXTRA_INCLUDE_DIRS})
    target_link_libraries(${TARGET_NAME} PRIVATE DAQInterface ${TDI_LINK_LIBS})
    strip_target(${TARGET_NAME})
endmacro()

# Win_Mac_translation.cpp sits at the repo root, not in src/
if(EXISTS ${TDI_SOURCE_DIR}/Win_Mac_translation.cpp)
    tdi_add_executable(Win_Mac_translation ${TDI_SOURCE_DIR}/Win_Mac_translation.cpp)
endif()

if(EXISTS ${TDI_SOURCE_DIR}/Example/Example.cpp)
    tdi_add_executable(DAQInterfaceExample ${TDI_SOURCE_DIR}/Example/Example.cpp)
endif()

if(EXISTS ${TDI_SOURCE_DIR}/Testing/Test.cpp)
    tdi_add_executable(DAQInterfaceTest ${TDI_SOURCE_DIR}/Testing/Test.cpp)
endif()

if(EXISTS ${TDI_SOURCE_DIR}/Testing/Test2.cpp)
    tdi_add_executable(DAQInterfaceTest2 ${TDI_SOURCE_DIR}/Testing/Test2.cpp)
endif()

# RemoteControl: the original Makefile recompiles the source taken from
# ToolDAQFramework (not one of libDAQInterface's own), linked against
# libDAQInterface. The target is called "DAQInterfaceRemoteControl" to
# avoid colliding with the identically named executable already defined
# in ToolDAQFramework.
if(EXISTS ${TDF_SOURCE_DIR}/src/RemoteControl/RemoteControl.cpp)
    tdi_add_executable(DAQInterfaceRemoteControl
        ${TDF_SOURCE_DIR}/src/RemoteControl/RemoteControl.cpp)
endif()

# NOTE: Python support (lib/libDAQInterfaceClassDict.so, via ROOT rootcling)
# is not included here: it requires ROOT to be installed and a dedicated
# find_package(ROOT). Let me know if you need it and we'll add it as a
# separate option (e.g. option(TDI_ENABLE_PYTHON "Build ROOT/cppyy dictionary" OFF)).
