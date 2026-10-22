// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick

// Holds a service on (its refCount) while it exists and is active: a part that's kept while hidden
// (a panel kept loaded) lets go of it while it isn't shown
QtObject {
    id: root

    required property var service
    property bool active: true
    property bool counted

    function sync(): void {
        if (!service)
            return;
        if (active && !counted) {
            service.refCount++;
            counted = true;
        } else if (!active && counted) {
            service.refCount--;
            counted = false;
        }
    }

    onActiveChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: {
        if (counted)
            service.refCount--;
    }
}
