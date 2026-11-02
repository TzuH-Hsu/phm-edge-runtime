# SPDX-License-Identifier: Apache-2.0
# phm_runtime_add_unit_test(<name> SOURCES <file>... [LIBS <target>...])
#
# Builds a GoogleTest executable and registers each of its tests with ctest,
# named <Suite>.<Test>, so `make test-one TEST=<regex>` can select them.
function(phm_runtime_add_unit_test name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "" "SOURCES;LIBS")
  add_executable(${name} ${arg_SOURCES})
  target_link_libraries(${name} PRIVATE ${arg_LIBS} GTest::gtest_main)
  phm_runtime_set_warnings(${name})
  gtest_discover_tests(${name} DISCOVERY_MODE PRE_TEST)
endfunction()

phm_runtime_add_unit_test(skeleton_test
  SOURCES unit/skeleton_test.cpp
  LIBS phm_edge_runtime::phm_edge_runtime
)

# The disk queue tests use the SQLite C API next to the queue (a second
# connection, fixture databases) and the private schema header.
foreach(test_name disk_queue_test disk_queue_schema_test)
  phm_runtime_add_unit_test(${test_name}
    SOURCES unit/${test_name}.cpp
    LIBS phm_edge_runtime::phm_edge_runtime ${PHM_RUNTIME_SQLITE_TARGET}
  )
  target_include_directories(${test_name} PRIVATE "${PROJECT_SOURCE_DIR}/src")
  target_compile_definitions(${test_name} PRIVATE
    PHM_RUNTIME_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures")
endforeach()
