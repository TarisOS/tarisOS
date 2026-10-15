// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell
import Taris.Images

Image {
    id: root

    property string path

    asynchronous: true
    fillMode: Image.PreserveAspectCrop
    source: IUtils.urlForPath(path, fillMode)
    // In points: Qt asks for it at the screen's scale itself (multiplying by the scale here as well
    // decoded and cached every image at twice the resolution it shows at, 4x the memory)
    sourceSize: Qt.size(width, height)
}
