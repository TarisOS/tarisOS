-- Copyright (C) 2026 George Dobreff ("Witcher") and contributors
-- SPDX-License-Identifier: GPL-3.0-only

-- The greeter's Hyprland (greetd starts it as the greeter user): nothing runs in it but the
-- greeter, or the setup screen on first boot (/usr/lib/taris/greeter-session). It quits when they
-- have started someone's session.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2 })

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("XCURSOR_SIZE", "24")

-- The system's keyboard layout (set up on first boot: localectl), so the password is typed in it
local layout, variant = "us", ""
local f = io.open("/etc/X11/xorg.conf.d/00-keyboard.conf")
if f then
  for line in f:lines() do
    layout = line:match('Option%s+"XkbLayout"%s+"([^"]*)"') or layout
    variant = line:match('Option%s+"XkbVariant"%s+"([^"]*)"') or variant
  end
  f:close()
end

hl.config({
  input = {
    kb_layout = layout,
    kb_variant = variant,
    touchpad = { natural_scroll = true, tap_to_click = true, clickfinger_behavior = true },
  },
  general = { border_size = 0, gaps_in = 0, gaps_out = 0 },
  decoration = { rounding = 0, shadow = { enabled = false }, blur = { enabled = false } },
  animations = { enabled = false },
  xwayland = { enabled = false },
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    background_color = "rgb(000000)",
    allow_session_lock_restore = true,
    disable_watchdog_warning = true,
  },
  ecosystem = { no_update_news = true, no_donation_nag = true },
})

hl.on("hyprland.start", function()
  hl.exec_cmd("/usr/lib/taris/greeter-session")
end)
