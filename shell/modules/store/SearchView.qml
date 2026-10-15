// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Taris.I18n
import qs.services
import qs.modules.store

// What the search finds: apps from the repos and Flathub, then AUR packages
StorePage {
    id: root

    property var result: null
    property int req: -1

    function load(): void {
        AppStore.cancel(req);
        req = AppStore.request("search", {
            q: sState.searchText
        }, (res, err) => {
            req = -1;
            result = res ?? {
                apps: [],
                aur: []
            };
            error = err;
        });
    }

    title: Tr.tr("“%1”").arg(sState.searchText)
    loading: result === null
    empty: !result?.apps?.length && !result?.aur?.length
    emptyText: Tr.tr("No apps found")

    Component.onCompleted: load()
    Component.onDestruction: AppStore.cancel(req)

    Connections {
        function onSearchTextChanged(): void {
            if (root.sState.searchText) {
                root.result = null;
                root.load();
            }
        }

        target: root.sState
    }

    Connections {
        function onChangesChanged(): void {
            root.load();
        }

        target: AppStore
    }

    AppGrid {
        sState: root.sState
        apps: root.result?.apps ?? []
    }

    AppGrid {
        sState: root.sState
        title: "AUR"
        apps: root.result?.aur ?? []
    }
}
