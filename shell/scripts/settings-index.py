#!/usr/bin/env python3
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

"""Writes modules/nexus/SettingsIndex.qml: every option on the settings pages, for the search.

Pages and their sub-pages come from modules/nexus/PageCompRegistry.qml's allPageComps (component N
there is page N of PageRegistry's allPages, whose id each option keeps; a page's sub-pages are its
StackPage's components, in order). Merged pages (General, Appearance) have no options of their own:
their member pages' options take you to them (PageRegistry.indexOf), as Dock's take you to Panels'
Dock sub-page (PageRegistry.shownSub). In each page's file,
each setting row (ToggleRow, SelectRow, ChoiceRow...) gives its label (text: or label:), its
description (subtext:) and the section it's under (the SectionHeader before it).
install.sh runs this before building; run it after changing settings pages to see them in search.
"""

import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
nexus = root / "modules" / "nexus"

ROWS = {
    "ToggleRow", "SelectRow", "ChoiceRow", "RangeRow", "StepperRow", "SliderRow", "TextFieldRow",
    "RowButton", "PopupRow", "SegmentedRow", "AgentRow", "ColourRow", "ColourOption",
}
# Sub-pages about one thing picked on their page (a network, a device, an app): opened from the
# search there'd be nothing picked, so their options aren't listed
SKIP = {
    "EthernetDetailPage", "AddNetworkPage", "NetworkDetailPage", "AddVpnPage", "BtDeviceInfo",
    "BluetoothPairing", "AppInfo", "WallpaperSelect", "WallpaperCategory", "PlaceholderComp",
}
TR = re.compile(r'Tr\.tr(?:Ctx)?\("((?:[^"\\]|\\.)*)"(?:\s*,\s*"((?:[^"\\]|\\.)*)")?\)')
PROP = re.compile(r"^\s*(text|label|subtext)\s*:\s*(.*)$")
OPEN = re.compile(r"^\s*(?:[\w.]+\s*:\s*)?([A-Z]\w*(?:\.\w+)*)\s*\{")


def page_files() -> dict[str, Path]:
    return {f.stem: f for f in (nexus / "pages").rglob("*.qml")}


def registry() -> list[list[str]]:
    """Each page's components (root page first, then its sub-pages) as type names."""
    text = (nexus / "PageCompRegistry.qml").read_text()
    body = text[text.index("allPageComps:"):]
    pages: list[list[str]] = []
    depth = 0
    current: list[str] | None = None
    for line in body.splitlines()[1:]:
        stripped = line.strip()
        if depth == 0 and stripped.startswith("]"):
            break
        if depth == 0 and stripped.startswith("Component {"):
            current = []
            pages.append(current)
        elif current is not None:
            # A sub-page: "Component {" then its type on the next line, or "Component { Type {} }"
            m = re.match(r"^([A-Z]\w*)\s*\{\s*\}?$", stripped)
            if m and m.group(1) not in ("Component", "StackPage"):
                current.append(m.group(1))
        depth += line.count("{") - line.count("}")
    return pages


def options(path: Path) -> list[dict]:
    found: list[dict] = []
    stack: list[str] = []
    section = ""
    row: dict | None = None
    row_depth = -1
    for line in path.read_text().splitlines():
        code = line.split("//")[0]
        m = OPEN.match(code)
        if m:
            stack.append(m.group(1))
            if m.group(1) in ROWS and row is None:
                row, row_depth = {"section": section}, len(stack)
        p = PROP.match(code)
        if p and stack:
            t = TR.search(p.group(2))
            if t:
                text, ctx = t.group(1), t.group(2)
                if stack[-1] == "SectionHeader" and p.group(1) == "text":
                    section = text
                elif row is not None and len(stack) == row_depth:
                    key = "label" if p.group(1) in ("text", "label") else "subtext"
                    row.setdefault(key, text)
                    if key == "label" and ctx:
                        row["ctx"] = ctx
        closes = code.count("}") - code.count("{") + (1 if m else 0)
        for _ in range(max(0, closes)):
            if row is not None and len(stack) == row_depth:
                if row.get("label"):
                    found.append(row)
                row, row_depth = None, -1
            if stack:
                stack.pop()
    return found


def page_ids() -> tuple[list[str], set[str]]:
    """PageRegistry's allPages ids, in order, and the merged pages' (those with consolidates:)."""
    text = (nexus / "PageRegistry.qml").read_text()
    body = text[text.index("allPages:"):]
    ids = re.findall(r'^\s*id: "(\w+)",', body, re.M)
    merged = set(re.findall(r'^\s*id: "(\w+)",\s*\n\s*consolidates:', body, re.M))
    return ids, merged


def main() -> None:
    files = page_files()
    ids, merged = page_ids()
    pages = registry()
    # A page that's also another's sub-page (Dock in Panels) is indexed as itself
    roots = {comps[0] for comps in pages if comps}
    index: list[dict] = []
    for page, comps in enumerate(pages):
        if ids[page] in merged:
            continue
        for sub, comp in enumerate(comps):
            path = files.get(comp)
            if not path or comp in SKIP or (sub > 0 and comp in roots):
                continue
            for opt in options(path):
                index.append({"pageId": ids[page], "sub": sub, **opt})

    out = nexus / "SettingsIndex.qml"
    out.write_text(
        "pragma Singleton\n\nimport QtQuick\n\n"
        "// Generated by scripts/settings-index.py (install.sh runs it): every option on the settings\n"
        "// pages, for the search. Don't edit by hand.\n"
        "QtObject {\n"
        f"    readonly property var options: {json.dumps(index, ensure_ascii=False)}\n"
        "}\n"
    )
    print(f"{len(index)} settings options indexed into {out.relative_to(root)}")


if __name__ == "__main__":
    main()
