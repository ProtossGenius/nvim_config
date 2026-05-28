cmake_minimum_required(VERSION 3.20)

project(cpp_cmake_demo LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_library(cpp_demo_lib
  src/app.cpp
  src/worker.cpp
)

target_include_directories(cpp_demo_lib PUBLIC include)

add_executable(cpp_dap_demo
  src/main.cpp
)

target_link_libraries(cpp_dap_demo PRIVATE cpp_demo_lib)
