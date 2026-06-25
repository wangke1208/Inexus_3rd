cmake_minimum_required(VERSION 3.16)
project(third_link_test CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT DEFINED THIRD_ROOT)
  set(THIRD_ROOT "${CMAKE_CURRENT_LIST_DIR}/../install/aarch64")
endif()

list(APPEND CMAKE_PREFIX_PATH
    ${THIRD_ROOT}/eigen
    ${THIRD_ROOT}/boost
    ${THIRD_ROOT}/tinyxml2
    ${THIRD_ROOT}/jsoncpp
    ${THIRD_ROOT}/console_bridge
    ${THIRD_ROOT}/urdfdom_headers
    ${THIRD_ROOT}/urdfdom
    ${THIRD_ROOT}/coal
    ${THIRD_ROOT}/eiquadprog
    ${THIRD_ROOT}/pinocchio
    ${THIRD_ROOT}/placo
    /usr/lib/${CMAKE_SYSTEM_PROCESSOR}-linux-gnu
)

set(assimp_DIR "/usr/lib/${CMAKE_SYSTEM_PROCESSOR}-linux-gnu/cmake/assimp-5.3" CACHE PATH "")
set(octomap_DIR "/usr/share/octomap" CACHE PATH "")

add_compile_definitions(COAL_DISABLE_HPP_FCL_WARNINGS)

find_package(Threads REQUIRED)
find_package(Eigen3 REQUIRED)
find_package(pinocchio REQUIRED)
find_package(eiquadprog REQUIRED)
find_package(jsoncpp REQUIRED)

if(TARGET JsonCpp::JsonCpp)
  set(TEST_JSONCPP_LIB JsonCpp::JsonCpp)
elseif(TARGET jsoncpp_static)
  set(TEST_JSONCPP_LIB jsoncpp_static)
else()
  set(TEST_JSONCPP_LIB jsoncpp_lib)
endif()

add_executable(test_link test_link.cpp)
target_compile_definitions(test_link PRIVATE COAL_DISABLE_HPP_FCL_WARNINGS)
target_include_directories(test_link PRIVATE ${THIRD_ROOT}/placo/include)
target_link_libraries(test_link PRIVATE
    ${THIRD_ROOT}/placo/lib/libplaco.a
    pinocchio::pinocchio
    eiquadprog::eiquadprog
    ${TEST_JSONCPP_LIB}
    Threads::Threads
)
