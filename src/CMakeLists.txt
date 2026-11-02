# SPDX-License-Identifier: Apache-2.0
# The library target phm_edge_runtime (alias phm_edge_runtime::phm_edge_runtime),
# a static library. Public headers live in include/ and are included as
# <phm/runtime/...>; sources and private headers live in this directory and
# include each other as "queue/...".
#
# SQLite 3 (found in the top-level CMakeLists.txt) is linked privately: no
# public header includes <sqlite3.h>. A static library still passes it to the
# consumer's link line, so the installed package configuration finds it too
# (cmake/phm_edge_runtimeConfig.cmake).

add_library(phm_edge_runtime STATIC
  queue/disk_queue.cpp
  queue/schema.cpp
)
add_library(phm_edge_runtime::phm_edge_runtime ALIAS phm_edge_runtime)
target_include_directories(phm_edge_runtime
  PUBLIC
    "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>"
    "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>"
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_compile_features(phm_edge_runtime PUBLIC cxx_std_20)
target_link_libraries(phm_edge_runtime
  PUBLIC Threads::Threads
  PRIVATE ${PHM_RUNTIME_SQLITE_TARGET}
)
phm_runtime_set_warnings(phm_edge_runtime)

# `cmake --install` puts the public headers under <prefix>/include and the
# exported target under <prefix>/lib/cmake/phm_edge_runtime, so a consumer
# uses find_package(phm_edge_runtime CONFIG) and links
# phm_edge_runtime::phm_edge_runtime. The project's warning flags stay out of
# the exported target: they are for this repository's own build.
install(TARGETS phm_edge_runtime EXPORT phm_edge_runtime_targets)
install(DIRECTORY "${PROJECT_SOURCE_DIR}/include/" TYPE INCLUDE)
install(EXPORT phm_edge_runtime_targets
  FILE phm_edge_runtimeTargets.cmake
  NAMESPACE phm_edge_runtime::
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/phm_edge_runtime")
install(FILES "${PROJECT_SOURCE_DIR}/cmake/phm_edge_runtimeConfig.cmake"
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/phm_edge_runtime")
