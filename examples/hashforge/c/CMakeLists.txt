cmake_minimum_required(VERSION 3.10)
project(hashforge_c C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_executable(hashforge-c main.c)

if(WIN32)
    target_link_libraries(hashforge-c advapi32)
else()
    find_package(OpenSSL REQUIRED)
    target_link_libraries(hashforge-c OpenSSL::Crypto)
endif()
