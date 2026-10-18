cmake_minimum_required(VERSION 3.21)
# Calc-U-59 Qt6 desktop app — the release build entry point for Windows and
# Linux (.github/workflows/build.yml configures -S Qt6) and the local
# development build on macOS (tools/build_qt.sh). The Mac Qt build is never
# shipped: on macOS the Swift app (Calc-U-59.xcodeproj) is the product.
#
# The app compiles Core/ and Shared/ unchanged — the same sources the Swift
# app and the root CMakeLists.txt (tests) build. No GUI-independent logic
# lives in Qt6/app; see CLAUDE.md § "Frontend Parity".
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.6" CACHE STRING "Minimum macOS version")
project(CalcU59Qt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC OFF)

# Find Homebrew's Qt on macOS if no prefix is configured.
if(APPLE AND NOT DEFINED CMAKE_PREFIX_PATH)
  foreach(prefix /opt/homebrew/opt/qt /usr/local/opt/qt)
    if(EXISTS ${prefix})
      list(APPEND CMAKE_PREFIX_PATH ${prefix})
      break()
    endif()
  endforeach()
endif()

find_package(Qt6 REQUIRED COMPONENTS Widgets)
qt_standard_project_setup()

set(REPO_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/..)
set(CORE_ROOT ${REPO_ROOT}/Core)
set(SHARED_ROOT ${REPO_ROOT}/Shared)

# ---- Version: the single source is the Xcode project's MARKETING_VERSION ----
file(STRINGS ${REPO_ROOT}/Calc-U-59.xcodeproj/project.pbxproj VERSION_LINES REGEX "MARKETING_VERSION = [0-9.]+;")
set(APP_VERSION "0.0.0")
foreach(line ${VERSION_LINES})
  if(line MATCHES "MARKETING_VERSION = ([0-9]+\\.[0-9.]+);")
    set(APP_VERSION ${CMAKE_MATCH_1})
    break()
  endif()
endforeach()

# git describe: a short build id for bug reports ("unknown" without git).
set(APP_BUILD_ID "unknown")
find_package(Git QUIET)
if(GIT_FOUND AND EXISTS ${REPO_ROOT}/.git)
  execute_process(COMMAND ${GIT_EXECUTABLE} describe --always --dirty
                  WORKING_DIRECTORY ${REPO_ROOT}
                  OUTPUT_VARIABLE APP_BUILD_ID_RAW OUTPUT_STRIP_TRAILING_WHITESPACE
                  RESULT_VARIABLE GIT_RESULT ERROR_QUIET)
  if(GIT_RESULT EQUAL 0 AND NOT APP_BUILD_ID_RAW STREQUAL "")
    set(APP_BUILD_ID ${APP_BUILD_ID_RAW})
  endif()
endif()
message(STATUS "Calc-U-59 (Qt) version ${APP_VERSION} build ${APP_BUILD_ID}")

configure_file(${CMAKE_CURRENT_SOURCE_DIR}/app/Version.h.in ${CMAKE_CURRENT_BINARY_DIR}/generated/Version.h @ONLY)
file(CONFIGURE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/generated/Version.iss
     CONTENT "#define APP_VERSION \"@APP_VERSION@\"\n" @ONLY)

file(GLOB SHARED_SOURCES CONFIGURE_DEPENDS ${SHARED_ROOT}/*.cpp)
set(CORE_SOURCES
  ${CORE_ROOT}/TI59Machine.cpp
  ${CORE_ROOT}/TMC0501.cpp
  ${CORE_ROOT}/ROM.cpp
  ${CORE_ROOT}/RAM.cpp
)

qt_add_executable(CalcU59Qt
  MACOSX_BUNDLE
  WIN32
  app/main.cpp
  app/MainWindow.cpp
  app/EmulatorController.cpp
  app/CalculatorPanel.cpp
  app/KeyboardWidget.cpp
  app/LedRenderer.cpp
  app/CueCardRenderer.cpp
  app/ControlBar.cpp
  app/PrinterWidget.cpp
  app/CardPickerDialog.cpp
  app/HoldRepeatButton.cpp
  app/SettingsDialog.cpp
  app/AboutDialog.cpp
  app/AppPaths.cpp
  app/debug/DebugPanel.cpp
  app/debug/LiveDebugWidget.cpp
  app/debug/CpuInspectorWidget.cpp
  app/debug/RomHeatmapWidget.cpp
  app/debug/AsmOverlayBox.cpp
  app/debug/LogWidget.cpp
  ${CORE_SOURCES}
  ${SHARED_SOURCES}
  resources/calc-u-59.qrc
)

# ---- Shared assets, one source, no copies: the ROM text dumps from roms/ and
# the calculator and cue-card artwork from the Swift app's asset catalog ----
file(GLOB ROM_TXT ${REPO_ROOT}/roms/calculator/*.txt ${REPO_ROOT}/roms/solid-state/*.txt)
list(FILTER ROM_TXT EXCLUDE REGEX "/files\\.txt$")
foreach(f ${ROM_TXT})
  get_filename_component(name ${f} NAME)
  set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()
qt_add_resources(CalcU59Qt "roms" PREFIX "/roms" FILES ${ROM_TXT})

set(ARTWORK)
foreach(img ti59_base ti58_base CueCard MagnetCard SolidStateCard)
  set(f ${REPO_ROOT}/App/Assets.xcassets/${img}.imageset/${img}.png)
  set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${img}.png)
  list(APPEND ARTWORK ${f})
endforeach()
qt_add_resources(CalcU59Qt "artwork" PREFIX "/img" FILES ${ARTWORK})

target_include_directories(CalcU59Qt PRIVATE ${CORE_ROOT} ${SHARED_ROOT} app ${CMAKE_CURRENT_BINARY_DIR}/generated)
target_link_libraries(CalcU59Qt PRIVATE Qt6::Widgets)
if(MSVC)
  target_compile_options(CalcU59Qt PRIVATE /W4 /utf-8)  # UTF-8 literals in Shared/
else()
  target_compile_options(CalcU59Qt PRIVATE -Wall -Wextra)
endif()

if(WIN32)
  target_sources(CalcU59Qt PRIVATE resources/windows/calc-u-59.rc)
endif()

if(APPLE)
  # Local development bundle only (never signed, notarized or shipped).
  set(APP_ICON ${CMAKE_CURRENT_SOURCE_DIR}/resources/macos/AppIcon.icns)
  if(EXISTS ${APP_ICON})
    set_source_files_properties(${APP_ICON} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
    target_sources(CalcU59Qt PRIVATE ${APP_ICON})
  endif()
  set_target_properties(CalcU59Qt PROPERTIES
    MACOSX_BUNDLE_ICON_FILE AppIcon
    MACOSX_BUNDLE_GUI_IDENTIFIER ch.erzberger.Calc-U-59-Qt
    MACOSX_BUNDLE_BUNDLE_VERSION ${APP_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${APP_VERSION}
    MACOSX_BUNDLE_BUNDLE_NAME "Calc-U-59"
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/resources/macos/Info.plist.in
  )
endif()

set_target_properties(CalcU59Qt PROPERTIES OUTPUT_NAME "Calc-U-59")

# ---- Install (used by the Windows/Linux packaging jobs) ----
install(TARGETS CalcU59Qt BUNDLE DESTINATION . RUNTIME DESTINATION bin)
