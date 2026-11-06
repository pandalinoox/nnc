cmake_minimum_required(VERSION 3.28)

project(nnc
    VERSION 1.0.0
    DESCRIPTION "A reusable neural network library written in C"
    LANGUAGES C
)


option(NNC_WITH_OPENCL "Enable the OpenCL backend for matrix multiplication" ON)
option(NNC_BUILD_TESTS "Build the Criterion test suite" ${PROJECT_IS_TOP_LEVEL})
option(NNC_BUILD_BENCHMARKS "Build the benchmarks" OFF)
option(NNC_INSTALL "Generate install rules and package files" ${PROJECT_IS_TOP_LEVEL})
option(NNC_SANITIZE "Build with AddressSanitizer and UndefinedBehaviorSanitizer" OFF)
option(NNC_WERROR "Treat compiler warnings as errors" OFF)

set(NNC_OPENCL_TARGET_VERSION 300 CACHE STRING "OpenCL API version to target")

if(PROJECT_IS_TOP_LEVEL)
    if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
        set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
    endif()
    set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
endif()

include(GNUInstallDirs)

set(NNC_WARNINGS
    -Wall
    -Wextra
    -Wpedantic
    -Wshadow
    -Wconversion
    -Wdouble-promotion
    -Wfloat-equal
)

if(NNC_WERROR)
    list(APPEND NNC_WARNINGS -Werror)
endif()

function(nnc_apply_dev_options target)
    if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(${target} PRIVATE ${NNC_WARNINGS})
        if(NNC_SANITIZE)
            target_compile_options(${target} PRIVATE
                -fsanitize=address,undefined -fno-omit-frame-pointer)
            target_link_options(${target} PRIVATE -fsanitize=address,undefined)
        endif()
    endif()
endfunction()

if(NNC_WITH_OPENCL)
    find_package(OpenCL 3.0 REQUIRED)
    message(STATUS "Using OpenCL ${OpenCL_VERSION_STRING} (target API ${NNC_OPENCL_TARGET_VERSION})")
endif()

