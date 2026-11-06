file(GLOB NNC_BENCH_SOURCES CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/*.c)

foreach(src IN LISTS NNC_BENCH_SOURCES)
    get_filename_component(name ${src} NAME_WE)
    add_executable(${name} ${src})
    set_target_properties(${name} PROPERTIES
        C_STANDARD 17
        C_STANDARD_REQUIRED ON
        C_EXTENSIONS OFF
    )
    target_compile_definitions(${name} PRIVATE _POSIX_C_SOURCE=200809L)
    target_link_libraries(${name} PRIVATE nnc::nnc)
    nnc_apply_dev_options(${name})
endforeach()
