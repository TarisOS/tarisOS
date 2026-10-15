// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <qdbusmessage.h>
#include <qhash.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qqmllist.h>
#include <qstring.h>
#include <qstringlist.h>
#include <qvariant.h>

#include <functional>

namespace taris::services {

// A phone, tablet or computer KDE Connect knows: kdeconnectd's /modules/kdeconnect/devices/<id>
// and its plugins' objects under it, read again whenever kdeconnectd says something changed
class KdeConnectDevice : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("KdeConnectDevice instances come from KdeConnect")

    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString name READ name NOTIFY changed)
    // "phone", "tablet", "laptop", "desktop", "tv" or "unknown"
    Q_PROPERTY(QString type READ type NOTIFY changed)
    Q_PROPERTY(bool reachable READ reachable NOTIFY changed)
    Q_PROPERTY(bool paired READ paired NOTIFY changed)
    // Pairing asked for from here, waiting for the device to accept
    Q_PROPERTY(bool pairRequested READ pairRequested NOTIFY changed)
    // Pairing asked for by the device, waiting for an answer here
    Q_PROPERTY(bool pairRequestedByPeer READ pairRequestedByPeer NOTIFY changed)
    // The code both screens show while pairing
    Q_PROPERTY(QString verificationKey READ verificationKey NOTIFY changed)
    // The plugins running for it ("kdeconnect_battery", "kdeconnect_ping"...)
    Q_PROPERTY(QStringList plugins READ plugins NOTIFY changed)
    Q_PROPERTY(bool hasBattery READ hasBattery NOTIFY batteryChanged)
    Q_PROPERTY(int charge READ charge NOTIFY batteryChanged)
    Q_PROPERTY(bool charging READ charging NOTIFY batteryChanged)
    // Its files being mounted to browse (browse())
    Q_PROPERTY(bool mounting READ mounting NOTIFY mountingChanged)

public:
    explicit KdeConnectDevice(const QString& id, QObject* parent = nullptr);

    [[nodiscard]] QString id() const;
    [[nodiscard]] QString name() const;
    [[nodiscard]] QString type() const;
    [[nodiscard]] bool reachable() const;
    [[nodiscard]] bool paired() const;
    [[nodiscard]] bool pairRequested() const;
    [[nodiscard]] bool pairRequestedByPeer() const;
    [[nodiscard]] QString verificationKey() const;
    [[nodiscard]] QStringList plugins() const;
    [[nodiscard]] bool hasBattery() const;
    [[nodiscard]] int charge() const;
    [[nodiscard]] bool charging() const;
    [[nodiscard]] bool mounting() const;

    Q_INVOKABLE void requestPairing();
    Q_INVOKABLE void acceptPairing();
    Q_INVOKABLE void cancelPairing();
    Q_INVOKABLE void unpair();
    Q_INVOKABLE void ping();
    Q_INVOKABLE void ring();
    Q_INVOKABLE void sendClipboard();
    // Sends files (local paths)
    Q_INVOKABLE void share(const QStringList& paths);
    // Mounts its files; mounted() gives the folder once they're there
    Q_INVOKABLE void browse();

signals:
    void changed();
    void batteryChanged();
    void mountingChanged();
    void mounted(const QString& path);
    void browseFailed(const QString& error);

public slots:
    void refresh();

private slots:
    void handleBattery(bool charging, int charge);

private:
    [[nodiscard]] QString path(const QString& plugin = {}) const;
    void call(const QString& plugin, const QString& iface, const QString& method, const QVariantList& args = {},
        const std::function<void(const QDBusMessage&)>& done = {}, int timeout = -1);
    void readBattery();

    QString m_id;
    QVariantMap m_props;
    QStringList m_plugins;
    bool m_hasBattery = false;
    int m_charge = -1;
    bool m_charging = false;
    bool m_mounting = false;
};

// KDE Connect (kdeconnectd, started by D-Bus the first time it's asked): the devices it knows, paired
// or only seen on the network. Nothing is asked of it until refresh(), so it isn't started for
// someone who never opens it.
class KdeConnect : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // kdeconnectd answered (it's installed and running)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // This computer's name as the devices see it
    Q_PROPERTY(QString name READ name NOTIFY nameChanged)
    // Paired first, then by name
    Q_PROPERTY(QQmlListProperty<taris::services::KdeConnectDevice> devices READ devices NOTIFY devicesChanged)

public:
    explicit KdeConnect(QObject* parent = nullptr);

    [[nodiscard]] bool available() const;
    [[nodiscard]] QString name() const;
    [[nodiscard]] QQmlListProperty<KdeConnectDevice> devices();

    // Reads the devices again, starting kdeconnectd if it isn't running
    Q_INVOKABLE void refresh();
    // Looks for devices on the network again
    Q_INVOKABLE void rescan();

signals:
    void availableChanged();
    void nameChanged();
    void devicesChanged();

private slots:
    void handleDeviceListChanged();
    void handleNameChanged(const QString& name);

private:
    void setAvailable(bool available);
    void sortDevices();

    bool m_available = false;
    bool m_connected = false;
    QString m_name;
    QHash<QString, KdeConnectDevice*> m_byId;
    QList<KdeConnectDevice*> m_devices;
};

} // namespace taris::services
