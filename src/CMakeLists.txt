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
target_include_directories(phm_edge_runtime INTERFACE
  "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>"
  "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>")
target_compile_features(phm_edge_runtime INTERFACE cxx_std_20)
phm_runtime_set_warnings(phm_edge_runtime)

# `cmake --install` puts the public headers under <prefix>/include and the
# exported target under <prefix>/lib/cmake/phm_edge_runtime, so a consumer
# uses find_package(phm_edge_runtime CONFIG) and links
# phm_edge_runtime::phm_edge_runtime. The project's warning flags stay out of
# the exported target: they are for this repository's own build.
install(TARGETS phm_edge_runtime EXPORT phm_edge_runtime_targets)
install(DIRECTORY "${PROJECT_SOURCE_DIR}/include/" TYPE INCLUDE)
install(EXPORT phm_edge_runtime_targets
  FILE phm_edge_runtimeConfig.cmake
  NAMESPACE phm_edge_runtime::
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/phm_edge_runtime")