file(GLOB_RECURSE NNC_SOURCES CONFIGURE_DEPENDS
    ${PROJECT_SOURCE_DIR}/src/*.c
)
list(FILTER NNC_SOURCES EXCLUDE REGEX ".*/main\\.c$")

if(NOT NNC_WITH_OPENCL)
    list(FILTER NNC_SOURCES EXCLUDE REGEX ".*/src/opencl/.*")
endif()

if(NNC_SOURCES)
    add_library(nnc ${NNC_SOURCES})
    add_library(nnc::nnc ALIAS nnc)

    set_target_properties(nnc PROPERTIES
        C_STANDARD 17
        C_STANDARD_REQUIRED ON
        C_EXTENSIONS OFF
        VERSION ${PROJECT_VERSION}
        SOVERSION ${PROJECT_VERSION_MAJOR}
        EXPORT_NAME nnc
    )

    target_include_directories(nnc
        PUBLIC
            $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>
            $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
        PRIVATE
            ${PROJECT_SOURCE_DIR}/src
    )

    target_compile_definitions(nnc
        PRIVATE
            _POSIX_C_SOURCE=200809L
        PUBLIC
            NNC_WITH_OPENCL=$<BOOL:${NNC_WITH_OPENCL}>
    )

    if(NOT WIN32)
        target_link_libraries(nnc PUBLIC m)
    endif()

    if(NNC_WITH_OPENCL)
        target_compile_definitions(nnc
            PUBLIC
                CL_TARGET_OPENCL_VERSION=${NNC_OPENCL_TARGET_VERSION}
            PRIVATE
                NNC_KERNELS_DIR_BUILD="${PROJECT_SOURCE_DIR}/kernels"
                NNC_KERNELS_DIR_INSTALL="${CMAKE_INSTALL_FULL_DATADIR}/nnc/kernels"
        )
        target_link_libraries(nnc PUBLIC OpenCL::OpenCL)
    endif()

    nnc_apply_dev_options(nnc)

    if(NNC_INSTALL)
        include(CMakePackageConfigHelpers)

        install(TARGETS nnc
            EXPORT nncTargets
            ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
            LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
            INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
        )

        set(_nnc_header_excludes "")
        if(NOT NNC_WITH_OPENCL)
            set(_nnc_header_excludes PATTERN "opencl" EXCLUDE)
        endif()

        install(DIRECTORY ${PROJECT_SOURCE_DIR}/include/
            DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
            FILES_MATCHING PATTERN "*.h"
            ${_nnc_header_excludes}
        )

        if(NNC_WITH_OPENCL AND EXISTS "${PROJECT_SOURCE_DIR}/kernels")
            install(DIRECTORY ${PROJECT_SOURCE_DIR}/kernels/
                DESTINATION ${CMAKE_INSTALL_DATADIR}/nnc/kernels
                PATTERN ".gitkeep" EXCLUDE
            )
        endif()

        set(NNC_INSTALL_CMAKEDIR "${CMAKE_INSTALL_LIBDIR}/cmake/nnc")

        configure_package_config_file(
            ${PROJECT_SOURCE_DIR}/cmake/nncConfig.cmake.in
            ${PROJECT_BINARY_DIR}/nncConfig.cmake
            INSTALL_DESTINATION ${NNC_INSTALL_CMAKEDIR}
        )

        write_basic_package_version_file(
            ${PROJECT_BINARY_DIR}/nncConfigVersion.cmake
            VERSION ${PROJECT_VERSION}
            COMPATIBILITY SameMajorVersion
        )

        install(EXPORT nncTargets
            FILE nncTargets.cmake
            NAMESPACE nnc::
            DESTINATION ${NNC_INSTALL_CMAKEDIR}
        )

        install(FILES
            ${PROJECT_BINARY_DIR}/nncConfig.cmake
            ${PROJECT_BINARY_DIR}/nncConfigVersion.cmake
            DESTINATION ${NNC_INSTALL_CMAKEDIR}
        )

        if(NNC_WITH_OPENCL)
            set(NNC_PC_CFLAGS "-DNNC_WITH_OPENCL=1 -DCL_TARGET_OPENCL_VERSION=${NNC_OPENCL_TARGET_VERSION}")
            set(NNC_PC_LIBS_PRIVATE "-lOpenCL -lm")
        else()
            set(NNC_PC_CFLAGS "-DNNC_WITH_OPENCL=0")
            set(NNC_PC_LIBS_PRIVATE "-lm")
        endif()

        if(BUILD_SHARED_LIBS)
            set(NNC_PC_LIBS_PUBLIC "")
        else()
            set(NNC_PC_LIBS_PUBLIC "${NNC_PC_LIBS_PRIVATE}")
        endif()

        configure_file(
            ${PROJECT_SOURCE_DIR}/cmake/nnc.pc.in
            ${PROJECT_BINARY_DIR}/nnc.pc
            @ONLY
        )

        install(FILES ${PROJECT_BINARY_DIR}/nnc.pc
            DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig
        )
    endif()
else()
    message(STATUS "No library sources in src/ yet; skipping the nnc library target")
endif()

if(NNC_BUILD_TESTS)
    file(GLOB_RECURSE NNC_TEST_SOURCES CONFIGURE_DEPENDS
        ${PROJECT_SOURCE_DIR}/tests/*.c
    )

    if(NNC_TEST_SOURCES)
        enable_testing()

        find_package(PkgConfig REQUIRED)
        pkg_check_modules(CRITERION REQUIRED IMPORTED_TARGET criterion)

        add_executable(nnc_tests ${NNC_TEST_SOURCES})

        set_target_properties(nnc_tests PROPERTIES
            C_STANDARD 17
            C_STANDARD_REQUIRED ON
            C_EXTENSIONS OFF
        )

        target_compile_definitions(nnc_tests PRIVATE _POSIX_C_SOURCE=200809L)
        target_link_libraries(nnc_tests PRIVATE PkgConfig::CRITERION)
        if(TARGET nnc)
            target_link_libraries(nnc_tests PRIVATE nnc::nnc)
        endif()
        nnc_apply_dev_options(nnc_tests)

        add_test(NAME nnc_tests COMMAND nnc_tests)

        add_custom_target(check
            COMMAND ${CMAKE_CTEST_COMMAND} --test-dir ${CMAKE_BINARY_DIR} --output-on-failure
            DEPENDS nnc_tests
            USES_TERMINAL
            COMMENT "Running tests"
        )
    endif()
endif()

if(NNC_BUILD_BENCHMARKS AND EXISTS "${PROJECT_SOURCE_DIR}/benchmarks/CMakeLists.txt")
    add_subdirectory(benchmarks)
endif()

if(PROJECT_IS_TOP_LEVEL)
    find_program(NNC_CLANG_FORMAT clang-format)

    file(GLOB_RECURSE NNC_FORMAT_SOURCES CONFIGURE_DEPENDS
        ${PROJECT_SOURCE_DIR}/src/*.c
        ${PROJECT_SOURCE_DIR}/src/*.h
        ${PROJECT_SOURCE_DIR}/include/*.h
        ${PROJECT_SOURCE_DIR}/tests/*.c
        ${PROJECT_SOURCE_DIR}/tests/*.h
        ${PROJECT_SOURCE_DIR}/benchmarks/*.c
        ${PROJECT_SOURCE_DIR}/benchmarks/*.h
    )

    if(NNC_CLANG_FORMAT AND NNC_FORMAT_SOURCES)
        add_custom_target(format
            COMMAND ${NNC_CLANG_FORMAT} -i ${NNC_FORMAT_SOURCES}
            COMMENT "Formatting sources with clang-format"
            VERBATIM
        )

        add_custom_target(format-check
            COMMAND ${NNC_CLANG_FORMAT} --dry-run --Werror ${NNC_FORMAT_SOURCES}
            COMMENT "Checking formatting with clang-format"
            VERBATIM
        )
    endif()
endif()
