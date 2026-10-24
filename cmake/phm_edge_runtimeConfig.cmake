# SPDX-License-Identifier: Apache-2.0
# Package configuration installed with the library. The static library links
# SQLite 3 and the platform thread library, so a consumer's find_package of
# this package finds both before it imports the target.
include(CMakeFindDependencyMacro)
find_dependency(SQLite3)
find_dependency(Threads)

# FindSQLite3 names its target SQLite3::SQLite3 from CMake 4.3 on and
# SQLite::SQLite3 before; the library may have been built with either.
if(TARGET SQLite::SQLite3 AND NOT TARGET SQLite3::SQLite3)
  add_library(SQLite3::SQLite3 ALIAS SQLite::SQLite3)
elseif(TARGET SQLite3::SQLite3 AND NOT TARGET SQLite::SQLite3)
  add_library(SQLite::SQLite3 ALIAS SQLite3::SQLite3)
endif()

include("${CMAKE_CURRENT_LIST_DIR}/phm_edge_runtimeTargets.cmake")
