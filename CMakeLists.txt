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
include(GNUInstallDirs)
include(CompilerWarnings)
include(Sanitizers)

include(CTest)

# Found here, not in src/, so the tests can link the same imported targets.
find_package(SQLite3 REQUIRED)
# CMake 4.3 renamed FindSQLite3's imported target to SQLite3::SQLite3 and
# deprecated SQLite::SQLite3; older releases (down to the 3.28 minimum) only
# have SQLite::SQLite3.
if(TARGET SQLite3::SQLite3)
  set(PHM_RUNTIME_SQLITE_TARGET SQLite3::SQLite3)
else()
  set(PHM_RUNTIME_SQLITE_TARGET SQLite::SQLite3)
endif()
find_package(Threads REQUIRED)

add_subdirectory(src)

if(BUILD_TESTING)
  include(Dependencies)
  add_subdirectory(tests)
endif()
