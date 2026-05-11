cmake_minimum_required(VERSION 3.20)
project(ComparePlus LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")

# Paths to shared headers
set(NPP_MACOS_DIR "${CMAKE_SOURCE_DIR}/../../notepad-plus-plus-macos")
set(NPP_WIN_DIR "${CMAKE_SOURCE_DIR}/../../notepad-plus-plus")
set(SCINTILLA_INCLUDE "${NPP_WIN_DIR}/scintilla/include")
set(NPP_PLUGIN_INCLUDE "${NPP_MACOS_DIR}/src")

add_library(ComparePlus SHARED
    src/ComparePlus.mm
    src/Engine/Engine.cpp
    src/CompareSettings.mm
    src/CompareHelpers.mm
    src/CompareTools.mm
    src/EngineBridge.mm
)

target_include_directories(ComparePlus PRIVATE
    ${NPP_PLUGIN_INCLUDE}
    ${SCINTILLA_INCLUDE}
    src
    src/Engine
)

target_compile_definitions(ComparePlus PRIVATE
    MULTITHREAD=1
)

target_link_libraries(ComparePlus PRIVATE
    "-framework Cocoa"
    "-framework Security"
)

set_target_properties(ComparePlus PROPERTIES
    PREFIX ""
    SUFFIX ".dylib"
    OUTPUT_NAME "ComparePlus"
)

# Install target
set(PLUGIN_INSTALL_DIR "$ENV{HOME}/.nextpad++/plugins/ComparePlus")
install(TARGETS ComparePlus DESTINATION "${PLUGIN_INSTALL_DIR}")

# Toolbar icons. The plugin source passes bare filenames (e.g.
# "Compare.png") to NPPM_ADDTOOLBARICON_FORDARKMODE, so the host
# resolves them relative to the plugin's install directory. Install
# both light and dark sets flat at the plugin root; the host picks
# the matching variant based on macOS appearance.
file(GLOB COMPAREPLUS_LIGHT_ICONS "${CMAKE_SOURCE_DIR}/res/icons/light/*.png")
file(GLOB COMPAREPLUS_DARK_ICONS  "${CMAKE_SOURCE_DIR}/res/icons/dark/*.png")
install(FILES ${COMPAREPLUS_LIGHT_ICONS} ${COMPAREPLUS_DARK_ICONS}
        DESTINATION "${PLUGIN_INSTALL_DIR}")
