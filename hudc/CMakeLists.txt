cmake_minimum_required(VERSION 3.16)
project(hudc LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt5 REQUIRED COMPONENTS Core Gui Quick Network)

add_executable(hudc
    src/main.cpp
    src/hudmodel.cpp
    src/simulation.cpp
    src/healthworker.cpp
    src/daemonreceiver.cpp
    src/backlightcontroller.cpp
)

target_include_directories(hudc PRIVATE src)

target_link_libraries(hudc
    Qt5::Core
    Qt5::Gui
    Qt5::Quick
    Qt5::Network
    pigpiod_if2
)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()
target_compile_options(hudc PRIVATE
    $<$<CONFIG:Release>:-O2 -march=armv8-a>
)
