// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Taris.I18n
import qs.services
import qs.modules.store

// Popular, trending and new apps (Flathub's lists, an app's native package in its place when there's one)
StorePage {
    id: root

    property var sections: null
    property int req: -1
    readonly property bool hasApps: (sections?.popular?.length ?? 0) + (sections?.trending?.length ?? 0) + (sections?.["recently-added"]?.length ?? 0) > 0

    function load(): void {
        AppStore.cancel(req);
        req = AppStore.request("home", {}, (result, err) => {
            req = -1;
            sections = result ?? {};
            error = err;
        });
    }

    title: Tr.tr("Discover")
    loading: sections === null
    empty: !hasApps
    emptyText: Tr.tr("Couldn't reach Flathub")

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
        title: Tr.tr("Popular")
        apps: root.sections?.popular ?? []
        limit: 12
    }

    AppGrid {
        sState: root.sState
        title: Tr.tr("Trending")
        apps: root.sections?.trending ?? []
        limit: 12
    }

    AppGrid {
        sState: root.sState
        title: Tr.tr("New")
        apps: root.sections?.["recently-added"] ?? []
        limit: 12
    }
}
