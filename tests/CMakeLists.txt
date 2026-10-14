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
