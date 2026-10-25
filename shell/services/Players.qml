// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton
pragma ComponentBehavior: Bound

import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Taris
import Taris.Config
import Taris.I18n
import qs.components.misc

Singleton {
    id: root

    readonly property list<MprisPlayer> list: Mpris.players.values
    /*
     * The player the media keys, the Touch Bar and the dashboard act on. It follows playback
     * (`follow`): the one that has been playing longest keeps it while others start, and once it
     * pauses or stops it goes to what is still playing. While nothing plays it stays on the last
     * one, so play resumes what was just paused. Before anything has played: the default player,
     * else the first.
     */
    readonly property MprisPlayer active: (list.includes(props.manualActive) ? props.manualActive : null) ?? list.find(p => p.isPlaying) ?? list.find(p => isDefault(p)) ?? list[0] ?? null
    // Moved by `follow`, and by hand from the dashboard's player menu and the mediaSwitch shortcut
    property alias manualActive: props.manualActive
    // When each playing player started, by D-Bus name: the one playing longest keeps the controls
    property var playingSince: ({})

    // Dedup key for progressive metadata (e.g. mpv-mpris/yt-dlp player fills title then artist later).
    property string lastNowPlayingKey: ""

    function getIdentity(player: MprisPlayer): string {
        if (!player)
            return "";
        const alias = GlobalConfig.services.playerAliases.values.find(a => a.from === player.identity);
        return alias?.to ?? player.identity;
    }

    // The default player, set either as its own name (`Music`) or as shown (`Taris Music`)
    function isDefault(player: MprisPlayer): bool {
        const preferred = GlobalConfig.services.defaultPlayer;
        return !!player && !!preferred && (player.identity === preferred || getIdentity(player) === preferred);
    }

    // Moves the controls along with playback; see `active`
    function follow(): void {
        const now = Date.now();
        const since = {};
        for (const player of list) {
            if (player.isPlaying)
                since[player.dbusName] = playingSince[player.dbusName] ?? now;
        }
        playingSince = since;

        if (active?.isPlaying)
            return;
        const playing = list.filter(p => p.isPlaying).sort((a, b) => since[a.dbusName] - since[b.dbusName]);
        if (playing.length > 0)
            props.manualActive = playing[0];
    }

    function getArtUrl(player: MprisPlayer): string {
        if (!player)
            return "";
        if (player.trackArtUrl)
            return player.trackArtUrl;

        const url = player.metadata["xesam:url"] ?? "";
        if (url.startsWith("https://www.youtube.com/watch")) {
            // Fallback for youtube
            const id = url.match(/[?&]v=([\w-]{11})/)?.[1];
            return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : "";
        }
        return "";
    }

    // Quickshell only emits postTrackChanged when trackid/url/title change, so late
    // artist updates (common with mpv-mpris + yt-dlp player) never retrigger it. Watch
    // title/artist too and toast once both are usable.
    function maybeToastNowPlaying(): void {
        if (!GlobalConfig.utilities.toasts.nowPlaying)
            return;

        const player = root.active;
        if (!player)
            return;

        const title = player.trackTitle ?? "";
        const artist = player.trackArtist ?? "";
        if (!title || !artist)
            return;

        const key = `${getIdentity(player)}\0${player.uniqueId}\0${title}\0${artist}`;
        if (key === lastNowPlayingKey)
            return;

        lastNowPlayingKey = key;
        Toaster.toast(Tr.tr("Now playing"), Tr.trCtx("%1 - %2", "track artist and title").arg(artist).arg(title), "music_note");
    }

    onActiveChanged: lastNowPlayingKey = ""
    onListChanged: follow()
    Component.onCompleted: follow()

    // Every player's playback, for `follow`
    Variants {
        model: root.list

        Connections {
            required property MprisPlayer modelData

            function onIsPlayingChanged(): void {
                root.follow();
            }

            target: modelData
        }
    }

    Connections {
        function onPostTrackChanged(): void {
            root.maybeToastNowPlaying();
        }

        function onTrackTitleChanged(): void {
            root.maybeToastNowPlaying();
        }

        function onTrackArtistChanged(): void {
            root.maybeToastNowPlaying();
        }

        target: root.active
    }

    PersistentProperties {
        id: props

        property MprisPlayer manualActive

        reloadableId: "players"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaToggle"
        description: "Toggle media playback"
        onPressed: {
            const active = root.active;
            if (active && active.canTogglePlaying)
                active.togglePlaying();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaPrev"
        description: "Previous track"
        onPressed: {
            const active = root.active;
            if (active && active.canGoPrevious)
                active.previous();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaNext"
        description: "Next track"
        onPressed: {
            const active = root.active;
            if (active && active.canGoNext)
                active.next();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaStop"
        description: "Stop media playback"
        onPressed: root.active?.stop()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaSwitch"
        description: "Switch to the next media player"
        onPressed: {
            if (root.list.length > 1)
                root.manualActive = root.list[(root.list.indexOf(root.active) + 1) % root.list.length];
        }
    }

    IpcHandler {
        function getActive(prop: string): string {
            const active = root.active;
            return active ? active[prop] ?? "Invalid property" : "No active player";
        }

        function list(): string {
            return root.list.map(p => root.getIdentity(p)).join("\n");
        }

        function play(): void {
            const active = root.active;
            if (active?.canPlay)
                active.play();
        }

        function pause(): void {
            const active = root.active;
            if (active?.canPause)
                active.pause();
        }

        function playPause(): void {
            const active = root.active;
            if (active?.canTogglePlaying)
                active.togglePlaying();
        }

        function previous(): void {
            const active = root.active;
            if (active?.canGoPrevious)
                active.previous();
        }

        function next(): void {
            const active = root.active;
            if (active?.canGoNext)
                active.next();
        }

        function stop(): void {
            root.active?.stop();
        }

        target: "mpris"
    }
}
