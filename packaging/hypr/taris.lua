-- Copyright (C) 2026 George Dobreff ("Witcher") and contributors
-- SPDX-License-Identifier: GPL-3.0-only

-- TarisOS: the shell's integration with Hyprland (/usr/share/taris/hypr), loaded from the end of
-- hyprland.lua. Settings made on the Displays and Keyboard pages live in
-- ~/.config/taris/hypr-settings.lua; the Window style page writes ~/.config/taris/window-style.conf.

local home = os.getenv("HOME")
local qs = "taris-qs -c taris"

-- Panels animate themselves. The floating windows' button surfaces (titlebars) too: the shell takes
-- them away while a panel is open and brings them back after, and Hyprland's fade of those
-- (transparent until hovered) was about half of its work and frames at every panel opening and
-- closing
hl.layer_rule({ match = { namespace = "taris-(border-exclusion|area-picker|overview|agent|titlebars)" }, no_anim = true })
hl.layer_rule({ match = { namespace = "taris-(drawers|background)" }, animation = "fade" })

-- Shell shortcuts
hl.bind("SUPER + GRAVE", hl.dsp.global("taris:overview"), { description = "Window overview" })
pcall(hl.unbind, "SUPER + SPACE")
hl.bind("SUPER + SPACE", hl.dsp.global("taris:launcher"), { description = "App launcher" })
hl.bind("SUPER + N", hl.dsp.global("taris:sidebar"), { description = "Notification sidebar" })
-- Every shortcut, from the descriptions given to them (modules/Keybinds.qml)
hl.bind("SUPER + K", hl.dsp.global("taris:keybinds"), { description = "Keyboard shortcuts" })
hl.bind("SUPER + COMMA", hl.dsp.exec_cmd(qs .. " ipc call nexus open"), { description = "Settings" })

-- 3-finger swipe up opens the window overview, down closes it
hl.gesture({ fingers = 3, direction = "up", action = function()
  hl.dispatch(hl.dsp.global("taris:overviewOpen"))
end })
hl.gesture({ fingers = 3, direction = "down", action = function()
  hl.dispatch(hl.dsp.global("taris:overviewClose"))
end })

