cmake_minimum_required(VERSION 3.16)
project(dc_bench VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(BUILD_HOMA "Build Homa benchmark (requires HomaModule headers)" OFF)

add_library(dc_common STATIC
    src/statistics.cpp
    src/workload.cpp
    src/cpu_monitor.cpp
)
target_include_directories(dc_common PUBLIC include)
target_link_libraries(dc_common PUBLIC pthread)

add_library(dc_tcp STATIC
    src/connection_pool.cpp
    src/priority_scheduler.cpp
    src/tcp_server.cpp
    src/tcp_client.cpp
)
target_include_directories(dc_tcp PUBLIC include)
target_link_libraries(dc_tcp PUBLIC dc_common)

add_executable(tcp_bench src/tcp_bench.cpp)
target_link_libraries(tcp_bench PRIVATE dc_tcp dc_common)

if(BUILD_HOMA)
    add_library(dc_homa STATIC
        src/homa_api.cpp
        src/homa_server.cpp
        src/homa_client.cpp
    )
    target_include_directories(dc_homa PUBLIC include)
    target_link_libraries(dc_homa PUBLIC dc_common)

    if(DEFINED HOMA_INCLUDE_DIR)
        target_include_directories(dc_homa PUBLIC ${HOMA_INCLUDE_DIR})
    endif()

    add_executable(homa_bench src/homa_bench.cpp)
    target_link_libraries(homa_bench PRIVATE dc_homa dc_common)
endif()
