# SPDX-License-Identifier: Apache-2.0
# The library target phm_edge_runtime (alias phm_edge_runtime::phm_edge_runtime).
# Public headers live in include/ and are included as <phm/runtime/...>;
# sources live in this directory. While the library only declares interfaces
# it is an INTERFACE library; the first source file turns it into a static
# library:
#
#   add_library(phm_edge_runtime STATIC disk_queue.cpp)
#   ... and every INTERFACE below becomes PUBLIC.
add_library(phm_edge_runtime INTERFACE)
add_library(phm_edge_runtime::phm_edge_runtime ALIAS phm_edge_runtime)
target_include_directories(phm_edge_runtime INTERFACE "${PROJECT_SOURCE_DIR}/include")
target_compile_features(phm_edge_runtime INTERFACE cxx_std_20)
phm_runtime_set_warnings(phm_edge_runtime)