-- Apps that live only on a special workspace of their own, shown over whichever workspace you're
-- on and hidden again, as Caelestia's music workspace is: Taris Music, the music player (music),
-- and the shell's agent terminal (agent: a window of the shell's, titled Agent, made when SUPER + A
-- first shows it; services/AgentTerminal.qml). Their windows open there, tiled, and one moved
-- anywhere else (minimised, SUPER + SHIFT + a number) goes back there, hidden. They look like the
-- shell's settings overlay: rounded as near the shell's panels (Config.border.rounding, 25) as a
-- window rule goes (20 at most), no border, the rest of the screen dimmed. taris_music() shows or
-- hides the player, starting it first when it has no window: SUPER + P, its launcher (hyprctl eval)
-- and the dashboard's Media tab. taris_agent() shows or hides the agent's: the shell calls it for
-- SUPER + A, and makes the window instead when there's none. Errors go to
-- $XDG_RUNTIME_DIR/taris-hypr.log.
local spaces = {
  {
    name = "music",
    ws = "special:music",
    rule = "music-player",
    match = { class = "^(taris-music)$" },
    is = function(w) return (w.class or "") == "taris-music" end,
  },
  {
    name = "agent",
    ws = "special:agent",
    rule = "agent-window",
    match = { class = "^(org\\.quickshell)$", title = "^(Agent)$" },
    is = function(w) return (w.class or "") == "org.quickshell" and (w.title or "") == "Agent" end,
  },
}
local function log_error(where, err)
  local f = io.open((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/taris-hypr.log", "a")
  if f then
    f:write(os.date("%H:%M:%S "), where, ": ", tostring(err), "\n")
    f:close()
  end
end
-- The space whose app w is, and the space a workspace is
local function space_of(w)
  if w == nil then return nil end
  for _, s in ipairs(spaces) do
    if s.is(w) then return s end
  end
  return nil
end
local function space_on(ws)
  if ws == nil then return nil end
  for _, s in ipairs(spaces) do
    if ws.name == s.ws then return s end
  end
  return nil
end
-- Nothing else goes on these workspaces: a window opening while one's shown (an app started then)
-- opens on the workspace underneath instead, the special workspace hidden so it's seen (below).
-- Before the apps' own rules, which win for their windows (a later rule's workspace replaces an
-- earlier one's): the agent's window opening while the music workspace is shown goes on its own.
for _, s in ipairs(spaces) do
  hl.window_rule({
    name = s.name .. "-elsewhere",
    match = { workspace = s.ws, class = "negative:" .. s.match.class },
    workspace = "e+0",
  })
end
for _, s in ipairs(spaces) do
  hl.window_rule({
    name = s.rule,
    match = s.match,
    workspace = s.ws,
    tile = true,
    rounding = 20,
    border_size = 0,
    dim_around = true,
  })
  -- The workspace's window tiled at its full size, inside outer gaps
  hl.workspace_rule({ workspace = s.ws, gaps_out = 48 })
  -- While the workspace is hidden, the app can't be focused: Hyprland would otherwise give it the
  -- focus back (a panel's focus grab let go, a window closed), showing the workspace. With no other
  -- window, focus goes nowhere, as if the app weren't running.
  s.hidden_rule = hl.window_rule({ name = s.rule .. "-hidden", match = s.match, no_focus = true })
  -- The app stays as it is there, without anything being undone after the fact (which would
  -- flicker): its own fullscreen and maximise requests are ignored; the keys that would
  -- fullscreen, maximise, float, minimise or move it skip it (unless_space_app), and so does
  -- SUPER + drag. A window still moved in or out somehow is put back (below).
  hl.window_rule({ name = s.rule .. "-requests", match = s.match, suppress_event = "fullscreen maximize" })
end
-- SUPER + drag moves the window under the pointer, but not while one of these workspaces is shown.
-- Hyprland calls this again on release only when it started a drag, to end it.
local space_dragging = false
pcall(hl.unbind, "SUPER + mouse:272")
hl.bind("SUPER + mouse:272", function()
  if not space_dragging and space_on(hl.get_active_special_workspace()) ~= nil then return end
  space_dragging = not space_dragging
  hl.dispatch(hl.dsp.window.drag())
end, { mouse = true })
local function shown(s)
  for _, m in ipairs(hl.get_monitors() or {}) do
    local special = m.active_special_workspace
    if special ~= nil and special.name == s.ws then return true end
  end
  return false
end
-- Checked a moment after a special workspace is shown or hidden: the event can come before the
-- monitor says so, and the rule turned back on while it's shown would leave the app without the
-- focus (the next window focused, a panel closing, hides the workspace again). Shown, the app is
-- focused too.
local focus_timer
local function update_focus()
  for _, s in ipairs(spaces) do
    local on = shown(s)
    s.hidden_rule:set_enabled(not on)
    if on and not s.is(hl.get_active_window() or {}) then
      for _, w in ipairs(hl.get_workspace_windows(s.ws) or {}) do
        if s.is(w) then
          hl.dispatch(hl.dsp.focus({ window = w }))
          break
        end
      end
    end
  end
end
local function update_focus_soon()
  focus_timer = hl.timer(function()
    local ok, err = pcall(update_focus)
    if not ok then log_error("update_focus", err) end
  end, { timeout = 50, type = "oneshot" })
end
for _, s in ipairs(spaces) do
  s.hidden_rule:set_enabled(not shown(s))
end
hl.on("workspace.special_active", function()
  local ok, err = pcall(update_focus_soon)
  if not ok then log_error("workspace.special_active (spaces)", err) end
end)
-- Shows or hides the space's workspace when its app has a window; start() otherwise
local function toggle_space(s, start)
  -- Focusable before it's shown (or started), so showing it focuses it
  if not shown(s) then s.hidden_rule:set_enabled(false) end
  for _, w in ipairs(hl.get_windows() or {}) do
    if s.is(w) and w.mapped ~= false then
      hl.dispatch(hl.dsp.workspace.toggle_special(s.name))
      update_focus_soon()
      return
    end
  end
  if start ~= nil then start() end
end
function _G.taris_music()
  local ok, err = pcall(toggle_space, spaces[1], function()
    -- In a scope of its own, as every app (run-app)
    hl.dispatch(hl.dsp.exec_cmd("/usr/lib/taris/run-app taris-music"))
  end)
  if not ok then log_error("taris_music", err) end
end
function _G.taris_agent()
  local ok, err = pcall(toggle_space, spaces[2])
  if not ok then log_error("taris_agent", err) end
end
hl.bind("SUPER + P", function() _G.taris_music() end, { description = "Music player" })
local function off_space(w, ws)
  local s = space_on(ws)
  if w == nil or s == nil or s.is(w) then return end
  local m = w.monitor or hl.get_active_monitor()
  local under = m and m.active_workspace
  if under ~= nil then
    hl.dispatch(hl.dsp.window.move({ window = w, workspace = tostring(under.id), follow = false }))
  end
end
-- A window opening while one of these workspaces is shown: the workspace hidden so it's seen, and
-- the shell's own windows (Settings), which the rules above can't tell from the agent's, moved off it
hl.on("window.open", function(w)
  local ok, err = pcall(function()
    local s = space_on(hl.get_active_special_workspace())
    if s ~= nil and not s.is(w) then
      off_space(w, w.workspace)
      hl.dispatch(hl.dsp.workspace.toggle_special(s.name))
    end
  end)
  if not ok then log_error("window.open (spaces)", err) end
end)
local function is_space_app(w)
  return space_of(w) ~= nil
end
local function unless_space_app(dispatcher)
  return function()
    if not is_space_app(hl.get_active_window()) then hl.dispatch(dispatcher) end
  end
end
for key, d in pairs({
  ["SUPER + F"] = { hl.dsp.window.fullscreen({ mode = "fullscreen" }), "Fullscreen" },
  ["SUPER + SHIFT + M"] = { hl.dsp.window.fullscreen({ mode = "maximized" }), "Maximise" },
}) do
  pcall(hl.unbind, key)
  hl.bind(key, unless_space_app(d[1]), { description = d[2] })
end
for i = 1, 9 do
  pcall(hl.unbind, "SUPER + SHIFT + " .. i)
  hl.bind("SUPER + SHIFT + " .. i, unless_space_app(hl.dsp.window.move({ workspace = tostring(i) })), { description = "Move window to workspace" })
end
hl.on("window.move_to_workspace", function(w, ws)
  local ok, err = pcall(function()
    local s = space_of(w)
    if s ~= nil and ws ~= nil and ws.name ~= s.ws then
      hl.dispatch(hl.dsp.window.move({ window = w, workspace = s.ws, follow = false }))
    else
      off_space(w, ws)
    end
  end)
  if not ok then log_error("window.move_to_workspace (spaces)", err) end
end)

-- Window style (Settings > Window style writes window-style.conf: key=value lines)
local style = { bordertheme = "1", colors = "c4b5fd a855f7 da70d6", solid = "", inactive = "5b3a7a", fade = "1", swipe = "1", roundingon = "1", rounding = "70", bordersize = "1", gapsin = "1", gapsout = "1", columns = "0", floatnew = "0", opacity = "80", blur = "1", blursize = "12", blurpasses = "3", shellblur = "1" }
local function read_conf(path, into)
  local f = io.open(path)
  if not f then return end
  for line in f:lines() do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k then into[k] = v end
  end
  f:close()
end
read_conf(home .. "/.config/taris/window-style.conf", style)
-- The border in the colour scheme's colours (theme-border.conf, written by the shell on every
-- scheme change) until colours are picked on the Window style page
if style.bordertheme ~= "0" then
  local theme = {}
  read_conf(home .. "/.config/taris/theme-border.conf", theme)
  if theme.colors and theme.inactive then
    style.colors, style.inactive, style.solid = theme.colors, theme.inactive, ""
  end
end

-- Windows (same as the witchers-tweaks rounding, wide-columns and window-mode; border size and
-- gaps are set at the end of this file). New windows tile unless floatnew is on.
if style.roundingon == "1" then
  local percent = tonumber(style.rounding) or 70
  hl.config({ decoration = { rounding = math.floor(math.min(100, percent) * 32 / 100 + 0.5) } })
end
if style.columns == "1" then
  hl.config({ scrolling = { column_width = 0.97 } })
end
if style.floatnew == "1" then
  hl.window_rule({ match = { class = ".*" }, float = true })
  -- A floating window opens at the size it asks for: a viewer at its picture's or video's full
  -- size, a dialog at its saved one, often most of the screen. Larger than 65% x 70% of the
  -- screen, it opens at that size, centred, as SUPER + T does; it can still be made larger by hand
  -- (a max_size rule would forbid that). Errors go to $XDG_RUNTIME_DIR/taris-hypr.log.
  --
  -- Browsers, the web apps and VSCodium (and VS Code) open instead at the size they last had
  -- un-maximized, and a window that has only ever been tiled is maximized as far as they know, so
  -- that's the small size they first opened at (Chromium: 625 x 407). Their first window opens at
  -- 75% x 82% of the screen, centred; a popup of theirs (the same process) keeps the size it asks
  -- for.
  local function stale_size(w)
    local class = (w.class or ""):lower()
    if class ~= "chromium" and class ~= "firefox" and class ~= "codium" and class ~= "vscodium" and class ~= "code"
      and not class:find("^chrome%-") then
      return false
    end
    for _, other in ipairs(hl.get_windows() or {}) do
      if other.pid == w.pid and other.address ~= w.address then return false end
    end
    return true
  end
  local function fit_new_window(w)
    if w == nil or not w.floating or (tonumber(w.fullscreen) or 0) ~= 0 or w.monitor == nil then return end
    local m = w.monitor
    if stale_size(w) then
      hl.dispatch(hl.dsp.window.resize({ x = math.floor(m.width / m.scale * 0.75), y = math.floor(m.height / m.scale * 0.82), window = w }))
      hl.dispatch(hl.dsp.window.center({ window = w }))
      return
    end
    local size_w, size_h = w.size[1] or w.size.x, w.size[2] or w.size.y
    local max_w = math.floor(m.width / m.scale * 0.65)
    local max_h = math.floor(m.height / m.scale * 0.7)
    if size_w <= max_w and size_h <= max_h then return end
    hl.dispatch(hl.dsp.window.resize({ x = math.min(size_w, max_w), y = math.min(size_h, max_h), window = w }))
    hl.dispatch(hl.dsp.window.center({ window = w }))
  end
  hl.on("window.open", function(w)
    local ok, err = pcall(fit_new_window, w)
    if not ok then
      local f = io.open((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/taris-hypr.log", "a")
      if f then
        f:write(os.date("%H:%M:%S "), "window.open: ", tostring(err), "\n")
        f:close()
      end
    end
  end)
end

-- A floating window opening partly outside the screen's usable area (under the bar, or past an
-- edge) opens centred instead. X11 apps may ask for their own place, which Hyprland grants, and
-- some ask for the screen's corner, 0 x 0 (Hardware Locality, Steam's setup), under the bar; a
-- window opening where it fits keeps its place. Whether or not new windows open floating.
local function keep_on_screen(w)
  if w == nil or not w.floating or (tonumber(w.fullscreen) or 0) ~= 0 or w.monitor == nil then return end
  local m = w.monitor
  local r = m.reserved or {}
  local x, y = w.at[1] or w.at.x, w.at[2] or w.at.y
  local size_w, size_h = w.size[1] or w.size.x, w.size[2] or w.size.y
  local left, top = m.x + (r.left or 0), m.y + (r.top or 0)
  local right = m.x + m.width / m.scale - (r.right or 0)
  local bottom = m.y + m.height / m.scale - (r.bottom or 0)
  if x >= left and y >= top and x + size_w <= right and y + size_h <= bottom then return end
  hl.dispatch(hl.dsp.window.center({ window = w }))
end
hl.on("window.open", function(w)
  local ok, err = pcall(keep_on_screen, w)
  if not ok then
    local f = io.open((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/taris-hypr.log", "a")
    if f then
      f:write(os.date("%H:%M:%S "), "window.open (keep on screen): ", tostring(err), "\n")
      f:close()
    end
  end
end)

-- File pickers and other dialogs open like Taris's settings: centred above everything, the
-- rest dimmed, no border or shadow. Every dialog the desktop portal shows (whichever app asked),
-- and the usual Open/Save dialogs apps draw themselves, by title. modules/windowcontrols in the
-- shell matches the same windows (no window buttons on them).
local dialog_class = "^(xdg-desktop-portal-gtk)$"
local dialog_title = "^(Open (File|Files|Folder)|Select (a File|Folder|Directory)|Save (File|As|Image|Image As)|Choose (a )?File)(…|\\.\\.\\.)?$"
for _, match in ipairs({ { class = dialog_class }, { title = dialog_title } }) do
  hl.window_rule({ match = match, float = true, center = true, size = { 900, 600 }, border_size = 0, no_shadow = true, pin = true, dim_around = true })
end

if style.fade == "1" then
  hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "default", style = "slidefade 20%" })
end

-- 3-finger horizontal swipe between workspaces, tuned like the witchers-tweaks swipe: a short
-- swipe is enough and a quick flick commits. The standalone config doesn't define the gesture, so
-- it's only here (defining it twice in your own config is an error).
if style.swipe == "1" then
  pcall(hl.gesture, { fingers = 3, direction = "horizontal", action = "workspace" })
  hl.config({ gestures = {
    workspace_swipe_distance = 150, -- px for a full swipe (default 300)
    workspace_swipe_cancel_ratio = 0.15, -- commit after 15% instead of 50%
    workspace_swipe_min_speed_to_force = 5, -- a quick flick switches (default 30)
    workspace_swipe_create_new = true, -- past the last workspace makes a new one
    workspace_swipe_forever = true, -- keep going past neighbours in one swipe
  } })
end

-- Keybindings from the witchers-tweaks: CTRL+Q closes the window, SUPER+M minimizes it (into
-- special:minimized, where the dock brings it back) and SUPER+A shows or hides the agent workspace
-- (the shell's: taris_agent() above; SUPER+B, the browser, is in the standalone config)
hl.bind("CTRL + Q", hl.dsp.window.close(), { description = "Close window" })
hl.bind("SUPER + M", unless_space_app(hl.dsp.window.move({ workspace = "special:minimized", follow = false })), { description = "Minimise to dock" })
hl.bind("SUPER + A", hl.dsp.global("taris:agent"), { description = "Agent workspace" })

-- Keyboard options from the witchers-tweaks, added to the ones already set: left Ctrl and left
-- Super trade places (the right-hand keys stay), and Caps Lock is a plain Caps Lock: not a compose
-- key, and not cancelled by Shift (shift:both_capslock_cancel made Shift + 1 turn Caps Lock off
-- and type 1 instead of !). Settings > Keyboard & trackpad changes either; what it saves there is
-- loaded after this (hypr-settings.lua) and wins.
pcall(function()
  local options = hl.get_config("input.kb_options")
  options = (type(options) == "string" and options ~= "[[EMPTY]]") and options or ""
  local kept = {}
  for option in options:gmatch("[^,]+") do
    if option ~= "compose:caps" and option ~= "shift:both_capslock_cancel" and option ~= "ctrl:swap_lwin_lctl" then
      kept[#kept + 1] = option
    end
  end
  kept[#kept + 1] = "ctrl:swap_lwin_lctl"
  local new = table.concat(kept, ",")
  if new ~= options then
    hl.config({ input = { kb_options = new } })
  end
end)

-- The border: one colour (solid, else the first of colors). The shell changes the colours live (on
-- a scheme change) through taris_set_border, so it needn't reload Hyprland, which would close its
-- settings.
local function hex_list(spec)
  local colors = {}
  for hex in (spec or ""):gmatch("%x%x%x%x%x%x") do colors[#colors + 1] = hex:lower() end
  return colors
end

local function inactive_of(inactive)
  if inactive and inactive:match("^%x%x%x%x%x%x$") then return "rgba(" .. inactive .. "aa)" end
end

-- colors: the scheme's on a scheme change (its first is the border colour)
function _G.taris_set_border(colors, inactive)
  local active = hex_list(colors)[1]
  local col = { inactive_border = inactive_of(inactive) }
  if active then col.active_border = "rgba(" .. active .. "ee)" end
  hl.config({ general = { col = col } })
end
local solid = style.solid ~= "" and style.solid or style.colors
_G.taris_set_border(solid, style.inactive)

-- Title bars on floating windows (ported from the witchers-tweaks titlebars tweak): the
-- hyprbars plugin (/usr/lib/taris/hyprbars, built for the installed Hyprland by the taris-desktop
-- package's pacman hook) as an invisible strip just above the
-- window's top edge, to drag it by (double-click maximizes). The close, minimize and maximize
-- buttons grow out of the window's top-left corner on hover (modules/windowcontrols). Tiled
-- windows get no strip. A build for another Hyprland version doesn't load (Hyprland checks).
if style.titlebars ~= "0" then
  pcall(function()
    -- (A build an older install.sh made in the home folder comes first where there is one: swapping
    -- a loaded plugin for another copy would make Hyprland unload it in the running session)
    local dir = home .. "/.local/share/taris/hyprbars"
    local f = io.open(dir .. "/built-for")
    if not f then
      dir = "/usr/lib/taris/hyprbars"
      f = io.open(dir .. "/built-for")
    end
    local so = dir .. "/hyprbars.so"
    -- hl.plugin.load only lists the plugin; it has to be listed on every parse, loaded or not,
    -- or Hyprland unloads it, reloads the config and loops
    if f then
      f:close()
      pcall(hl.plugin.load, so)
    end
    if hl.plugin.hyprbars then
      hl.config({ plugin = { hyprbars = {
        bar_height = 14,
        bar_color = "rgba(00000000)",
        bar_title_enabled = false,
        bar_part_of_window = false,
        bar_precedence_over_border = false,
        bar_blur = false,
        on_double_click = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\" })'",
      } } })
      hl.window_rule({ match = { float = false }, ["hyprbars:no_bar"] = true })
      -- Only floating ones (a maximized one would sit below the strip): leaving fullscreen drops
      -- this rule's no_bar and with it the float = false one's, which isn't checked again, so a
      -- tiled window matching this came back from fullscreen 14 px lower
      hl.window_rule({ match = { float = true, fullscreen = true }, ["hyprbars:no_bar"] = true })
      hl.window_rule({ match = { class = dialog_class }, ["hyprbars:no_bar"] = true })
      hl.window_rule({ match = { title = dialog_title }, ["hyprbars:no_bar"] = true })
    end
  end)
end

-- SUPER + T: a tiled window made floating keeps its tiled size, often most of the screen, so it
-- shrinks to at most 65% x 70% of the screen and is centred. (Hyprland sends no event when a
-- window floats, so this is done by the key itself.) Errors go to $XDG_RUNTIME_DIR/taris-hypr.log,
-- as Hyprland's own log is usually off.
local function toggle_float()
  local w = hl.get_active_window()
  if w == nil or is_space_app(w) then return end
  local was_tiled = not w.floating
  local size_w, size_h = w.size[1] or w.size.x, w.size[2] or w.size.y
  hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
  if not was_tiled or (tonumber(w.fullscreen) or 0) ~= 0 or w.monitor == nil then return end

  local m = w.monitor
  local max_w = math.floor(m.width / m.scale * 0.65)
  local max_h = math.floor(m.height / m.scale * 0.7)
  if size_w > max_w or size_h > max_h then
    hl.dispatch(hl.dsp.window.resize({ x = math.min(size_w, max_w), y = math.min(size_h, max_h) }))
  end
  hl.dispatch(hl.dsp.window.center())
end
pcall(hl.unbind, "SUPER + T")
hl.bind("SUPER + T", function()
  local ok, err = pcall(toggle_float)
  if not ok then
    local f = io.open((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/taris-hypr.log", "a")
    if f then
      f:write(os.date("%H:%M:%S "), "SUPER + T: ", tostring(err), "\n")
      f:close()
    end
  end
end, { description = "Float or tile window" })

-- Floating windows resize by dragging their border; tiled windows don't. Follows Hyprland's
-- events, nothing polls.
if style.borderresize ~= "0" then
  local resizing = nil
  local function follow()
    local w = hl.get_active_window()
    local want = w ~= nil and w.floating == true and (tonumber(w.fullscreen) or 0) == 0
    if want ~= resizing then
      resizing = want
      hl.config({ general = { resize_on_border = want } })
    end
  end
  for _, event in ipairs({ "window.active", "window.update_rules", "window.fullscreen", "window.close", "workspace.active" }) do
    hl.on(event, function() pcall(follow) end)
  end
  pcall(follow)
end

-- No "Hyprland updated" window or donation nag: TarisOS updates Hyprland itself
hl.config({ ecosystem = { no_update_news = true, no_donation_nag = true } })

-- Settings from the Taris settings app (last, so they win)
pcall(dofile, home .. "/.config/taris/hypr-settings.lua")

-- Border size and gaps from the Window style page, after hypr-settings.lua so they win over the
-- same options set on the old Hyprland page
hl.config({ general = {
  border_size = tonumber(style.bordersize) or 1,
  gaps_in = tonumber(style.gapsin) or 1,
  gaps_out = tonumber(style.gapsout) or 1,
} })

-- Windows' opacity and the blur behind them, from the Window style page, after hypr-settings.lua
-- too. The blur's size and passes are Hyprland's one setting for everything it blurs, the shell's
-- panels included (their layer rule is the shell's: Colours.qml, with shellblur). With window
-- blur off, windows opt out by a rule, so the panels can still be blurred; with both off, nothing
-- is.
local opacity = math.max(0.3, math.min(1, (tonumber(style.opacity) or 80) / 100))
hl.config({ decoration = {
  active_opacity = opacity,
  inactive_opacity = opacity,
  blur = {
    enabled = style.blur ~= "0" or style.shellblur ~= "0",
    size = math.max(1, math.min(20, tonumber(style.blursize) or 12)),
    passes = math.max(1, math.min(4, tonumber(style.blurpasses) or 3)),
    -- Menus (right-click, ⋮, dropdowns) take their window's opacity: blurred behind, they stay
    -- readable over what's under them
    popups = true,
  },
} })
if style.blur == "0" then
  hl.window_rule({ name = "taris-no-window-blur", match = { class = ".*" }, no_blur = true })
end
-- Apps whose content would fade with the window stay solid: the browser and the web apps, video,
-- images, PDFs, screenshots, Nautilus's previews, graphics and VSCodium, the ones TarisOS ships and
-- the common ones from the App Store (by their app IDs). The terminal stays solid as a window too
-- and makes only its own background see-through, at the same opacity (kitty's background_opacity,
-- which the shell writes from this setting: services/WindowStyle.qml), so its text stays sharp.
local solid = {
  "chromium", "chrome-.*", "firefox", "codium", "VSCodium", "code", "com\\.microsoft\\.VSCode", "kitty",
  "mpv", "imv", "imv-dir", "swappy", "org\\.gnome\\.NautilusPreviewer", "org\\.gnome\\.Evince", "evince",
  "org\\.gnome\\.Loupe", "org\\.gnome\\.Showtime", "org\\.gnome\\.Totem", "org\\.gnome\\.Papers",
  "io\\.github\\.celluloid_player\\.Celluloid", "com\\.github\\.rafostar\\.Clapper", "vlc",
  "org\\.kde\\.haruna", "org\\.kde\\.gwenview", "org\\.kde\\.okular", "org\\.kde\\.kdenlive",
  "gimp", "krita", "org\\.inkscape\\.Inkscape", "blender", "com\\.obsproject\\.Studio",
}
hl.window_rule({
  name = "taris-solid-apps",
  match = { class = "^(" .. table.concat(solid, "|") .. ")$" },
  opacity = "1.0 override",
})
