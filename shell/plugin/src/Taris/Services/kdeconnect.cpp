// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#include "kdeconnect.hpp"

#include <qdbusargument.h>
#include <qdbusconnection.h>
#include <qdbuspendingcall.h>
#include <qdbusservicewatcher.h>
#include <qloggingcategory.h>
#include <qurl.h>

#include <algorithm>

namespace {

Q_LOGGING_CATEGORY(lcKdeConnect, "taris.services.kdeconnect", QtInfoMsg)

} // namespace

namespace taris::services {

using Qt::StringLiterals::operator""_s;

namespace {

const QString k_service = u"org.kde.kdeconnect"_s;
const QString k_daemonPath = u"/modules/kdeconnect"_s;
const QString k_daemonIface = u"org.kde.kdeconnect.daemon"_s;
const QString k_deviceIface = u"org.kde.kdeconnect.device"_s;
const QString k_propsIface = u"org.freedesktop.DBus.Properties"_s;

// Calls kdeconnectd; done gets the reply, an error included (logged here)
void callKdeConnect(QObject* context, const QString& path, const QString& iface, const QString& method,
    const QVariantList& args, const std::function<void(const QDBusMessage&)>& done, int timeout = -1) {
    auto msg = QDBusMessage::createMethodCall(k_service, path, iface, method);
    msg.setArguments(args);

    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg, timeout), context);
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, context, [method, done](QDBusPendingCallWatcher* self) {
        const QDBusMessage reply = self->reply();
        if (reply.type() == QDBusMessage::ErrorMessage)
            qCWarning(lcKdeConnect) << "Call to" << method << "failed:" << reply.errorMessage();
        if (done)
            done(reply);
        self->deleteLater();
    });
    // NOLINTNEXTLINE(clang-analyzer-cplusplus.NewDeleteLeaks) watcher is parented and self-deletes
}

bool ok(const QDBusMessage& reply) {
    return reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty();
}

QVariantMap propsOf(const QDBusMessage& reply) {
    return ok(reply) ? qdbus_cast<QVariantMap>(reply.arguments().constFirst()) : QVariantMap{};
}

} // namespace

KdeConnectDevice::KdeConnectDevice(const QString& id, QObject* parent)
    : QObject(parent)
    , m_id(id) {
    auto bus = QDBusConnection::sessionBus();
    for (const auto& signal : { u"pairStateChanged"_s, u"reachableChanged"_s, u"nameChanged"_s, u"typeChanged"_s,
             u"pluginsChanged"_s, u"linksChanged"_s }) {
        if (!bus.connect(k_service, path(), k_deviceIface, signal, this, SLOT(refresh())))
            qCWarning(lcKdeConnect) << "Failed to connect to" << signal << "of" << m_id;
    }
    bus.connect(k_service, path(u"battery"_s), u"org.kde.kdeconnect.device.battery"_s, u"refreshed"_s, this,
        SLOT(handleBattery(bool, int)));
}

QString KdeConnectDevice::id() const {
    return m_id;
}

QString KdeConnectDevice::name() const {
    const auto name = m_props.value(u"name"_s).toString();
    return name.isEmpty() ? m_id : name;
}

QString KdeConnectDevice::type() const {
    const auto type = m_props.value(u"type"_s).toString();
    if (type == u"smartphone"_s)
        return u"phone"_s;
    return type.isEmpty() ? u"unknown"_s : type;
}

bool KdeConnectDevice::reachable() const {
    return m_props.value(u"isReachable"_s).toBool();
}

bool KdeConnectDevice::paired() const {
    return m_props.value(u"isPaired"_s).toBool();
}

bool KdeConnectDevice::pairRequested() const {
    return m_props.value(u"isPairRequested"_s).toBool();
}

bool KdeConnectDevice::pairRequestedByPeer() const {
    return m_props.value(u"isPairRequestedByPeer"_s).toBool();
}

QString KdeConnectDevice::verificationKey() const {
    return m_props.value(u"verificationKey"_s).toString();
}

QStringList KdeConnectDevice::plugins() const {
    return m_plugins;
}

bool KdeConnectDevice::hasBattery() const {
    return m_hasBattery;
}

