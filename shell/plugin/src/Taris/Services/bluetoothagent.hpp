// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <qdbusabstractadaptor.h>
#include <qdbusextratypes.h>
#include <qdbusmessage.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qstringlist.h>
#include <qvariant.h>

class QDBusServiceWatcher;

namespace taris::services {

class BluetoothAgent;

// org.bluez.Agent1 on the system bus: BlueZ's questions, handed to BluetoothAgent. The slots carry
// BlueZ's method names, and the message, so an answer can wait for the user
class BluetoothAgentAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")

public:
    explicit BluetoothAgentAdaptor(BluetoothAgent* agent);

    // NOLINTBEGIN(readability-identifier-naming) BlueZ's method names
public slots:
    void Release();
    QString RequestPinCode(const QDBusObjectPath& device, const QDBusMessage& msg);
    void DisplayPinCode(const QDBusObjectPath& device, const QString& pincode);
    uint RequestPasskey(const QDBusObjectPath& device, const QDBusMessage& msg);
    void DisplayPasskey(const QDBusObjectPath& device, uint passkey, ushort entered);
    void RequestConfirmation(const QDBusObjectPath& device, uint passkey, const QDBusMessage& msg);
    void RequestAuthorization(const QDBusObjectPath& device, const QDBusMessage& msg);
    void AuthorizeService(const QDBusObjectPath& device, const QString& uuid, const QDBusMessage& msg);
    void Cancel();
    // NOLINTEND(readability-identifier-naming)

private:
    BluetoothAgent* m_agent;
};

// The session's Bluetooth agent: BlueZ asks it whether a device may pair or connect, and for codes.
// Registered as BlueZ's default agent (again whenever bluetoothd restarts) as soon as the shell
// first uses it. Paired devices connect without a question; everything else waits for the shell's
// prompt (modules/bluetooth). BlueZ asks one thing at a time, and cancels a question after a while.
class BluetoothAgent : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // What BlueZ is waiting for an answer to, or what to show while a device pairs (None: nothing)
    Q_PROPERTY(Kind kind READ kind NOTIFY requestChanged)
    Q_PROPERTY(QString deviceName READ deviceName NOTIFY requestChanged)
    Q_PROPERTY(QString deviceAddress READ deviceAddress NOTIFY requestChanged)
    // BlueZ's icon name for the device ("audio-headset", "input-keyboard"...)
    Q_PROPERTY(QString deviceIcon READ deviceIcon NOTIFY requestChanged)
    // The code to compare (Confirm) or to type on the device (DisplayPasskey: six digits,
    // DisplayPinCode: the PIN)
    Q_PROPERTY(QString code READ code NOTIFY requestChanged)
    // How many of the code's digits have been typed on the device (DisplayPasskey)
    Q_PROPERTY(int entered READ entered NOTIFY requestChanged)
    // Whether BlueZ has this as its agent
    Q_PROPERTY(bool registered READ registered NOTIFY registeredChanged)

public:
    enum Kind {
        None,
        Confirm,          // Both screens show a code: the same one? (accept, reject)
        Authorize,        // A device asks to pair, with no code (accept, reject)
        AuthorizeService, // A device that isn't paired asks to connect (accept, reject)
        PinCode,          // An older device's PIN (submit, reject)
        Passkey,          // The six digits the device shows (submit, reject)
        DisplayPinCode,   // The PIN to type on the device (reject cancels the pairing)
        DisplayPasskey,   // The six digits to type on the device (reject cancels the pairing)
    };
    Q_ENUM(Kind)

    explicit BluetoothAgent(QObject* parent = nullptr);

    [[nodiscard]] Kind kind() const;
    [[nodiscard]] QString deviceName() const;
    [[nodiscard]] QString deviceAddress() const;
    [[nodiscard]] QString deviceIcon() const;
    [[nodiscard]] QString code() const;
    [[nodiscard]] int entered() const;
    [[nodiscard]] bool registered() const;

    // Yes to Confirm, Authorize and AuthorizeService
    Q_INVOKABLE void accept();
    // The PIN (PinCode) or the six digits (Passkey)
    Q_INVOKABLE void submit(const QString& value);
    // No to any question; for DisplayPinCode and DisplayPasskey, the pairing is cancelled
    Q_INVOKABLE void reject();

    // From BluetoothAgentAdaptor
    void handleRelease();
    void handleRequest(Kind kind, const QDBusObjectPath& device, const QDBusMessage& msg, const QString& code = {});
    void handleDisplay(Kind kind, const QDBusObjectPath& device, const QString& code, int entered);
    void handleAuthorizeService(const QDBusObjectPath& device, const QDBusMessage& msg);
    void handleCancel();

signals:
    void requestChanged();
    void registeredChanged();

private slots:
    void handleDevicePropertiesChanged(const QString& iface, const QVariantMap& changed, const QStringList& invalidated);

private:
    void registerWithBluez();
    void requestDefault();
    void setRegistered(bool registered);
    // Shows a question or a code for the device at path, reading its name, address and icon
    void show(Kind kind, const QString& path, const QString& code, int entered);
    // Nothing shown or waiting any more; a question still waiting is answered with error first
    void clear(const QString& error = {});
    void watchDevice(const QString& path);
    void unwatchDevice();

    Kind m_kind = None;
    QString m_devicePath;
    QString m_deviceName;
    QString m_deviceAddress;
    QString m_deviceIcon;
    QString m_code;
    int m_entered = 0;
    // The question's message, answered once the user has: invalid while nothing waits
    QDBusMessage m_pending;
    bool m_hasPending = false;
    // The device whose pairing a code is shown for: its Paired turning true ends the showing
    QString m_watchedPath;
    bool m_registered = false;
    QDBusServiceWatcher* m_watcher = nullptr;
};

} // namespace taris::services
