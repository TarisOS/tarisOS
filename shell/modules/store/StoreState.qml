// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell

// What a Store shows: a view (discover, installed, updates, a category, a search) and, over it, an
// app's page
QtObject {
    property ShellScreen screen
    property bool isWindow
    property bool animatingContainer

    property string view: "discover"
    property string category
    property string categoryLabel
    property string searchText
    property var app: null // The app whose page is open (an app from store.py), else none
    // The screenshot preview: { shots: [{ thumb, full }], index }, else none
    property var viewer: null

    signal close

    function show(newView: string, newCategory: string, newCategoryLabel: string): void {
        app = null;
        viewer = null;
        view = newView;
        category = newCategory ?? "";
        categoryLabel = newCategoryLabel ?? "";
    }

    onSearchTextChanged: {
        if (searchText) {
            app = null;
            viewer = null;
        }
    }

    onAppChanged: viewer = null
}
