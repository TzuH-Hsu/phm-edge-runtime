# SPDX-License-Identifier: Apache-2.0
# With PHM_RUNTIME_SANITIZE=ON every target in the build is compiled and linked
# with AddressSanitizer and UndefinedBehaviorSanitizer. Undefined behaviour
# aborts the process instead of printing a warning, so ctest reports it as a
# failure.
if(PHM_RUNTIME_SANITIZE)
  add_compile_options(
    -fsanitize=address,undefined
    -fno-sanitize-recover=all
    -fno-omit-frame-pointer
  )
  add_link_options(-fsanitize=address,undefined)
endif()
