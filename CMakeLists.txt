cmake_minimum_required(VERSION 3.20)
project(ComparePlus LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)

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
set(PLUGIN_INSTALL_DIR "$ENV{HOME}/.notepad++/plugins/ComparePlus")
install(TARGETS ComparePlus DESTINATION "${PLUGIN_INSTALL_DIR}")
