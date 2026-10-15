# Icons and Brand Marks

Read this before adding or changing an icon in the shell, a logo or a brand mark.

## Which kind of icon

- **The shell's own icons** are Material Symbols Rounded glyphs, drawn with `MaterialIcon`
  (`shell/components/MaterialIcon.qml`) by name (`text: "wifi"`), recoloured from `Colours`. Use
  one of these for anything generic: a folder, a microphone, a setting.
- **Apps' icons** come from their desktop entries through the icon theme
  (`Quickshell.iconPath(entry.icon, "image-missing")`, Papirus). Never ship a copy of an app's
  icon for the launcher or the dock.
- **Brand marks** are SVG files in `shell/assets/` (the agents' marks in
  `shell/assets/agent/icons/`, with a `-light` variant where the mark needs one on light schemes).
  Reach for one only when a generic glyph would misrepresent the thing: a generic robot for several
  different coding agents is the case that justifies the real marks; a folder or a microphone is
  not.
- **TarisOS's logo** is `shell/assets/logo.png`, shown in its own colours (never recoloured) by
  `shell/components/Logo.qml` and the About page's `AnimatedLogo.qml`. The system's icon (`taris`,
  os-release's `LOGO`) is the same artwork as square PNGs in `packaging/defaults/logo/`, installed
  into the hicolor theme by `taris-desktop`. Regenerate all of them from the one source image.
- **The preinstalled web apps' icons** are PNGs in `packaging/defaults/webapps/icons/`, named in
  `list.tsv`, taken from the sites themselves.

## Adding a brand mark

- Prefer the official mark when it is published as flat art; fall back to an icon set's redraw
  (for example <https://simpleicons.org>) when it is not.
- Two-tone marks are a trap when recoloured: a logo whose meaning depends on lighter and darker
  halves turns into a blob. Pick a source whose silhouette alone reads, or keep its own colours.
- Note where the artwork came from (its URL) in the commit message the user approves, and
  keep its licence in mind: anything that isn't GPL-compatible doesn't go in.
- Check it at the size it's used, on dark and light schemes, in the running shell (see
  [`visual-verification.md`](visual-verification.md)).

## After changing fonts or icons

Qt reads the font database at startup: after installing or changing a font, refresh the cache
(`fc-cache -f`) and restart the shell (say so first) before judging the result. Remove temporary
fonts and fontconfig rules after verification.