int KdeConnectDevice::charge() const {
    return m_charge;
}

bool KdeConnectDevice::charging() const {
    return m_charging;
}

bool KdeConnectDevice::mounting() const {
    return m_mounting;
}

void KdeConnectDevice::requestPairing() {
    call({}, k_deviceIface, u"requestPairing"_s);
}

void KdeConnectDevice::acceptPairing() {
    call({}, k_deviceIface, u"acceptPairing"_s);
}

void KdeConnectDevice::cancelPairing() {
    call({}, k_deviceIface, u"cancelPairing"_s);
}

void KdeConnectDevice::unpair() {
    call({}, k_deviceIface, u"unpair"_s);
}

void KdeConnectDevice::ping() {
    call(u"ping"_s, u"org.kde.kdeconnect.device.ping"_s, u"sendPing"_s);
}

void KdeConnectDevice::ring() {
    call(u"findmyphone"_s, u"org.kde.kdeconnect.device.findmyphone"_s, u"ring"_s);
}

void KdeConnectDevice::sendClipboard() {
    call(u"clipboard"_s, u"org.kde.kdeconnect.device.clipboard"_s, u"sendClipboard"_s);
}

void KdeConnectDevice::share(const QStringList& paths) {
    QStringList urls;
    for (const auto& p : paths)
        urls << QUrl::fromLocalFile(p).toString();
    if (!urls.isEmpty())
        call(u"share"_s, u"org.kde.kdeconnect.device.share"_s, u"shareUrls"_s, { urls });
}

void KdeConnectDevice::browse() {
    if (m_mounting)
        return;
    m_mounting = true;
    emit mountingChanged();

    const auto sftp = u"org.kde.kdeconnect.device.sftp"_s;
    const auto finish = [this] {
        m_mounting = false;
        emit mountingChanged();
    };
    // Mounting waits for the device to answer: up to a minute
    call(u"sftp"_s, sftp, u"mountAndWait"_s, {}, [this, sftp, finish](const QDBusMessage& reply) {
        if (ok(reply) && reply.arguments().constFirst().toBool()) {
            call(u"sftp"_s, sftp, u"mountPoint"_s, {}, [this, finish](const QDBusMessage& point) {
                finish();
                if (ok(point) && !point.arguments().constFirst().toString().isEmpty())
                    emit mounted(point.arguments().constFirst().toString());
                else
                    emit browseFailed({});
            });
        } else {
            call(u"sftp"_s, sftp, u"getMountError"_s, {}, [this, finish](const QDBusMessage& error) {
                finish();
                emit browseFailed(ok(error) ? error.arguments().constFirst().toString() : QString());
            });
        }
    }, 60000);
}

void KdeConnectDevice::refresh() {
    call({}, k_propsIface, u"GetAll"_s, { k_deviceIface }, [this](const QDBusMessage& reply) {
        if (!ok(reply))
            return;
        m_props = propsOf(reply);
        call({}, k_deviceIface, u"loadedPlugins"_s, {}, [this](const QDBusMessage& plugins) {
            m_plugins = ok(plugins) ? plugins.arguments().constFirst().toStringList() : QStringList{};
            emit changed();
            readBattery();
        });
    });
}

void KdeConnectDevice::handleBattery(bool charging, int charge) {
    m_hasBattery = charge >= 0;
    m_charging = charging;
    m_charge = charge;
    emit batteryChanged();
}

QString KdeConnectDevice::path(const QString& plugin) const {
    const auto device = u"%1/devices/%2"_s.arg(k_daemonPath, m_id);
    return plugin.isEmpty() ? device : u"%1/%2"_s.arg(device, plugin);
}

void KdeConnectDevice::call(const QString& plugin, const QString& iface, const QString& method,
    const QVariantList& args, const std::function<void(const QDBusMessage&)>& done, int timeout) {
    callKdeConnect(this, path(plugin), iface, method, args, done, timeout);
}

