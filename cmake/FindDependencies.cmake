function(find_zeromq)
    # pkg-config, when run during cross-compilation, invokes the HOST's
    # pkg-config binary and reads the HOST's libzmq.pc by default (unless
    # PKG_CONFIG_SYSROOT_DIR/PKG_CONFIG_LIBDIR are explicitly configured for
    # the target, which we don't assume here). That would report the host's
    # x86_64 include/lib directories as HINTS below, which take priority
    # over the PATHS fallback and over CMake's own cross-aware search paths
    # -- causing the wrong-architecture library to be picked up. So we skip
    # pkg-config entirely when cross-compiling and rely on find_path/
    # find_library's normal (CMAKE_FIND_ROOT_PATH-aware) search instead.
    if(NOT CMAKE_CROSSCOMPILING)
        find_package(PkgConfig QUIET)
        if(PKG_CONFIG_FOUND)
            pkg_check_modules(PC_ZMQ QUIET libzmq)
        endif()
    endif()
    find_path(ZMQ_INCLUDE_DIR
        NAMES zmq.h
        HINTS ${PC_ZMQ_INCLUDEDIR} ${PC_ZMQ_INCLUDE_DIRS}
              $ENV{ZMQ_ROOT}/include $ENV{ZEROMQ_ROOT}/include
              ${ZMQ_ROOT}/include
        PATHS /usr/include /usr/local/include /opt/include)
    find_library(ZMQ_LIBRARY
        NAMES zmq libzmq
        HINTS ${PC_ZMQ_LIBDIR} ${PC_ZMQ_LIBRARY_DIRS}
              $ENV{ZMQ_ROOT}/lib $ENV{ZEROMQ_ROOT}/lib
              ${ZMQ_ROOT}/lib
        PATHS /usr/lib /usr/local/lib /opt/lib)
    include(FindPackageHandleStandardArgs)
    find_package_handle_standard_args(ZeroMQ
        REQUIRED_VARS ZMQ_LIBRARY ZMQ_INCLUDE_DIR)
    if(ZeroMQ_FOUND AND NOT TARGET ToolFramework::ZeroMQ)
        add_library(ToolFramework::ZeroMQ UNKNOWN IMPORTED GLOBAL)
        set_target_properties(ToolFramework::ZeroMQ PROPERTIES
            IMPORTED_LOCATION             "${ZMQ_LIBRARY}"
            INTERFACE_INCLUDE_DIRECTORIES "${ZMQ_INCLUDE_DIR}")
    endif()
    # Export the results to the caller
    set(ZeroMQ_FOUND     ${ZeroMQ_FOUND}     PARENT_SCOPE)
    set(ZMQ_INCLUDE_DIRS ${ZMQ_INCLUDE_DIR}  PARENT_SCOPE)
    set(ZMQ_LIBRARIES    ${ZMQ_LIBRARY}      PARENT_SCOPE)
endfunction()
function(find_boost_dependencies)
    set(_components ${ARGN})
    if(NOT _components)
        set(_components date_time serialization iostreams)
    endif()
    # Prefer BoostConfig.cmake when available (CMake >= 3.30)
    if(POLICY CMP0167)
        cmake_policy(SET CMP0167 NEW)
    endif()
    find_package(Boost REQUIRED COMPONENTS ${_components})

    # boost_iostreams can be built with optional compression backends
    # (zstd/bz2/zlib). ${Boost_LIBRARIES} (legacy module-mode variable, as
    # opposed to the Boost::iostreams imported target) does NOT pull in
    # these transitive shared-library dependencies automatically, and
    # linkers using --as-needed (default on many distros/cross-toolchains)
    # will drop them unless listed explicitly -- causing errors like
    # "undefined reference to ZSTD_createDCtx" / "DSO missing from command
    # line". Find them here and append them, so every target linking
    # ${Boost_LIBRARIES} gets them automatically.
    set(_boost_extra_libs "")
    find_library(ZSTD_LIBRARY NAMES zstd)
    if(ZSTD_LIBRARY)
        list(APPEND _boost_extra_libs ${ZSTD_LIBRARY})
    endif()
    find_library(BZ2_LIBRARY NAMES bz2)
    if(BZ2_LIBRARY)
        list(APPEND _boost_extra_libs ${BZ2_LIBRARY})
    endif()
    find_library(ZLIB_LIBRARY NAMES z zlib)
    if(ZLIB_LIBRARY)
        list(APPEND _boost_extra_libs ${ZLIB_LIBRARY})
    endif()

    set(Boost_FOUND        ${Boost_FOUND}                        PARENT_SCOPE)
    set(Boost_INCLUDE_DIRS ${Boost_INCLUDE_DIRS}                 PARENT_SCOPE)
    set(Boost_LIBRARIES    "${Boost_LIBRARIES};${_boost_extra_libs}" PARENT_SCOPE)
endfunction()
