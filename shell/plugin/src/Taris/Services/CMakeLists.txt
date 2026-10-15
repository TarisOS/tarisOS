# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

qml_module(taris-services
    URI Taris.Services
    SOURCES
        service.cpp
        serviceref.cpp
        beattracker.cpp
        audiocollector.cpp
        audioprovider.cpp
        cavaprovider.cpp
        tickingservice.cpp
        sensorslib.cpp
        cpu.cpp
        gpu.cpp
        memory.cpp
        diskinfo.cpp
        storage.cpp
        lyriccandidate.cpp
        lyrics.cpp
        sessionmanager.cpp
        networkusage.cpp
        hyprdevices.cpp
        hyprextras.cpp
        kdeconnect.cpp
    LIBRARIES
        Qt::Concurrent
        Qt::DBus
        Qt::Network
        PkgConfig::Pipewire
        PkgConfig::Aubio
        PkgConfig::Cava
        Sensors::Sensors
        taris-util
        taris-core
        taris-config
    DEPENDENCIES
        Taris
        Taris.Config
)
