// SPDX-License-Identifier: Apache-2.0
// Includes every public header, so each one is compiled with the project
// warnings and checked by clang-tidy even before it has sources.
#include <gtest/gtest.h>

#include <phm/runtime/runtime.hpp>

TEST(Skeleton, PublicHeadersCompile) { SUCCEED(); }
