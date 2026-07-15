cmake_minimum_required(VERSION 3.28)
project(os LANGUAGES CXX)

# Require C++23
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Generate compile_commands.json
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Force scanning on (CMake 3.28+ will handle the rest natively)
set(CMAKE_CXX_SCAN_FOR_MODULES ON)

# --- string_helpers module ---
add_library(string_helpers)
target_sources(string_helpers
    PRIVATE
        string_helpers/string_helpers.cpp
    PUBLIC
        FILE_SET CXX_MODULES FILES
            string_helpers/string_helpers.cppm
)
target_compile_features(string_helpers PUBLIC cxx_std_23)

# --- main executable ---
add_executable(os main.cpp)
target_compile_features(os PRIVATE cxx_std_23)
target_link_libraries(os PRIVATE string_helpers)