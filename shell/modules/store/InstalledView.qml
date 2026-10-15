// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Taris.I18n
import qs.services
import qs.modules.store

// Apps on this system: from the repos, Flathub and the AUR
StorePage {
    id: root

    property var apps: null
    property int req: -1

    function load(): void {
        AppStore.cancel(req);
        req = AppStore.request("installed", {}, (result, err) => {
            req = -1;
            apps = result ?? [];
            error = err;
        });
    }

    title: Tr.tr("Installed")
    loading: apps === null
    empty: !apps?.length
    emptyText: Tr.tr("No apps")

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
