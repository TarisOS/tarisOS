# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

cmake_minimum_required(VERSION 3.19)

if(NOT DEFINED VERSION)
    execute_process(COMMAND git describe --tags --abbrev=0
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        OUTPUT_VARIABLE VERSION
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )

    if("${VERSION}" STREQUAL "")
        message(FATAL_ERROR "VERSION is not set and failed to get from git")
    endif()
endif()

if(NOT DEFINED GIT_REVISION)
    execute_process(COMMAND git rev-parse HEAD
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        OUTPUT_VARIABLE GIT_REVISION
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )

    if("${GIT_REVISION}" STREQUAL "")
        message(FATAL_ERROR "GIT_REVISION is not set and failed to get from git")
    endif()
endif()

string(REGEX REPLACE "^v" "" VERSION "${VERSION}")

project(taris-shell VERSION ${VERSION} LANGUAGES CXX)

include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

set(DISTRIBUTOR "Unset" CACHE STRING "Distributor")
set(ENABLE_MODULES "extras;plugin;shell" CACHE STRING "Modules to build/install")
set(INSTALL_LIBDIR "${CMAKE_INSTALL_LIBDIR}/taris" CACHE STRING "Library install dir")
set(INSTALL_QMLDIR "${CMAKE_INSTALL_LIBDIR}/qt6/qml" CACHE STRING "QML install dir")
set(INSTALL_QSCONFDIR "${CMAKE_INSTALL_SYSCONFDIR}/xdg/quickshell/taris" CACHE STRING "Quickshell config install dir")

add_compile_definitions(
    QT_NO_CAST_FROM_ASCII
    QT_NO_CAST_TO_ASCII
    QT_NO_CAST_FROM_BYTEARRAY
)

add_compile_options(
    -Wall -Wextra -Wpedantic -Wshadow -Wconversion
    -Wold-style-cast -Wnull-dereference -Wdouble-promotion
    -Wformat=2 -Wfloat-equal -Woverloaded-virtual
    -Wsign-conversion -Wredundant-decls -Wswitch
    -Wunreachable-code
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    add_compile_options(-Wunused-lambda-capture -Wno-nonportable-include-path)
endif()

if("extras" IN_LIST ENABLE_MODULES)
    add_subdirectory(extras)
endif()

if("plugin" IN_LIST ENABLE_MODULES)
    add_subdirectory(plugin)
endif()

if("shell" IN_LIST ENABLE_MODULES)
    foreach(dir assets components modules services utils)
        install(DIRECTORY ${dir} DESTINATION "${INSTALL_QSCONFDIR}")
    endforeach()

    install(PROGRAMS assets/wrap_term_launch.sh assets/fans.py assets/remove-app.sh assets/install-webapp.sh assets/launch-webapp.sh assets/store.py
        assets/scheme-overrides.py assets/portal-filechooser.py assets/stash.py
        DESTINATION "${INSTALL_QSCONFDIR}/assets")

    # Taris's file picker for every app that asks the desktop for one: an xdg-desktop-portal
    # FileChooser backend, started by D-Bus (install.sh points the portal's FileChooser at it)
    file(WRITE "${CMAKE_BINARY_DIR}/org.freedesktop.impl.portal.desktop.taris.service"
        "[D-BUS Service]\nName=org.freedesktop.impl.portal.desktop.taris\nExec=/usr/bin/python3 -I /${INSTALL_QSCONFDIR}/assets/portal-filechooser.py\n")
    install(FILES "${CMAKE_BINARY_DIR}/org.freedesktop.impl.portal.desktop.taris.service"
        DESTINATION "${CMAKE_INSTALL_DATADIR}/dbus-1/services")
    install(FILES assets/taris.portal DESTINATION "${CMAKE_INSTALL_DATADIR}/xdg-desktop-portal/portals")
    install(PROGRAMS assets/settings/dns.sh DESTINATION "${INSTALL_QSCONFDIR}/assets/settings")
    install(PROGRAMS assets/agent/launch.sh assets/agent/install.sh assets/agent/usage-update.sh assets/agent/usage-claude.py
        assets/agent/usage-codex.py DESTINATION "${INSTALL_QSCONFDIR}/assets/agent")

    # Settings as an app: the dock shows Taris's windows as this entry, and launches it to reopen them
    install(FILES assets/taris-settings.desktop DESTINATION "${CMAKE_INSTALL_DATADIR}/applications")
    install(FILES assets/taris-store.desktop DESTINATION "${CMAKE_INSTALL_DATADIR}/applications")
    install(FILES assets/taris-kdeconnect.desktop DESTINATION "${CMAKE_INSTALL_DATADIR}/applications")
    install(FILES assets/taris-nordvpn.desktop DESTINATION "${CMAKE_INSTALL_DATADIR}/applications")

    file(READ shell.qml SHELL_QML)
    string(REPLACE "settings.watchFiles: true" "settings.watchFiles: false" SHELL_QML "${SHELL_QML}")
    file(WRITE "${CMAKE_BINARY_DIR}/qml/shell.qml" "${SHELL_QML}")
    install(FILES "${CMAKE_BINARY_DIR}/qml/shell.qml" DESTINATION "${INSTALL_QSCONFDIR}")
    # The greeter and the first-boot setup screen (taris-login runs them through greetd)
    install(FILES greeter.qml setup.qml DESTINATION "${INSTALL_QSCONFDIR}")

    install(FILES LICENSE DESTINATION "${INSTALL_QSCONFDIR}")
endif()
