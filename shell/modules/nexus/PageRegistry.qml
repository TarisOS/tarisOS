// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import Taris.I18n

QtObject {
    id: root

    // Pages merged into one, as the Witcher's Tweaks settings have them (General, Appearance: each
    // a page showing its member pages one after another), and Dock in Panels. False brings back
    // the separate pages.
    readonly property bool consolidated: true

    // The pages in the sidebar (and PageCompRegistry.pageComps, which follows them)
    readonly property list<var> pages: allPages.filter(p => shows(p))

    // id: what the Settings overlay is opened on (WindowFactory.open, a popout's "Open settings");
    // keywords: what else finds the page in the settings search (matches); consolidates: the
    // pages a merged page shows (only there while consolidated, and they aren't then); inPage,
    // inSub: the page and sub-page it is while consolidated (not in the sidebar then)
    readonly property list<var> allPages: [
        // Connectivity
        {
            id: "network",
            keywords: "wifi wi-fi wireless ethernet vpn internet connection password hotspot dns",
            label: Tr.tr("Network"),
            icon: "wifi",
            description: Tr.tr("Wi-Fi, ethernet, VPN"),
            category: "connectivity"
        },
        {
            id: "bluetooth",
            keywords: "bluetooth devices pair pairing headphones speaker mouse",
            label: Tr.tr("Connected devices"),
            icon: "devices_other",
            description: Tr.tr("Bluetooth, pairing"),
            category: "connectivity",
            noFill: true
        },
        // General, look, panels, displays and power
        {
            id: "general",
            consolidates: ["about", "updates", "language"],
            label: Tr.tr("General"),
            icon: "settings",
            description: Tr.tr("About, updates, language, time and units"),
            category: "system"
        },
        {
            id: "about",
            keywords: "about system version information",
            label: Tr.tr("About"),
            icon: "info",
            description: Tr.tr("System information, credits"),
            category: "system"
        },
        {
            id: "updates",
            keywords: "update upgrade packages pacman system",
            label: Tr.tr("Updates"),
            icon: "update",
            description: Tr.tr("System updates"),
            category: "system"
        },
        {
            id: "language",
            keywords: "language region time zone timezone clock date weather location city units temperature",
            label: Tr.tr("Language & region"),
            icon: "globe",
            description: Tr.tr("Weather location, display units"),
            category: "system"
        },
        {
            id: "look",
            consolidates: ["appearance", "windowstyle"],
            label: Tr.tr("Appearance"),
            icon: "palette",
            description: Tr.tr("Wallpaper, colours, windows and borders"),
            category: "system"
        },
        {
            id: "appearance",
            keywords: "wallpaper background colours colors colour color theme scheme accent dark light mode transparency opacity scale fonts",
            label: Tr.tr("Wallpaper & style"),
            icon: "palette",
            description: Tr.tr("Wallpaper, fonts, colours"),
            category: "system"
        },
        {
            id: "windowstyle",
            keywords: "window windows border gaps gap rounding corners animation workspace swipe gesture floating float tiled titlebar title bar resize columns",
            label: Tr.tr("Window style"),
            icon: "border_style",
            description: Tr.tr("Borders, gaps, corners, workspace animation, swipes"),
            category: "system"
        },
        {
            id: "panels",
            keywords: "panels bar taskbar dashboard launcher notifications quick toggles osd clock workspaces tray",
            label: Tr.tr("Panels"),
            icon: "dock_to_bottom",
            description: Tr.tr("Dashboard, taskbar, launcher, sidebar"),
            category: "system"
        },
        {
            id: "dock",
            inPage: "panels",
            inSub: 9,
            keywords: "dock pinned pin apps trash",
            label: Tr.tr("Dock"),
            icon: "dock_to_left",
            description: Tr.tr("Pinned apps, show or hide"),
            category: "system"
        },
        {
            id: "displays",
            keywords: "display displays monitor monitors screen resolution scale refresh rate arrangement",
            label: Tr.tr("Displays"),
            icon: "monitor",
            description: Tr.tr("Scale, resolution, arrangement"),
            category: "system"
        },
        {
            id: "power",
            keywords: "power battery idle sleep suspend hibernate timeout profile charging",
            label: Tr.tr("Power"),
            icon: "battery_charging_full",
            description: Tr.tr("Power profile, idle, sleep, battery"),
            category: "system"
        },
        // Notifications and sound
        {
            id: "services",
            keywords: "services notifications toasts lyrics media players brightness",
            label: Tr.tr("Services"),
            icon: "build",
            description: Tr.tr("Poll intervals, lyrics backend"),
            category: "alerts"
        },
        {
            id: "audio",
            keywords: "sound volume speakers microphone mic input output headphones",
            label: Tr.tr("Audio"),
            icon: "volume_up",
            description: Tr.tr("App volumes, sound devices"),
            category: "alerts"
        },
        // Security
        {
            id: "security",
            keywords: "lock screen lockscreen password security",
            label: Tr.tr("Security"),
            icon: "lock",
            description: Tr.tr("Lock screen, password"),
            category: "security"
        },
        // Backup & restore
        {
            id: "backup",
            keywords: "backup backups restore snapshot snapshots factory reset erase",
            label: Tr.tr("Backup & restore"),
            icon: "settings_backup_restore",
            description: Tr.tr("Backups, factory reset"),
            category: "security"
        },
        // Input
        {
            id: "keyboard",
            keywords: "keyboard layout repeat caps lock ctrl super swap input method chinese japanese korean pinyin trackpad touchpad mouse pointer scroll tap natural",
            label: Tr.tr("Keyboard & trackpad"),
            icon: "keyboard",
            description: Tr.tr("Layout, repeat, Ctrl/Super swap, Caps Lock, input methods, scrolling, tapping"),
            category: "input"
        },
        // Apps and plugins
        {
            id: "apps",
            keywords: "apps applications default browser terminal file manager agent hidden favourites favorites",
            label: Tr.tr("Apps"),
            icon: "apps",
            description: Tr.tr("Default apps, favourites, hidden apps"),
            category: "apps"
        },
        {
            id: "plugins",
            keywords: "plugins extensions",
            label: Tr.tr("Plugins"),
            icon: "extension",
            description: Tr.tr("Manage plugins"),
            category: "apps"
        },
    ]

    // The page settings open on when no page is asked for
    readonly property string defaultPage: "general"

    // Whether the sidebar has this page: a merged page only while consolidated, its members only
    // while not
    function shows(page: var): bool {
        if (page.consolidates)
            return consolidated;
        return !(consolidated && (page.inPage || allPages.some(p => p.consolidates?.includes(page.id))));
    }

    // The page showing the page with that id: itself, the merged page it's in, or the one it's a
    // sub-page of
    function shownId(id: string): string {
        if (consolidated) {
            const merged = allPages.find(p => p.consolidates?.includes(id));
            if (merged)
                return merged.id;
            const inPage = allPages.find(p => p.id === id)?.inPage;
            if (inPage)
                return inPage;
        }
        return id;
    }

    // Sub-page sub of the page with that id, as a sub-page of the page showing it (shownId)
    function shownSub(id: string, sub: int): int {
        const inSub = allPages.find(p => p.id === id)?.inSub;
        return consolidated && inSub !== undefined ? inSub + sub : sub;
    }

    // The index (in pages) of the page showing the one with that id, or of the default page
    function indexOf(id: string): int {
        const i = pages.findIndex(p => p.id === shownId(id));
        return i >= 0 ? i : Math.max(0, pages.findIndex(p => p.id === shownId(defaultPage)));
    }

    // An option of the settings index (SettingsIndex.options) as it reads in the current language
    function optionLabel(opt: var): string {
        return opt.ctx ? Tr.trCtx(opt.label, opt.ctx) : Tr.tr(opt.label);
    }

    // An option the settings search finds: every word typed is in its name, description, section
    // or page name
    function optionMatches(opt: var, query: string): bool {
        const words = query.toLowerCase().split(/\s+/).filter(w => w);
        const page = allPages.find(p => p.id === opt.pageId);
        const text = `${optionLabel(opt)} ${opt.subtext ? Tr.tr(opt.subtext) : ""} ${opt.section ? Tr.tr(opt.section) : ""} ${page?.label ?? ""}`.toLowerCase();
        return words.length > 0 && words.every(w => text.includes(w));
    }

    // A page the settings search finds: every word typed is in its name, description or keywords
    // (a merged page's: its members' too)
    function matches(page: var, query: string): bool {
        const words = query.toLowerCase().split(/\s+/).filter(w => w);
        const members = consolidated ? allPages.filter(p => page.consolidates?.includes(p.id) || p.inPage === page.id) : [];
        const text = [page, ...members].map(p => `${p.label} ${p.description} ${p.keywords ?? ""}`).join(" ").toLowerCase();
        return words.every(w => text.includes(w));
    }
}
