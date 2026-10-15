// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell
import Quickshell.Io
import Taris.I18n
import qs.components.filedialog

// File pickers other apps ask the desktop for (through xdg-desktop-portal: browsers, Electron apps,
// Flatpaks, GTK4 apps...), shown with Taris's own, in the overlay like the settings.
// assets/portal-filechooser.py is the portal's FileChooser backend: it passes each request on with
// `ipc call filepicker open <id> <request>` and gets the answer back on D-Bus (Done).
Scope {
    id: root

    // The request being answered (one at a time: a newer one cancels it)
    property string requestId

    function answer(id: string, response: int, path: string): void {
        Quickshell.execDetached(["gdbus", "call", "--session", "--dest", "org.freedesktop.impl.portal.desktop.taris", "--object-path", "/org/taris/FilePicker", "--method", "org.taris.FilePicker.Done", id, String(response), path]);
    }

    FileDialog {
        id: dialog

        onAccepted: path => {
            const id = root.requestId;
            root.requestId = "";
            if (id)
                root.answer(id, 0, path);
        }
        onRejected: {
            const id = root.requestId;
            root.requestId = "";
            if (id)
                root.answer(id, 1, "");
        }
    }

    IpcHandler {
        // request: JSON { title, mode: open | directory | save, name, acceptLabel, filterLabel,
        // filters: [extensions], cwd: [path parts, "Home" first under the home folder] }
        function open(id: string, request: string): void {
            let r;
            try {
                r = JSON.parse(request);
            } catch (e) {
                root.answer(id, 2, "");
                return;
            }
            if (root.requestId)
                root.answer(root.requestId, 1, "");
            root.requestId = id;
            dialog.title = r.title || Tr.tr("Select a file");
            dialog.mode = ["open", "directory", "save"].includes(r.mode) ? r.mode : "open";
            dialog.currentName = r.name ?? "";
            dialog.acceptLabel = r.acceptLabel ?? "";
            dialog.filterLabel = r.filterLabel || Tr.tr("All files");
            dialog.filters = r.filters?.length > 0 ? r.filters : ["*"];
            dialog.cwd = r.cwd?.length > 0 ? r.cwd : ["Home"];
            dialog.open();
        }

        // The app gave up on it (the portal closed the request)
        function cancel(id: string): void {
            if (root.requestId !== id)
                return;
            root.requestId = "";
            dialog.close();
        }

        target: "filepicker"
    }
}
