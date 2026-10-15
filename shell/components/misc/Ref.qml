// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick

QtObject {
    required property var service

    Component.onCompleted: service.refCount++
    Component.onDestruction: service.refCount--
}
