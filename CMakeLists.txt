cmake_minimum_required(VERSION 3.21)

# Development / IDE build of the whole repository: the emulation core, the
# Shared/ C++ layer both frontends use, the C++ test suite (CTest), the
# headless harness library, and — when Qt6 is found — the Qt6 desktop app
# via add_subdirectory(Qt6).
#
# The Swift app is built by Calc-U-59.xcodeproj, which compiles the same
# Core/ and Shared/ sources (synchronized folders). Every Core/ or Shared/
# change must pass both builds — see CLAUDE.md § "Frontend Parity".

project(Calc-U-59 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CORE_ROOT   ${CMAKE_CURRENT_SOURCE_DIR}/Core)
set(SHARED_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/Shared)

if(MSVC)
  # /utf-8: Shared/ has UTF-8 string literals (cue-card math tokens, mnemonics).
  set(CALCU59_WARNINGS /W4 /utf-8)
else()
  set(CALCU59_WARNINGS -Wall -Wextra)
endif()

# -----------------------------------------------------------------------------
# Core (hardware emulation) and Shared (frontend-neutral logic above it)
# -----------------------------------------------------------------------------
add_library(calcu59_core STATIC
  ${CORE_ROOT}/TI59Machine.cpp
  ${CORE_ROOT}/TMC0501.cpp
  ${CORE_ROOT}/ROM.cpp
  ${CORE_ROOT}/RAM.cpp
)
target_include_directories(calcu59_core PUBLIC ${CORE_ROOT})
target_compile_options(calcu59_core PRIVATE ${CALCU59_WARNINGS})
set_target_properties(calcu59_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
find_package(Threads REQUIRED)
target_link_libraries(calcu59_core PUBLIC Threads::Threads)

file(GLOB SHARED_SOURCES CONFIGURE_DEPENDS ${SHARED_ROOT}/*.cpp)
add_library(calcu59_shared STATIC ${SHARED_SOURCES})
target_include_directories(calcu59_shared PUBLIC ${SHARED_ROOT})
target_link_libraries(calcu59_shared PUBLIC calcu59_core)
target_compile_options(calcu59_shared PRIVATE ${CALCU59_WARNINGS})

# -----------------------------------------------------------------------------
# Headless harness (tools/headless/ti59.py loads it via ctypes; build.sh does
# the same with one clang++ call)
# -----------------------------------------------------------------------------
add_library(ti59headless SHARED ${CMAKE_CURRENT_SOURCE_DIR}/tools/headless/capi.cpp)
target_link_libraries(ti59headless PRIVATE calcu59_core)

# -----------------------------------------------------------------------------
# Tests: run from the repository root so they can read roms/ and examples/
# -----------------------------------------------------------------------------
file(GLOB TEST_SOURCES CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/tests/*.cpp)
add_executable(CalcU59Tests ${TEST_SOURCES})
target_link_libraries(CalcU59Tests PRIVATE calcu59_shared)
target_compile_options(CalcU59Tests PRIVATE ${CALCU59_WARNINGS})
if(NOT MSVC)
  # The ROM-driven tests run millions of steps; keep Debug builds usable.
  target_compile_options(CalcU59Tests PRIVATE $<$<CONFIG:Debug>:-O1>)
  target_compile_options(calcu59_core PRIVATE $<$<CONFIG:Debug>:-O1>)
endif()

enable_testing()
file(MAKE_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/build)  # scratch files written by the tests
add_test(NAME CalcU59Tests COMMAND CalcU59Tests WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
# tools/read_trace.py must read the trace CalcU59Tests wrote with Shared/TraceWriter.
find_package(Python3 COMPONENTS Interpreter)
if(Python3_FOUND)
  add_test(NAME CalcU59TraceReader
           COMMAND ${Python3_EXECUTABLE} tools/read_trace.py --json build/trace-test.bin
           WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
  set_tests_properties(CalcU59TraceReader PROPERTIES DEPENDS CalcU59Tests)
endif()

# -----------------------------------------------------------------------------
# Qt6 desktop app (optional: Core/Shared/tests build without Qt)
# -----------------------------------------------------------------------------
# Qt6/CMakeLists.txt stays the release entry point (CI configures -S Qt6);
# this only pulls the same directory in for IDEs and local development.
option(CALCU59_BUILD_QT "Build the Qt6 desktop app when Qt6 is available" ON)
if(CALCU59_BUILD_QT)
  if(APPLE AND NOT DEFINED CMAKE_PREFIX_PATH AND EXISTS /opt/homebrew/opt/qt)
    list(APPEND CMAKE_PREFIX_PATH /opt/homebrew/opt/qt)
  endif()
  find_package(Qt6 QUIET COMPONENTS Widgets)
  if(Qt6_FOUND)
    add_subdirectory(Qt6)
  else()
    message(STATUS "Qt6 not found: building Core, Shared and the tests only")
  endif()
endif()
