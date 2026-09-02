cmake_minimum_required(VERSION 3.17)

project(
    wuxia-duel-native
    VERSION 0.1.0
    DESCRIPTION "Experimental native compact-state kernel for Wuxia Card"
    LANGUAGES CXX
)

set(GODOTCPP_API_VERSION "4.7" CACHE STRING "Godot extension API version")
set(GODOTCPP_TARGET "template_debug" CACHE STRING "godot-cpp target")
set(GODOTCPP_ENABLE_TESTING OFF CACHE BOOL "Disable godot-cpp tests" FORCE)
set(GODOTCPP_USE_HOT_RELOAD OFF CACHE BOOL "Disable hot reload accounting" FORCE)

add_subdirectory(godot-cpp)

set(TARGET_NAME "wuxia-duel-native")
add_library(${TARGET_NAME} SHARED)
target_sources(
    ${TARGET_NAME}
    PRIVATE
        src/duel_native_compact_kernel.cpp
        src/duel_native_compact_kernel.h
        src/register_types.cpp
        src/register_types.h
)
target_link_libraries(${TARGET_NAME} PRIVATE godot-cpp)

get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)
set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bin")
if(ANDROID)
    set(DUEL_NATIVE_PREFIX "lib")
else()
    set(DUEL_NATIVE_PREFIX "")
endif()
set_target_properties(
    ${TARGET_NAME}
    PROPERTIES
        CXX_STANDARD 17
        CXX_EXTENSIONS OFF
        CXX_VISIBILITY_PRESET ${GODOTCPP_SYMBOL_VISIBILITY}
        POSITION_INDEPENDENT_CODE ON
        LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        PDB_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        PREFIX "${DUEL_NATIVE_PREFIX}"
        OUTPUT_NAME "duel_native${GODOTCPP_SUFFIX}"
)

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/duel_native.gdextension.in"
    "${OUTPUT_DIR}/duel_native.gdextension"
    COPYONLY
)
