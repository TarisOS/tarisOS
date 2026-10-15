// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Taris.I18n
import qs.components.controls
import qs.services
import qs.modules.store

// Flatpak and AUR apps with an update. Repo packages, apps included, update with the system on
// the Settings Updates page (updating one on its own is a partial upgrade, which can break Arch)
StorePage {
    id: root

    property var apps: null
    property int req: -1
    readonly property var flatpaks: (apps ?? []).filter(a => a.source === "flathub")
    readonly property var aur: (apps ?? []).filter(a => a.source === "aur")

    function load(): void {
        AppStore.cancel(req);
        req = AppStore.request("updates", {}, (result, err) => {
            req = -1;
            apps = result ?? [];
            AppStore.updateCount = apps.length;
            error = err;
        });
    }

    function updateAll(): void {
        if (flatpaks.length) {
            AppStore.markRunning("flathub:*");
            AppStore.request("update", {
                key: "flathub:*",
                source: "flathub",
                pkg: ""
            });
        }
        const versions = {};
        for (const a of aur)
            versions[a.pkg] = a.version;
        if (aur.length)
            AppStore.aurTerminal(Tr.tr("Updating apps"), "yay -S", aur.map(a => a.pkg), "update", versions);
    }

    title: Tr.tr("Updates")
    loading: apps === null
    empty: !apps?.length
    emptyText: Tr.tr("Apps are up to date")
    trailing: TextButton {
        visible: (root.apps?.length ?? 0) > 1 && AppStore.jobs["flathub:*"]?.state !== "running"
        text: Tr.tr("Update all")
        onClicked: root.updateAll()
    }

    Component.onCompleted: load()
    Component.onDestruction: AppStore.cancel(req)

    Connections {
        function onChangesChanged(): void {
            root.load();
        }

        target: AppStore
    }

    AppGrid {
        sState: root.sState
        apps: root.apps ?? []
    }
}
