cmake_minimum_required(VERSION 3.20)
project(cpp_app LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_executable(cpp_app src/main.cpp)

install(TARGETS cpp_app RUNTIME DESTINATION bin)
