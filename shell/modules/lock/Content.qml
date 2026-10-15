// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Layouts
import Taris.Config
import qs.components
import qs.services

RowLayout {
    id: root

    required property var lock

    spacing: Tokens.spacing.largeIncreased * 2

    // The greeter shows the middle column only: its side columns (weather, media, notifications,
    // resources) aren't even made, so nothing of them runs
    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        active: !root.lock.pam.greeter
        visible: active

        sourceComponent: ColumnLayout {
            spacing: Tokens.spacing.medium

            WeatherInfo {
                Layout.fillWidth: true
                rootHeight: root.height
            }

            Fetch {
                Layout.fillWidth: true
                rootHeight: root.height
            }

            Media {
                Layout.fillWidth: true
                Layout.fillHeight: true
                lock: root.lock
            }
        }
    }

    Center {
        Layout.alignment: Qt.AlignHCenter
        lock: root.lock
    }

    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        active: !root.lock.pam.greeter
        visible: active

        sourceComponent: ColumnLayout {
            spacing: Tokens.spacing.medium

            Resources {
                Layout.fillWidth: true
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true

                bottomRightRadius: Tokens.rounding.extraLarge
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainer

                NotifDock {
                    lock: root.lock
                }
            }
        }
    }
}
