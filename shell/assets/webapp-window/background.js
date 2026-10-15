// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

// Web app windows (chromium --app=…, assets/launch-webapp.sh) have no scrollbars; their pages
// still scroll. Normal windows and popups (sign-in windows) keep theirs.
// Loaded with --load-extension (install.sh adds it to ~/.config/chromium-flags.conf).

const css = "* { scrollbar-width: none !important; }";
const allTypes = ["normal", "popup", "panel", "app", "devtools"];

chrome.webNavigation.onCommitted.addListener(async ({ tabId, frameId }) => {
    try {
        const tab = await chrome.tabs.get(tabId);
        // Without windowTypes, windows.get only finds normal windows and popups
        const win = await chrome.windows.get(tab.windowId, { windowTypes: allTypes });
        if (win.type !== "app") return;

        // USER origin: wins over the page's own !important scrollbar styles
        await chrome.scripting.insertCSS({ target: { tabId, frameIds: [frameId] }, css, origin: "USER" });
    } catch {
        // The tab or frame went away, or it's a page extensions can't touch (chrome://…)
    }
});
