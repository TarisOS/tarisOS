# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

"""The boot screen's password field (field.png): the lock screen's pill, in its dark surface colour.
Drawn at twice the size and scaled down for smooth edges. field.py <out.png>"""

import sys

from PIL import Image, ImageDraw

W, H, S = 440, 56, 4
img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
ImageDraw.Draw(img).rounded_rectangle((0, 0, W * S - 1, H * S - 1), radius=H * S // 2, fill=(43, 41, 48, 255))
img.resize((W, H), Image.LANCZOS).save(sys.argv[1])
