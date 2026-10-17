cmake_minimum_required(VERSION 3.10)
project(hashforge_cpp CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(hashforge-cpp main.cpp)

if(WIN32)
    target_link_libraries(hashforge-cpp advapi32)
else()
    find_package(OpenSSL REQUIRED)
    target_link_libraries(hashforge-cpp OpenSSL::Crypto)
endif()

