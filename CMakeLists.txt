cmake_minimum_required(VERSION 3.16)
# Builds a Cocoa/Sparkle updater .app for one of the two toolchain products.
#   -DMAVGO_VARIANT=native (default): updates the NATIVE .pkg; x86_64/min-10.9 (runs on the 10.9 box).
#   -DMAVGO_VARIANT=cross           : updates the CROSS .pkg; native arm64/min-11 (runs on the dev Mac).
# Each links the matching Sparkle slice, derived automatically from CMAKE_OSX_ARCHITECTURES by
# mavericks_add_updater_app. Cocoa/ObjC only (no Go). Native + cross use SEPARATE build dirs.
set(MAVGO_VARIANT "native" CACHE STRING "which product this updater updates: native | cross")

if(MAVGO_VARIANT STREQUAL "native")
  set(CMAKE_OSX_DEPLOYMENT_TARGET 10.9 CACHE STRING "native updater runs on 10.9")
  set(CMAKE_OSX_ARCHITECTURES x86_64 CACHE STRING "Intel-only (10.9)")
elseif(MAVGO_VARIANT STREQUAL "cross")
  set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0 CACHE STRING "arm64 macOS floor")
  set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "native Apple Silicon")
else()
  message(FATAL_ERROR "MAVGO_VARIANT must be 'native' or 'cross' (got '${MAVGO_VARIANT}')")
endif()

project(GoUpdater LANGUAGES OBJC)

find_package(MavericksShipyard REQUIRED)
include(Mavericks)          # universal umbrella: AppleClang gate + build conventions
include(MavericksSparkle)   # the Sparkle updater .app builder

file(STRINGS "${CMAKE_SOURCE_DIR}/VERSION" MAVGO_VERSION LIMIT_COUNT 1)

# A Go MINOR LINE is a product: go126 and a future go127 install side by side, each with its own
# prefix, identifiers and UPDATE FEED. Deriving the line from the version keeps the updater's feed,
# the paths it names, and the product title honest when a new line appears.
string(REGEX REPLACE "^([0-9]+)\\.([0-9]+)\\..*$" "\\1\\2" MAVGO_LINE "${MAVGO_VERSION}")
string(REGEX REPLACE "^([0-9]+)\\.([0-9]+)\\..*$" "\\1.\\2" MAVGO_MINOR "${MAVGO_VERSION}")
if(NOT MAVGO_LINE MATCHES "^[0-9]+$")
  message(FATAL_ERROR "cannot derive the Go line from VERSION '${MAVGO_VERSION}'")
endif()

if(MAVGO_VARIANT STREQUAL "native")
  set(_name       GoUpdater)
  set(_product    "Mavericks Go ${MAVGO_MINOR}")
  set(_bundle     dev.mavergreen.GoUpdater)
  # Per-LINE feed, not /latest/: installed updaters poll `feed-126`, so the URL must never
  # change. A future Go line lives in its own repo with its own feed, not a second line here.
  set(_feed       "https://github.com/Mavergreen/golang/releases/download/feed-${MAVGO_LINE}/appcast.xml")
  set(_logprefix  "MavGoUpdater")
  set(_confirmbody "The Go toolchain in /usr/local/go${MAVGO_LINE} was updated.")
  set(_relaunch   "/tmp/.mavericks-go-updater-relaunched")
else()
  set(_name       GoCrossUpdater)
  set(_product    "Mavericks Go ${MAVGO_MINOR} (cross)")
  set(_bundle     dev.mavergreen.GoCrossUpdater)
  set(_feed       "https://github.com/Mavergreen/golang/releases/download/feed-${MAVGO_LINE}/appcast-cross.xml")
  set(_logprefix  "MavGoCrossUpdater")
  set(_confirmbody "The cross toolchain in /usr/local/go${MAVGO_LINE}-cross was updated.")
  set(_relaunch   "/tmp/.mavericks-go-cross-updater-relaunched")
endif()

mavericks_add_updater_app(
  NAME ${_name}
  PRODUCT_NAME "${_product}"
  BUNDLE_ID ${_bundle}
  FEED_URL "${_feed}"
  ICON "${CMAKE_SOURCE_DIR}/updater/mavericks-go-updater.icns"
  VERSION "${MAVGO_VERSION}"
  LOG_PREFIX "${_logprefix}"
  CONFIRM_TITLE "${_product} updated"
  CONFIRM_BODY "${_confirmbody}"
  RELAUNCH_MARKER "${_relaunch}"
  # no PANE_HINT_KEY -> background-found updates post an NSUserNotification (CLI toolchain, no pane)
)
