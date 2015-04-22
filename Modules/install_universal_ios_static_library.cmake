# Copyright (c) 2014, Ruslan Baratov
# All rights reserved.

function(install_universal_ios_static_library destination)
  if(NOT APPLE)
    return()
  endif()

  if(NOT "$ENV{EFFECTIVE_PLATFORM_NAME}" MATCHES iphone)
    return()
  endif()

  if(NOT IS_ABSOLUTE "${destination}")
    message(FATAL_ERROR "`destination` is not absolute")
  endif()

  string(COMPARE EQUAL "${INSTALL_UNIVERSAL_IOS_STATIC_LIBRARY_NAME}" "" is_empty)
  if(is_empty)
    message(FATAL_ERROR "INSTALL_UNIVERSAL_IOS_STATIC_LIBRARY_NAME is empty")
  endif()
  set(target "${INSTALL_UNIVERSAL_IOS_STATIC_LIBRARY_NAME}")

  string(COMPARE EQUAL "${INSTALL_UNIVERSAL_IOS_STATIC_LIBRARY_TOP}" "" is_empty)
  if(is_empty)
    message(FATAL_ERROR "INSTALL_UNIVERSAL_IOS_STATIC_LIBRARY_TOP is empty")
  endif()
  set(work_dir "${INSTALL_UNIVERSAL_IOS_STATIC_LIBRARY_TOP}")

  string(COMPARE EQUAL "${CMAKE_INSTALL_CONFIG_NAME}" "" is_empty)
  if(is_empty)
    message(FATAL_ERROR "CMAKE_INSTALL_CONFIG_NAME is empty")
  endif()
  set(config "${CMAKE_INSTALL_CONFIG_NAME}")

  # Detect architectures
  execute_process(
      COMMAND
      xcodebuild -sdk iphonesimulator -showBuildSettings
      COMMAND
      sed -n "s,.* VALID_ARCHS = ,,p"
      WORKING_DIRECTORY
      "${work_dir}"
      RESULT_VARIABLE result
      OUTPUT_VARIABLE IPHONESIMULATOR_ARCHS
      OUTPUT_STRIP_TRAILING_WHITESPACE
  )

  if(NOT ${result} EQUAL 0)
    message(FATAL_ERROR "xcodebuild failed")
  endif()

  execute_process(
      COMMAND
      xcodebuild -sdk iphoneos -showBuildSettings
      COMMAND
      sed -n "s,.* VALID_ARCHS = ,,p"
      WORKING_DIRECTORY
      "${work_dir}"
      RESULT_VARIABLE result
      OUTPUT_VARIABLE IPHONEOS_ARCHS
      OUTPUT_STRIP_TRAILING_WHITESPACE
  )

  if(NOT ${result} EQUAL 0)
    message(FATAL_ERROR "xcodebuild failed")
  endif()

  # Calculate number of architectures
  # If only one architecture valid no need to build universal library
  # since library already installed
  set(_all_archs "${IPHONESIMULATOR_ARCHS} ${IPHONEOS_ARCHS}")

  # this is space separated string, let's make a CMake list
  string(REPLACE " " ";" _all_archs "${_all_archs}")
  list(REMOVE_ITEM _all_archs "") # remove empty elements
  list(REMOVE_DUPLICATES _all_archs)
  list(LENGTH _all_archs _all_archs_number)
  if(_all_archs_number EQUAL 1)
    message("[iOS universal] Skip: only one valid architecture (${_all_archs})")
    return()
  endif()

  ### Library output name
  execute_process(
      COMMAND
      xcodebuild -showBuildSettings -target "${target}" -configuration "${config}"
      COMMAND
      sed -n "s,.* EXECUTABLE_NAME = ,,p"
      WORKING_DIRECTORY
      "${work_dir}"
      RESULT_VARIABLE result
      OUTPUT_VARIABLE libname
      OUTPUT_STRIP_TRAILING_WHITESPACE
  )

  if(NOT ${result} EQUAL 0)
    message(FATAL_ERROR "xcodebuild failed")
  endif()

  ### Find already installed library (destination of universal library)
  set(library_destination "XXX-NOTFOUND")
  find_file(library_destination ${libname} PATHS "${destination}" NO_DEFAULT_PATH)
  if(NOT library_destination)
    message(FATAL_ERROR "Library `${libname}` not found in `${destination}`")
  endif()

  ### Build iphoneos and iphonesimulator variants
  message(
      STATUS
      "[iOS universal] Build `${target}` for `iphoneos` "
      "(archs: ${IPHONEOS_ARCHS})"
  )

  execute_process(
      COMMAND
      "${CMAKE_COMMAND}"
      --build
      .
      --target "${target}"
      --config ${config}
      --
      -sdk iphoneos
      ONLY_ACTIVE_ARCH=NO
      "ARCHS=${IPHONEOS_ARCHS}"
      WORKING_DIRECTORY
      "${work_dir}"
      RESULT_VARIABLE
      result
  )

  if(NOT ${result} EQUAL 0)
    message(FATAL_ERROR "Build failed")
  endif()

  execute_process(
      COMMAND
      xcodebuild
      -showBuildSettings
      -target
      "${target}"
      -configuration
      "${config}"
      -sdk
      iphoneos
      COMMAND
      sed -n "s,.* CODESIGNING_FOLDER_PATH = ,,p"
      WORKING_DIRECTORY
      "${work_dir}"
      RESULT_VARIABLE result
      OUTPUT_VARIABLE iphoneos_src
      OUTPUT_STRIP_TRAILING_WHITESPACE
  )

  if(NOT ${result} EQUAL 0)
    message(FATAL_ERROR "Xcode failed")
  endif()
  if(NOT EXISTS "${iphoneos_src}")
    message(FATAL_ERROR "${iphoneos_src} not found")
  endif()

  # Fix for targets with forced location. I.e. when ARCHIVE_OUTPUT_DIRECTORY
  # property set both simulator and iphoneos library with have same destination,
  # so each build will rewrite older one. Special directory used to keep
  # intermediate results from overwriting.
  set(_ios_universal_directory "${work_dir}/_3rdParty/ios-universal")

  get_filename_component(_libname "${iphoneos_src}" NAME)

  set(_iphoneos_lib "${_ios_universal_directory}/iphoneos/${_libname}")
  set(_iphonesimulator_lib "${_ios_universal_directory}/iphonesimulator/${_libname}")

  configure_file("${iphoneos_src}" "${_iphoneos_lib}" COPYONLY)

  message(
      STATUS
      "[iOS universal] Done: ${_iphoneos_lib} (from: ${iphoneos_src})"
  )

  message(STATUS "[iOS universal] Build `${target}` for `iphonesimulator`")

  execute_process(
      COMMAND
      "${CMAKE_COMMAND}"
      --build
      .
      --target "${target}"
      --config ${config}
      --
      -sdk iphonesimulator
      ONLY_ACTIVE_ARCH=NO
      "ARCHS=${IPHONESIMULATOR_ARCHS}"
      WORKING_DIRECTORY
      "${work_dir}"
      RESULT_VARIABLE
      result
  )

  if(NOT ${result} EQUAL 0)
    message(FATAL_ERROR "Build failed")
  endif()

  execute_process(
      COMMAND
      xcodebuild
      -showBuildSettings
      -target
      "${target}"
      -configuration
      "${config}"
      -sdk
      iphonesimulator
      COMMAND
      sed -n "s,.* CODESIGNING_FOLDER_PATH = ,,p"
      WORKING_DIRECTORY
      "${work_dir}"
      RESULT_VARIABLE result
      OUTPUT_VARIABLE iphonesimulator_src
      OUTPUT_STRIP_TRAILING_WHITESPACE
  )

  if(NOT ${result} EQUAL 0)
    message(FATAL_ERROR "Xcode failed")
  endif()
  if(NOT EXISTS "${iphonesimulator_src}")
    message(FATAL_ERROR "${iphonesimulator_src} not found")
  endif()

  configure_file("${iphonesimulator_src}" "${_iphonesimulator_lib}" COPYONLY)

  message(
      STATUS
      "[iOS universal] Done: ${_iphonesimulator_lib} "
      "(from: ${iphonesimulator_src}"
  )

  message(STATUS "[iOS universal] simulator: ${_iphonesimulator_lib}")
  message(STATUS "[iOS universal] device: ${_iphoneos_lib}")

  execute_process(
      COMMAND
      lipo
      -create
      "${_iphonesimulator_lib}"
      "${_iphoneos_lib}"
      -output ${library_destination}
      WORKING_DIRECTORY
      "${work_dir}"
      RESULT_VARIABLE result
  )

  if(NOT ${result} EQUAL 0)
    message(FATAL_ERROR "lipo failed")
  endif()

  message(STATUS "[iOS universal] Install done: ${library_destination}")
endfunction()
