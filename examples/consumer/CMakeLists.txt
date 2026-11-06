cmake_minimum_required(VERSION 3.28)
project(nnc_consumer C)

find_package(nnc 1 REQUIRED)

add_executable(consumer main.c)
target_link_libraries(consumer PRIVATE nnc::nnc)
