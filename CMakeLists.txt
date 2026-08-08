cmake_minimum_required(VERSION 3.28)
project(os LANGUAGES CXX)

# Require C++23
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Generate compile_commands.json
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# --- point module ---
add_library(point
    point/point.cpp
)
target_include_directories(point PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(point PUBLIC cxx_std_23)

# --- string_helpers module ---
add_library(string_helpers
    string_helpers/string_helpers.cpp
)
target_include_directories(string_helpers PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/string_helpers)
target_compile_features(string_helpers PUBLIC cxx_std_23)

# --- component module ---
add_library(component
    component/component.cpp
)
target_include_directories(component PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/component)
target_compile_features(component PUBLIC cxx_std_23)

# --- desktop module ---
add_library(desktop
    component/desktop/desktop.cpp
)
target_include_directories(desktop PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/component/desktop)
target_compile_features(desktop PUBLIC cxx_std_23)

# --- graphics module ---
add_library(graphics
    graphics/graphics.cpp
)
target_include_directories(graphics PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/graphics)
target_compile_features(graphics PUBLIC cxx_std_23)
target_link_libraries(graphics PUBLIC point component)

# --- main executable ---
add_executable(os main.cpp)
target_compile_features(os PRIVATE cxx_std_23)
target_link_libraries(os PRIVATE string_helpers graphics desktop)