void KdeConnectDevice::readBattery() {
    if (!m_plugins.contains(u"kdeconnect_battery"_s)) {
        if (m_hasBattery) {
            m_hasBattery = false;
            emit batteryChanged();
        }
        return;
    }
    call(u"battery"_s, k_propsIface, u"GetAll"_s, { u"org.kde.kdeconnect.device.battery"_s },
        [this](const QDBusMessage& reply) {
            const auto props = propsOf(reply);
            if (props.isEmpty())
                return;
            m_hasBattery = props.value(u"hasBattery"_s, true).toBool();
            m_charge = props.value(u"charge"_s, -1).toInt();
            m_charging = props.value(u"isCharging"_s).toBool();
            emit batteryChanged();
        });
}

KdeConnect::KdeConnect(QObject* parent)
    : QObject(parent) {
    auto bus = QDBusConnection::sessionBus();
    bus.connect(k_service, k_daemonPath, k_daemonIface, u"deviceListChanged"_s, this, SLOT(handleDeviceListChanged()));
    bus.connect(k_service, k_daemonPath, k_daemonIface, u"announcedNameChanged"_s, this,
        SLOT(handleNameChanged(QString)));

    // kdeconnectd starting (after a crash, or by D-Bus) or going away
    auto* watcher = new QDBusServiceWatcher(k_service, bus,
        QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration, this);
    connect(watcher, &QDBusServiceWatcher::serviceRegistered, this, [this] {
        if (m_connected)
            refresh();
    });
    connect(watcher, &QDBusServiceWatcher::serviceUnregistered, this, [this] {
        setAvailable(false);
    });
}

bool KdeConnect::available() const {
    return m_available;
}

QString KdeConnect::name() const {
    return m_name;
}

QQmlListProperty<KdeConnectDevice> KdeConnect::devices() {
    return QQmlListProperty<KdeConnectDevice>(this, &m_devices);
}

void KdeConnect::refresh() {
    m_connected = true;
    callKdeConnect(this, k_daemonPath, k_daemonIface, u"devices"_s, { false, false }, [this](const QDBusMessage& reply) {
        if (!ok(reply)) {
            setAvailable(false);
            return;
        }
        setAvailable(true);

        const auto ids = reply.arguments().constFirst().toStringList();
        bool listChanged = false;
        for (auto it = m_byId.begin(); it != m_byId.end();) {
            if (ids.contains(it.key())) {
                ++it;
                continue;
            }
            m_devices.removeAll(it.value());
            it.value()->deleteLater();
            it = m_byId.erase(it);
            listChanged = true;
        }
        for (const auto& id : ids) {
            auto* device = m_byId.value(id);
            if (!device) {
                device = new KdeConnectDevice(id, this);
                connect(device, &KdeConnectDevice::changed, this, &KdeConnect::sortDevices);
                m_byId.insert(id, device);
                m_devices << device;
                listChanged = true;
            }
            device->refresh();
        }
        if (listChanged)
            emit devicesChanged();
    });

    callKdeConnect(this, k_daemonPath, k_daemonIface, u"announcedName"_s, {}, [this](const QDBusMessage& reply) {
        if (ok(reply))
            handleNameChanged(reply.arguments().constFirst().toString());
    });
}

void KdeConnect::rescan() {
    callKdeConnect(this, k_daemonPath, k_daemonIface, u"forceOnNetworkChange"_s, {}, {});
}

void KdeConnect::handleDeviceListChanged() {
    if (m_connected)
        refresh();
}

void KdeConnect::handleNameChanged(const QString& name) {
    if (m_name == name)
        return;
    m_name = name;
    emit nameChanged();
}

void KdeConnect::setAvailable(bool available) {
    if (!available && !m_devices.isEmpty()) {
        for (auto* device : std::as_const(m_devices))
            device->deleteLater();
        m_devices.clear();
        m_byId.clear();
        emit devicesChanged();
    }
    if (m_available == available)
        return;
    m_available = available;
    emit availableChanged();
}

void KdeConnect::sortDevices() {
    auto sorted = m_devices;
    std::ranges::stable_sort(sorted, [](const KdeConnectDevice* a, const KdeConnectDevice* b) {
        if (a->paired() != b->paired())
            return a->paired();
        if (a->reachable() != b->reachable())
            return a->reachable();
        return a->name().localeAwareCompare(b->name()) < 0;
    });
    if (sorted == m_devices)
        return;
    m_devices = sorted;
    emit devicesChanged();
}

} // namespace taris::services
