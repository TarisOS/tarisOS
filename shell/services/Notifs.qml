// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Taris
import Taris.Config
import Taris.I18n
import qs.components.misc
import qs.services
import qs.utils

Singleton {
    id: root

    property list<NotifData> list: []
    readonly property list<NotifData> notClosed: list.filter(n => !n.closed)
    readonly property list<NotifData> popups: list.filter(n => n.popup)
    property alias dnd: props.dnd

    property bool loaded

    function hasFullscreen(): bool {
        for (const monitor of Hypr.monitors.values) {
            if (monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1))
                return true;
        }
        return false;
    }

    // A notification clicked with Settings' click action "open": its single action when there's one
    // and Settings asks for it (notifs.actionOnClick), else its app (open)
    function activate(notif: NotifData): void {
        const actions = notif.actions;
        if (GlobalConfig.notifs.actionOnClick && actions.length === 1 && actions[0].identifier !== "default")
            actions[0].invoke();
        else
            open(notif);
    }

    // A notification clicked: its app, at what it's about. The notification's default action has the
    // app open it (a chat, a mail...); the app then asks for its window to be shown, which Hyprland
    // only marks urgent (misc:focus_on_activate is off), and that window is focused. Without that
    // request soon, or without a default action, the app's window is focused, or the app opened.
    function open(notif: NotifData): void {
        const entry = appEntry(notif);
        const action = notif.actions.find(a => a.identifier === "default");
        notif.popup = false;
        openFallback.entry = entry;
        if (action?.invoke) {
            openFallback.restart();
            action.invoke();
        } else if (entry) {
            showApp(entry);
        }
    }

    // The launcher of the app that sent a notification (none for Taris's own)
    function appEntry(notif: NotifData): DesktopEntry {
        if (notif.materialIcon)
            return null;
        return (notif.desktopEntry ? DesktopEntries.byId(notif.desktopEntry) : null) ?? DesktopEntries.heuristicLookup(notif.appName);
    }

    function showApp(entry: DesktopEntry): void {
        const wins = Dock.windowsFor(entry);
        if (wins.length > 0)
            Dock.focusWindow(wins.find(w => w === Hypr.activeToplevel) ?? wins[0]);
        else
            Dock.activate(entry);
    }

    function shouldShowPopup(): bool {
        if (props.dnd || ShellState.anySidebarOpen())
            return false;
        if (GlobalConfig.notifs.fullscreen === NotifsFullscreen.Off && hasFullscreen())
            return false;
        return true;
    }

    // Taris's own messages (battery, charger, do not disturb, VPN...) come as toasts; they show
    // as notifications instead, popping up top right and kept in the notification panel like any other.
    // The plugin's toasts (Caps Lock, keyboard layout...) are marked for translation: translated
    // and filled in here, as the toasts' own view did.
    function takeToasts(): void {
        const toasts = [];
        for (let i = 0; i < Toaster.toasts.length; i++)
            if (!Toaster.toasts[i].closed)
                toasts.push(Toaster.toasts[i]);

        for (const toast of toasts.reverse()) {
            const comp = notifComp.createObject(root, {
                popup: root.shouldShowPopup(),
                summary: Tr.trMarked(toast.title),
                body: Tr.trMarked(toast.message),
                appName: Tr.tr("System"),
                materialIcon: toast.icon,
                expireTimeout: toast.timeout,
                urgency: toast.type === Toast.Error ? NotificationUrgency.Critical : NotificationUrgency.Normal
            });
            root.list = [comp, ...root.list];
            toast.close();
        }
    }

    onDndChanged: {
        if (!GlobalConfig.utilities.toasts.dndChanged)
            return;

        if (dnd)
            Toaster.toast(Tr.tr("Do not disturb enabled"), Tr.tr("Popup notifications are now disabled"), "do_not_disturb_on");
        else
            Toaster.toast(Tr.tr("Do not disturb disabled"), Tr.tr("Popup notifications are now enabled"), "do_not_disturb_off");
    }

    onListChanged: {
        if (loaded)
            saveTimer.restart();
    }
    // Toasts sent before this service was made
    Component.onCompleted: Qt.callLater(takeToasts)

    Connections {
        function onToastsChanged(): void {
            Qt.callLater(root.takeToasts);
        }

        target: Toaster
    }

    // Waiting for the app to ask for its window after a click (open())
    Timer {
        id: openFallback

        property var entry

        interval: 1500
        onTriggered: {
            if (entry)
                root.showApp(entry);
        }
    }

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name !== "urgent" || !openFallback.running)
                return;
            const window = Hypr.toplevels.values.find(t => t.address === event.data);
            if (window) {
                openFallback.stop();
                Dock.focusWindow(window);
            }
        }

        target: Hyprland
    }

    Timer {
        id: saveTimer

        interval: 1000
        onTriggered: storage.setText(JSON.stringify(root.notClosed.map(n => ({
                    time: n.time,
                    id: n.id,
                    summary: n.summary,
                    body: n.body,
                    appIcon: n.appIcon,
                    appName: n.appName,
                    desktopEntry: n.desktopEntry,
                    image: n.image,
                    materialIcon: n.materialIcon,
                    expireTimeout: n.expireTimeout,
                    urgency: n.urgency,
                    resident: n.resident,
                    hasActionIcons: n.hasActionIcons,
                    actions: n.actions
                }))))
    }

    PersistentProperties {
        id: props

        property bool dnd

        reloadableId: "notifs"
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;

            const comp = notifComp.createObject(root, {
                popup: root.shouldShowPopup(),
                notification: notif
            });
            root.list = [comp, ...root.list];
        }
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/notifs.json`
        onLoaded: {
            const data = JSON.parse(text());
            for (const notif of data) {
                const properties = Object.assign({}, notif);

                // Backwards compatibility for old notifications
                if (properties.notificationId === undefined && properties.id !== undefined)
                    properties.notificationId = properties.id;

                delete properties.id;
                root.list.push(notifComp.createObject(root, properties));
            }
            root.list.sort((a, b) => b.time - a.time);
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.loaded = true;
                Qt.callLater(() => setText("[]"));
            }
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "clearNotifs"
        description: "Clear all notifications"
        onPressed: {
            for (const notif of root.list.slice())
                notif.close();
        }
    }

    IpcHandler {
        function clear(): void {
            for (const notif of root.list.slice())
                notif.close();
        }

        function isDndEnabled(): bool {
            return props.dnd;
        }

        function toggleDnd(): void {
            props.dnd = !props.dnd;
        }

        function enableDnd(): void {
            props.dnd = true;
        }

        function disableDnd(): void {
            props.dnd = false;
        }

        target: "notifs"
    }

    Component {
        id: notifComp

        NotifData {}
    }
}
