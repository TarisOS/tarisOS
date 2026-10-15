// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services

// Close, minimize and maximize buttons for floating windows (ported from the
// witchers-tweaks titlebars tweak). Hovering just above a floating window's
// top-left corner pops the three buttons out of its top edge, on their own
// over whatever is behind; they go back in a moment after the pointer leaves.
// A floating window is never narrower than the buttons and the corner after
// them.
//
// Each visible floating window gets a small surface of its own over that
// corner (just above the window, so its content stays clickable). A window
// whose corner is covered by a window focused more recently gets none.
Scope {
  id: root

  // The invisible drag strip's height (bar_height in hypr-taris.lua).
  readonly property int stripHeight: 14
  property int borderSize: 2
  property int rounding: 0

  // The buttons: each a dot this wide, clickable a little around it
  readonly property int buttonSize: 16
  readonly property int buttonSpacing: 9
  readonly property int hitPadding: 3
  // The space above the window they pop out into
  readonly property int edge: buttonSize + 10

  // ---------- the smallest a floating window gets ----------

  // As wide as the buttons and the window's top-right corner after them, a
  // little over, and as tall: Hyprland's min_size for each floating window,
  // unless the app asks for more itself (set_prop takes over the app's own
  // minimum, so the larger of the two, each way). Resizing stops there, and a
  // smaller window grows to it.
  readonly property int minWidth: Math.ceil(controlsEnd() + rounding + 8)
  // Address -> the minimum size given to it
  property var sized: ({})

  // Where the buttons start and end, from the window's left edge
  function buttonsX() {
    return borderSize + Math.max(10, rounding * 0.6)
  }

  function controlsEnd() {
    return buttonsX() + 3 * buttonSize + 2 * buttonSpacing + hitPadding + 6
  }

  function applyMinWidth() {
    if (minSizer.running) return
    var todo = []
    for (var a in windowInfo) if (sized[a] !== minWidth) todo.push(a)
    if (todo.length === 0) return
    var next = Object.assign({}, sized)
    for (var i = 0; i < todo.length; i++) next[todo[i]] = minWidth
    sized = next
    minSizer.command = ["bash", "-c",
      "min=$1; shift; for a in \"$@\"; do read -r w h <<<\"$(hyprctl getprop address:0x$a min_size)\"; "
      + "w=${w%.*}; h=${h%.*}; [[ $w =~ ^[0-9]+$ && $h =~ ^[0-9]+$ ]] || continue; "
      + "if (( w < min || h < min )); then (( w = w < min ? min : w, h = h < min ? min : h )); "
      + "hyprctl dispatch \"hl.dsp.window.set_prop({ prop = 'min_size', value = '$w $h', window = 'address:0x$a' })\" >/dev/null; "
      + "fi; done", "_", String(minWidth)].concat(todo)
    minSizer.running = true
  }

  // The border's width and the windows' rounding, where the buttons sit
  function readBorder() { borderReader.running = true }

  onWindowInfoChanged: applyMinWidth()
  onMinWidthChanged: applyMinWidth()

  // Windows that came while it ran get theirs next
  Process {
    id: minSizer

    onExited: root.applyMinWidth()
  }

  Process {
    id: borderReader
    command: ["bash", "-c", "hyprctl getoption general:border_size -j; echo; hyprctl getoption decoration:rounding -j"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.split("\n").filter(function(l) { return l.trim() !== "" })
        try {
          root.borderSize = JSON.parse(lines[0]).int || 2
          root.rounding = JSON.parse(lines[1]).int || 0
        } catch (e) {}
      }
    }
  }
  Component.onCompleted: { readBorder(); poll() }

  // ---------- the windows ----------

  // Where the floating windows are, read straight from Hyprland's request
  // socket ("j/clients") rather than through Quickshell's window list, whose
  // refresh would make everything else watching windows (the dock) redo its
  // work too. Hyprland's events (opened, closed, floated, focused,
  // fullscreen, workspace changes) ask again; floating windows can also move
  // without an event, so while any is on screen their places are asked for a
  // few times a second. Nothing updates unless one actually changed, and
  // with none on screen nothing runs.

  // Visible floating windows by address: { x, y, w, h, history }.
  property var windowInfo: ({})
  property string snapshot: ""
  property string reply: ""

  function addressKey(value) { return String(value || "").replace(/^0x/, "").toLowerCase() }

  Socket {
    id: query
    path: Hyprland.requestSocketPath
    parser: SplitParser {
      splitMarker: ""
      // Hyprland closes the connection after its reply; hanging up as soon
      // as the reply is whole keeps that from being logged as an error.
      onRead: data => {
        root.reply += data
        if (/\]\s*$/.test(root.reply) && root.take(root.reply)) { root.reply = ""; query.connected = false }
      }
    }
    onConnectedChanged: {
      if (connected) {
        root.reply = ""
        write("j/clients")
        flush()
      } else {
        if (root.reply !== "") root.take(root.reply)
        root.reply = ""
      }
    }
  }

  function poll() { if (!query.connected) query.connected = true }

  function take(text) {
    var list
    try { list = JSON.parse(text) } catch (e) { return false }
    // The workspace each monitor shows. Until Hyprland has said (just after
    // the shell starts), every window would look hidden: asked again shortly.
    var shown = ({})
    var monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    if (monitors.length === 0 || monitors.some(function(m) { return !m.activeWorkspace })) {
      eventPoll.restart()
      return true
    }
    for (var m = 0; m < monitors.length; m++)
      if (monitors[m].activeWorkspace) shown[monitors[m].id] = monitors[m].activeWorkspace.id
    var info = ({})
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (!c.floating || c.fullscreen || !c.workspace || c.workspace.id < 0 || shown[c.monitor] !== c.workspace.id) continue
      // Dialogs opened like the settings (hypr-taris.lua's dialog rules) get no buttons
      if (/^xdg-desktop-portal-gtk$/.test(c.class) || /^(Open (File|Files|Folder)|Select (a File|Folder|Directory)|Save (File|As|Image|Image As)|Choose (a )?File)(…|\.\.\.)?$/.test(c.title)) continue
      info[addressKey(c.address)] = { x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1], history: c.focusHistoryID }
    }
    var next = JSON.stringify(info)
    if (next === snapshot) return true
    snapshot = next
    windowInfo = info
    return true
  }

  readonly property bool anyFloating: snapshot !== "" && snapshot !== "{}"
  Timer {
    interval: 400
    repeat: true
    running: root.anyFloating
    onTriggered: root.poll()
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (/^(openwindow|closewindow|movewindowv2|changefloatingmode|fullscreen|workspacev2|activewindowv2|focusedmonv2)$/.test(name))
        eventPoll.restart()
    }
  }
  Timer { id: eventPoll; interval: 60; onTriggered: root.poll() }

  // The windows themselves are the model (so each keeps its surface while it
  // moves). A corner covered by a more recently focused window gets no buttons.
  readonly property var floating: {
    var info = windowInfo
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var list = []
    for (var i = 0; i < tops.length; i++) {
      var w = tops[i] ? info[addressKey(tops[i].address)] : null
      if (w) list.push({ top: tops[i], x: w.x, y: w.y, w: w.w, h: w.h, history: w.history })
    }
    return list.filter(function(a) {
      var zx = a.x, zy = a.y - root.stripHeight - 30
      return !list.some(function(b) {
        return b !== a && b.history < a.history
          && b.x < zx + 150 && b.x + b.w > zx && b.y < a.y && b.y + b.h > zy
      })
    }).map(function(a) { return a.top })
  }

  function dispatch(lua) { Quickshell.execDetached(["hyprctl", "dispatch", lua]) }

  Variants {
    model: root.floating

    PanelWindow {
      id: area
      required property var modelData
      readonly property var info: root.windowInfo[root.addressKey(modelData.address)] || ({ x: 0, y: 0, w: 1, h: 1 })
      readonly property var mon: modelData.monitor || ({ name: "", x: 0, y: 0 })
      readonly property string address: "0x" + String(modelData.address).replace(/^0x/, "")

      // The shell's panels, its bar's popouts and its overlays (Settings, the App Store) are on the
      // same layer as this surface, which is made after them and so sits over them: over an open
      // one it took the pointer through it (the buttons opened over it, and the panel, left, closed
      // and opened again). While one is open on this screen, this surface goes.
      readonly property var screenState: screen ? ShellState.forScreen(screen) : null
      readonly property var popouts: screen ? ShellState.componentsFor(screen)?.panels?.popouts ?? null : null
      readonly property bool panelOpen: (!!screenState && (screenState.dashboard || screenState.launcher
        || screenState.session || screenState.utilities || screenState.sidebar || screenState.dock
        || screenState.osd)) || !!popouts?.hasCurrent || !!popouts?.isDetached

      // Window geometry (layout coordinates); the border box is around it.
      readonly property real wx: info.x
      readonly property real wy: info.y
      readonly property int bw: root.borderSize

      screen: {
        for (var i = 0; i < Quickshell.screens.length; i++)
          if (Quickshell.screens[i].name === area.mon.name) return Quickshell.screens[i]
        return null
      }
      anchors { top: true; left: true }
      margins.left: wx - bw - mon.x
      margins.top: Math.max(0, wy - bw - mon.y - root.edge)
      implicitWidth: root.controlsEnd() + 4
      implicitHeight: root.edge
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "taris-titlebars"
      WlrLayershell.layer: WlrLayer.Top
      visible: !panelOpen
      onPanelOpenChanged: if (panelOpen && shown) shown = false

      // Growing out of the window on hover, back in after a moment.
      // Opens when the pointer rests above the corner of a window that isn't
      // moving: while a window is dragged its surface trails behind it, and
      // the pointer sweeping over that spot mustn't open the buttons there.
      property bool shown: false
      property real grow: shown ? 1 : 0
      Behavior on grow { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }

      property double movedAt: 0
      onWxChanged: windowMoved()
      onWyChanged: windowMoved()
      function windowMoved() {
        movedAt = Date.now()
        if (shown) shown = false
      }

      HoverHandler {
        id: hover
        onHoveredChanged: {
          if (hovered) {
            hideDelay.stop()
            if (!area.shown) rest.restart()
          } else {
            rest.stop()
            hideDelay.restart()
          }
        }
      }
      Timer {
        id: rest
        interval: 120
        onTriggered: {
          if (!hover.hovered) return
          if (Date.now() - area.movedAt < 500) { rest.restart(); return }
          root.readBorder()
          area.shown = true
        }
      }
      Timer { id: hideDelay; interval: 450; onTriggered: if (!hover.hovered) area.shown = false }

      // The buttons, rising out of the window's top edge as they grow, in the
      // top bar's colors: dots in its icon color, symbols in its background
      // color.
      Row {
        id: buttons
        x: root.buttonsX() + 4 - root.hitPadding
        y: root.edge - root.hitPadding - (root.edge + root.buttonSize) / 2 * area.grow
        spacing: root.buttonSpacing - 2 * root.hitPadding
        opacity: Math.min(1, area.grow)
        scale: 0.6 + 0.4 * area.grow
        transformOrigin: Item.Bottom
        Repeater {
          model: [
            { symbol: "×", action: "close" },
            { symbol: "−", action: "minimize" },
            { symbol: "+", action: "maximize" }
          ]
          Item {
            id: button
            required property var modelData
            width: root.buttonSize + 2 * root.hitPadding
            height: width
            Rectangle {
              anchors.centerIn: parent
              width: root.buttonSize
              height: root.buttonSize
              radius: root.buttonSize / 2
              color: Colours.palette.m3onSurface
              scale: press.pressed ? 0.88 : 1
              Behavior on scale { NumberAnimation { duration: 90 } }
              Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                text: button.modelData.symbol
                color: Colours.palette.m3surface
                font.pixelSize: 13
                font.bold: true
              }
            }
            MouseArea {
              id: press
              anchors.fill: parent
              enabled: area.shown
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var a = "address:" + area.address
                if (button.modelData.action === "close")
                  root.dispatch("hl.dsp.window.close({ window = \"" + a + "\" })")
                else if (button.modelData.action === "minimize")
                  // Into special:minimized; the dock brings it back
                  root.dispatch("hl.dsp.window.move({ window = \"" + a + "\", workspace = \"special:minimized\", follow = false })")
                else
                  Quickshell.execDetached(["bash", "-c", "hyprctl dispatch 'hl.dsp.focus({ window = \"" + a + "\" })' >/dev/null && hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\" })' >/dev/null"])
              }
            }
          }
        }
      }
    }
  }
}
