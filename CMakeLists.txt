# SPDX-License-Identifier: Apache-2.0
cmake_minimum_required(VERSION 3.28...4.3)

project(phm_edge_runtime LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# No C++20 modules are used. Scanning for them adds GCC-only flags to
# compile_commands.json, which clang-tidy cannot parse.
set(CMAKE_CXX_SCAN_FOR_MODULES OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(PHM_RUNTIME_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)
option(PHM_RUNTIME_SANITIZE "Build with AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")
include(CompilerWarnings)
include(Sanitizers)

include(CTest)

add_subdirectory(src)

if(BUILD_TESTING)
  include(Dependencies)
  add_subdirectory(tests)
endif()
