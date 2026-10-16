// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Taris.Config
import Taris.I18n
import qs.components
import qs.modules.nexus.common

// Security: lock screen behaviour, remote login, disk encryption and password
PageBase {
    id: root

    function inTerminal(cmd: string): void {
        Quickshell.execDetached(["sh", "-c", `exec ${GlobalConfig.general.apps.terminal.join(" ")} -e sh -c '${cmd}; echo; read -p "Press Enter to close" _'`]);
    }

    title: Tr.tr("Security")

    // Disk encryption (/usr/lib/taris/encrypt): plain, pending (at the next restart), encrypted or
    // unsupported (not a TarisOS disk layout)
    property string encryption
    property bool encryptOpen
    property string encryptError
    // The disk: the partition the root is on (for changing its password)
    property string encryptedPartition

    property Process _encryptionGet: Process {
        id: encryptionGet

        running: true
        command: ["sh", "-c", "[ -x /usr/lib/taris/encrypt ] && /usr/lib/taris/encrypt status; lsblk -n -s -o PATH,TYPE \"$(findmnt -n -o SOURCE / | sed 's/\\[.*//')\" | awk '$2 == \"part\" { print \"part \" $1; exit }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l);
                root.encryption = lines.find(l => !l.startsWith("part ")) ?? "unsupported";
                root.encryptedPartition = (lines.find(l => l.startsWith("part ")) ?? "").slice(5);
            }
        }
    }

    // Encrypting: the password checked (it's the keyring's), the system marked and made ready (as
    // root), the keyring's own password removed (the disk password is the login from then on), then
    // the restart that encrypts
    property Process _keyringCheck: Process {
        id: keyringCheck

        command: ["/usr/lib/taris/keyring-unprotect", "--check"]
        stdinEnabled: true
        stderr: StdioCollector {
            id: keyringCheckErr
        }
        onStarted: {
            write(encryptPassword.field.text);
            stdinEnabled = false;
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            if (code === 0)
                encryptPrepare.running = true;
            else
                root.encryptError = keyringCheckErr.text.trim().split("\n").pop() || Tr.tr("Wrong password");
        }
    }

    property Process _encryptPrepare: Process {
        id: encryptPrepare

        command: ["pkexec", "/usr/lib/taris/encrypt", "prepare"]
        stderr: StdioCollector {
            id: encryptPrepareErr
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            if (code === 0) {
                keyringUnprotect.running = true;
            } else {
                root.encryptError = encryptPrepareErr.text.trim().split("\n").pop() || Tr.tr("Encryption couldn't be set up");
                encryptionGet.running = true;
            }
        }
    }

    property Process _keyringUnprotect: Process {
        id: keyringUnprotect

        command: ["/usr/lib/taris/keyring-unprotect"]
        stdinEnabled: true
        onStarted: {
            write(encryptPassword.field.text);
            stdinEnabled = false;
        }
        onExited: {
            encryptPassword.field.text = "";
            root.encryption = "pending";
            Quickshell.execDetached(["systemctl", "reboot"]);
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Tr.tr("Lock screen")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Use the wallpaper as the lock screen background")
            checked: Config.lock.useWallpaper
            onToggled: GlobalConfig.lock.useWallpaper = checked
        }

        ToggleRow {
            text: Tr.tr("Hide notifications on the lock screen")
            checked: Config.lock.hideNotifs
            onToggled: GlobalConfig.lock.hideNotifs = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Power buttons on the lock screen")
            subtext: Tr.tr("Shut down, restart, sleep and stash without unlocking")
            checked: GlobalConfig.lock.enableSessionControls
            onToggled: GlobalConfig.lock.enableSessionControls = checked
        }

        SectionHeader {
            visible: root.encryption !== "" && root.encryption !== "unsupported"
            text: Tr.tr("Disk encryption")
        }

        InfoRow {
            visible: root.encryption === "pending" || root.encryption === "encrypted"
            first: true
            last: root.encryption !== "encrypted"
            icon: root.encryption === "encrypted" ? "lock" : "lock_clock"
            label: root.encryption === "encrypted" ? Tr.tr("Encrypted") : Tr.tr("Encrypts at the next restart")
        }

        RowButton {
            visible: root.encryption === "encrypted" && root.encryptedPartition !== ""
            last: true
            icon: "key"
            text: Tr.tr("Change disk password")
            onClicked: root.inTerminal(`sudo cryptsetup luksChangeKey ${root.encryptedPartition}`)
        }

        RowButton {
            visible: root.encryption === "plain"
            first: true
            last: !root.encryptOpen
            icon: "enhanced_encryption"
            text: Tr.tr("Encrypt the disk")
            onClicked: root.encryptOpen = !root.encryptOpen
        }

        TextFieldRow {
            id: encryptPassword

            visible: root.encryption === "plain" && root.encryptOpen
            label: Tr.tr("User password")
            errorText: root.encryptError
            subtext: root.encryptError
            Component.onCompleted: field.echoMode = TextInput.Password
        }

        RowButton {
            visible: root.encryption === "plain" && root.encryptOpen
            last: true
            icon: "restart_alt"
            text: Tr.tr("Encrypt and restart")
            disabled: encryptPassword.field.text === "" || keyringCheck.running || encryptPrepare.running || keyringUnprotect.running
            onClicked: {
                root.encryptError = "";
                keyringCheck.stdinEnabled = true;
                keyringUnprotect.stdinEnabled = true;
                keyringCheck.running = true;
            }
        }

        SectionHeader {
            text: Tr.tr("Account")
        }

        RowButton {
            first: true
            last: true
            icon: "password"
            text: Tr.tr("Change password")
            onClicked: root.inTerminal("passwd")
        }
    }
}
