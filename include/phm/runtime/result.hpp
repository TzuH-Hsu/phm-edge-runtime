// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdlib>
#include <utility>
#include <variant>

namespace phm::runtime {

// Wraps an error so it can initialise a Result (the C++20 stand-in for
// std::unexpected).
template <typename E>
struct Unexpected {
  E error;
};

// Either a value or an error. A C++20 stand-in for std::expected<T, E> with
// the same member names, so it can become an alias once the library moves to
// C++23. Never throws: value() on an error, or error() on a value, aborts.
template <typename T, typename E>
class [[nodiscard]] Result {
 public:
  Result(T value)  // NOLINT(google-explicit-constructor,hicpp-explicit-conversions)
      : state_(std::in_place_index<0>, std::move(value)) {}
  Result(Unexpected<E> failure)  // NOLINT(google-explicit-constructor,hicpp-explicit-conversions)
      : state_(std::in_place_index<1>, std::move(failure.error)) {}

  [[nodiscard]] bool has_value() const noexcept { return state_.index() == 0; }
  explicit operator bool() const noexcept { return has_value(); }

  [[nodiscard]] T& value() & {
    require_value();
    return *std::get_if<0>(&state_);
  }
  [[nodiscard]] const T& value() const& {
    require_value();
    return *std::get_if<0>(&state_);
  }
  [[nodiscard]] T&& value() && {
    require_value();
    return std::move(*std::get_if<0>(&state_));
  }
  [[nodiscard]] const E& error() const& {
    if (has_value()) {
      std::abort();
    }
    return *std::get_if<1>(&state_);
  }

 private:
  void require_value() const noexcept {
    if (!has_value()) {
      std::abort();
    }
  }

  std::variant<T, E> state_;
};

}  // namespace phm::runtime
