cmake_minimum_required(VERSION 3.28)
project(os LANGUAGES CXX)

# Require C++23
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Generate compile_commands.json
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# --- string_helpers module ---
add_library(string_helpers
    string_helpers/string_helpers.cpp
)
target_include_directories(string_helpers PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/string_helpers)
target_compile_features(string_helpers PUBLIC cxx_std_23)

# --- main executable ---
add_executable(os main.cpp)
target_compile_features(os PRIVATE cxx_std_23)
target_link_libraries(os PRIVATE string_helpers)