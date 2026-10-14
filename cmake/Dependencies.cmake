# SPDX-License-Identifier: Apache-2.0
# Third-party dependencies of the test build.
#
# GoogleTest is a test-only dependency: it is not linked into the library and
# is not delivered with it. An installed GoogleTest of the pinned version (for
# example from an SDK sysroot) is used when present; otherwise the release
# archive is downloaded and verified against the hash below. A sanitized build
# always builds GoogleTest from source, so the test framework is instrumented
# like the code under test.
include(FetchContent)

if(PHM_RUNTIME_SANITIZE)
  set(FETCHCONTENT_TRY_FIND_PACKAGE_MODE NEVER)
endif()

set(PHM_RUNTIME_GTEST_VERSION 1.17.0)

FetchContent_Declare(
  googletest
  URL https://github.com/google/googletest/releases/download/v${PHM_RUNTIME_GTEST_VERSION}/googletest-${PHM_RUNTIME_GTEST_VERSION}.tar.gz
  URL_HASH SHA256=65fab701d9829d38cb77c14acdc431d2108bfdbf8979e40eb8ae567edf10b27c
  DOWNLOAD_EXTRACT_TIMESTAMP ON
  FIND_PACKAGE_ARGS ${PHM_RUNTIME_GTEST_VERSION} EXACT NAMES GTest
)

set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
set(BUILD_GMOCK ON CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(googletest)

include(GoogleTest)
