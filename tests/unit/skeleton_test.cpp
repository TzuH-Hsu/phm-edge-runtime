// SPDX-License-Identifier: Apache-2.0
// Includes every public header, so each one is compiled with the project
// warnings and checked by clang-tidy on its own.
#include <gtest/gtest.h>

#include <phm/runtime/queue/disk_queue.hpp>
#include <phm/runtime/result.hpp>
#include <phm/runtime/runtime.hpp>

TEST(Skeleton, PublicHeadersCompile) { SUCCEED(); }
