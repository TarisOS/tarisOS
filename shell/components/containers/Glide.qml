// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick

// Momentum scrolling, as the Witcher's Tweaks app drawer and settings do it: a touchpad scroll
// follows the fingers and keeps gliding once they lift (the compositor sends no momentum of its
// own), slowing with friction; a mouse wheel notch pushes the view into the same glide, adding up
// when spun. At an edge the scroll goes on to whatever scrolls around it.
// Declare one inside a Flickable, ListView or GridView (StyledFlickable and StyledListView have one).
// It covers the visible area behind the content: the wheel goes to whatever is topmost under the
// pointer first, so items and nested scroll views get it before this; the view's own wheel
// scrolling never gets it. It only takes the wheel (clicks and hover go through).
MouseArea {
    id: root

    required property Flickable flickable
    property bool horizontal
    readonly property bool isGlide: true // For outer(), which looks for the glides around this one

    property real velocity
    property double lastAt
    readonly property real friction: 3.4
    readonly property real speed: 1.4

    function lowest(): real {
        return horizontal ? flickable.originX - flickable.leftMargin : flickable.originY - flickable.topMargin;
    }

    function highest(): real {
        const end = horizontal ? flickable.originX + flickable.contentWidth + flickable.rightMargin - flickable.width : flickable.originY + flickable.contentHeight + flickable.bottomMargin - flickable.height;
        return Math.max(lowest(), end);
    }

    function position(): real {
        return horizontal ? flickable.contentX : flickable.contentY;
    }

    // Moves by d pixels within the bounds; false when it couldn't move at all
    function moveBy(d: real): bool {
        const to = Math.max(lowest(), Math.min(highest(), position() + d));
        if (Math.abs(to - position()) < 0.01)
            return false;
        if (horizontal)
            flickable.contentX = to;
        else
            flickable.contentY = to;
        return true;
    }

    // The glide of the nearest scroll view around this one's, which gets what this can't scroll
    function outer(): var {
        for (let p = flickable.parent; p; p = p.parent) {
            const glide = p.contentItem?.children?.find(c => c.isGlide && c !== root);
            if (glide)
                return glide;
        }
        return null;
    }

    // A wheel event; false when neither this nor a glide around it could use it
    function take(angleDelta: point, pixelDelta: point, phase: int): bool {
        const along = horizontal ? Math.abs(angleDelta.x) >= Math.abs(angleDelta.y) || flickable.contentHeight <= flickable.height : Math.abs(angleDelta.y) >= Math.abs(angleDelta.x);
        const pixels = horizontal ? (pixelDelta.x || pixelDelta.y) : pixelDelta.y;
        const angle = horizontal ? (angleDelta.x || angleDelta.y) : angleDelta.y;
        const now = Date.now();

        // The touchpad marks a scroll's start and end with events that move nothing; the end one
        // means the fingers lifted. The glides around this one follow along.
        if (pixels === 0 && angle === 0) {
            if (phase === Qt.ScrollEnd) {
                lift.stop();
                glide.running = Math.abs(velocity) > 60;
            } else if (phase === Qt.ScrollBegin) {
                glide.running = false;
                velocity = 0;
            }
            outer()?.take(angleDelta, pixelDelta, phase);
            return true;
        }

        if (!along)
            return outer()?.take(angleDelta, pixelDelta, phase) ?? false;

        if (pixels !== 0 || angle % 120 !== 0) {
            // Fingers on the touchpad: follow them, and track their speed
            const d = (pixels !== 0 ? -pixels : -angle / 3) * speed;
            const dt = Math.max(4, now - lastAt);
            const v = d * 1000 / dt;
            velocity = now - lastAt > 120 ? v : velocity * 0.5 + v * 0.5;
            lastAt = now;
            glide.running = false;
            if (!moveBy(d)) {
                velocity = 0;
                return outer()?.take(angleDelta, pixelDelta, phase) ?? false;
            }
            lift.restart();
        } else {
            // A mouse wheel notch: a push into the glide (none at the edge it pushes against)
            const push = -angle / 120 * 1400;
            if ((push < 0 && position() <= lowest() + 0.5) || (push > 0 && position() >= highest() - 0.5))
                return outer()?.take(angleDelta, pixelDelta, phase) ?? false;
            velocity = glide.running && Math.sign(push) === Math.sign(velocity) ? velocity + push : push;
            glide.running = true;
        }
        return true;
    }

    // In the content, under its items: a ListView or GridView keeps declared children on itself,
    // where z: -1 puts this behind the view, so the view would take the wheel first. Kept over the
    // visible area, as the content can be shorter than the view or start above it
    parent: flickable.contentItem
    x: flickable.contentX
    y: flickable.contentY
    width: flickable.width
    height: flickable.height
    z: -1
    enabled: flickable.interactive
    acceptedButtons: Qt.NoButton

    // Every wheel event stays with the glides: one passed on would reach the view's own wheel
    // scrolling, which moves by what it has added up since the last scroll it saw begin (seconds ago,
    // as it sees so few), and the view jumps back
    onWheel: event => {
        root.take(event.angleDelta, event.pixelDelta, event.phase);
        event.accepted = true;
    }

    // The fingers lifted (no events for a moment): glide
    property Timer _lift: Timer {
        id: lift

        interval: 50
        onTriggered: glide.running = Math.abs(root.velocity) > 60
    }

    property FrameAnimation _glide: FrameAnimation {
        id: glide

        onTriggered: {
            if (!root.moveBy(root.velocity * frameTime)) {
                running = false;
                return;
            }
            root.velocity *= Math.exp(-root.friction * frameTime);
            if (Math.abs(root.velocity) < 20)
                running = false;
        }
    }
}
