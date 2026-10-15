// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Taris.I18n
import qs.services
import qs.modules.store

// A category's apps: Flathub's most installed first (native packages in their place), then the
// repos' others
StorePage {
    id: root

    property var apps: null
    property int req: -1

    function load(): void {
        AppStore.cancel(req);
        const category = sState.category;
        req = AppStore.request("category", {
            name: category
        }, (result, err) => {
            req = -1;
            apps = result ?? [];
            error = err;
        });
    }

    title: sState.categoryLabel
    loading: apps === null
    empty: !apps?.length
    emptyText: Tr.tr("No apps")

    Component.onCompleted: load()
    Component.onDestruction: AppStore.cancel(req)

    Connections {
        function onCategoryChanged(): void {
            root.apps = null;
            root.load();
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
        apps: root.apps ?? []
    }
}
