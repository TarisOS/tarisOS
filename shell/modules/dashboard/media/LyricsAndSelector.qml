// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Layouts
import Quickshell
import Taris.Config
import Taris.I18n
import Taris.Services
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.bottomMargin: -Tokens.spacing.medium
            spacing: Tokens.spacing.medium
            z: 1

            MaterialIcon {
                Layout.topMargin: Math.round(fontInfo.pointSize * 0.12)
                text: "lyrics"
                fontStyle: Tokens.font.icon.medium
            }

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Lyrics")
                font: Tokens.font.title.medium
            }

            LyricsInfo {}
        }

        LyricList {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        // Bongo cat, along to the beat while something plays
        AnimatedImage {
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.sizes.dashboard.mediaSectionWidth / 3
            playing: (Players.active?.isPlaying ?? false) && !root.Tokens.anim.durations.suspended
            speed: Audio.beatTracker.bpm / Config.general.mediaGifSpeedAdjustment // qmllint disable unresolved-type
            source: Paths.absolutePath(Config.paths.mediaGif)
            asynchronous: true
            fillMode: AnimatedImage.PreserveAspectFit
        }
    }

    ServiceRef {
        service: root.visible && !root.Tokens.anim.durations.suspended ? Audio.beatTracker : null
    }
}
