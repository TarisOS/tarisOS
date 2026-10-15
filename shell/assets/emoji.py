#!/usr/bin/python3 -I
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Every emoji, for the shell's emoji picker (modules/EmojiPicker.qml, which runs this): Unicode's
# own list (unicode-emoji's emoji-test.txt), in its order and categories, each emoji with its name
# (what search matches). Only the emoji themselves: not the pieces they're made of (the Component
# category) nor their skin-tone variants.
# Usage: emoji.py [emoji-test.txt]   (prints [{"group": name, "emojis": [[emoji, name], ...]}, ...])

import json
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/unicode/emoji/emoji-test.txt"
skin_tones = {0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF}

groups = []
with open(path, encoding="utf-8") as f:
    for line in f:
        if line.startswith("# group: "):
            name = line[len("# group: ") :].strip()
            groups.append({"group": name, "emojis": []})
            continue
        if line.startswith("#") or "; fully-qualified" not in line or not groups:
            continue
        codes, _, rest = line.partition(";")
        if any(int(c, 16) in skin_tones for c in codes.split()):
            continue
        # "# 😀 E1.0 grinning face": the emoji, the version it came in, its name
        _, _, comment = rest.partition("#")
        parts = comment.strip().split(" ", 2)
        if len(parts) == 3:
            groups[-1]["emojis"].append([parts[0], parts[2]])

json.dump([g for g in groups if g["group"] != "Component" and g["emojis"]], sys.stdout, ensure_ascii=False)
