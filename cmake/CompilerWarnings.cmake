# SPDX-License-Identifier: Apache-2.0
# phm_runtime_set_warnings(<target>)
#
# Applies the project warning set to a target. INTERFACE libraries get the
# flags as INTERFACE options, so they reach every translation unit in this
# build that includes their headers; an installed target does not carry them.
function(phm_runtime_set_warnings target)
  set(warnings
    -Wall
    -Wextra
    -Wpedantic
    -Wshadow
    -Wconversion
    -Wsign-conversion
    -Wnon-virtual-dtor
    -Wold-style-cast
    -Woverloaded-virtual
    -Wnull-dereference
    -Wdouble-promotion
    -Wformat=2
  )
  if(PHM_RUNTIME_WARNINGS_AS_ERRORS)
    list(APPEND warnings -Werror)
  endif()

  get_target_property(type ${target} TYPE)
  if(type STREQUAL "INTERFACE_LIBRARY")
    target_compile_options(${target} INTERFACE "$<BUILD_INTERFACE:${warnings}>")
  else()
    target_compile_options(${target} PRIVATE ${warnings})
  endif()
endfunction()
