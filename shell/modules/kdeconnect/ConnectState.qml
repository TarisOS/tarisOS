// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell

// What a KDE Connect view shows: the device picked in its list (remembered by ConnectWindow, as
// the view is made again after the file picker has been over it)
QtObject {
    property ShellScreen screen
    property bool isWindow
    property bool animatingContainer

    property string deviceId: ConnectWindow.deviceId

    signal close

    onDeviceIdChanged: ConnectWindow.deviceId = deviceId
}
