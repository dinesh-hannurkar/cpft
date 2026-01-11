cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME wifi_connector)

project(${PROJECT_NAME} LANGUAGES CXX)

add_library(${PROJECT_NAME} SHARED
    "shared/wifi_connector_plugin.cpp"
    "shared/wifi_service.cpp"
)

target_include_directories(${PROJECT_NAME} PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/include"
)

target_link_libraries(${PROJECT_NAME} PRIVATE
    flutter
    wlanapi
)

apply_standard_settings(${PROJECT_NAME})
