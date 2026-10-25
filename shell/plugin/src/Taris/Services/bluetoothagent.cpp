// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#include "bluetoothagent.hpp"

#include <qdbusconnection.h>
#include <qdbuserror.h>
#include <qdbusmessage.h>
#include <qdbuspendingcall.h>
#include <qdbuspendingreply.h>
#include <qdbusreply.h>
#include <qdbusservicewatcher.h>
#include <qloggingcategory.h>

namespace {

Q_LOGGING_CATEGORY(lcBluetoothAgent, "taris.services.bluetoothagent", QtInfoMsg)

} // namespace

namespace taris::services {

using Qt::StringLiterals::operator""_s;

namespace {

const QString k_bluezService = u"org.bluez"_s;
const QString k_bluezPath = u"/org/bluez"_s;
const QString k_agentManagerIface = u"org.bluez.AgentManager1"_s;
const QString k_deviceIface = u"org.bluez.Device1"_s;
const QString k_propertiesIface = u"org.freedesktop.DBus.Properties"_s;
const QString k_agentPath = u"/org/taris/bluetooth/agent"_s;
// Keyboard and display: a code to compare or to type is shown here, and one shown on the device
// can be typed here. Devices without either (headphones) pair with no question when the pairing
// starts here (BlueZ's just-works)
const QString k_capability = u"KeyboardDisplay"_s;
const QString k_rejected = u"org.bluez.Error.Rejected"_s;
const QString k_canceled = u"org.bluez.Error.Canceled"_s;

} // namespace

BluetoothAgentAdaptor::BluetoothAgentAdaptor(BluetoothAgent* agent)
    : QDBusAbstractAdaptor(agent)
    , m_agent(agent) {}

void BluetoothAgentAdaptor::Release() {
    m_agent->handleRelease();
}

QString BluetoothAgentAdaptor::RequestPinCode(const QDBusObjectPath& device, const QDBusMessage& msg) {
    m_agent->handleRequest(BluetoothAgent::PinCode, device, msg);
    return {};
}

void BluetoothAgentAdaptor::DisplayPinCode(const QDBusObjectPath& device, const QString& pincode) {
    m_agent->handleDisplay(BluetoothAgent::DisplayPinCode, device, pincode, 0);
}

uint BluetoothAgentAdaptor::RequestPasskey(const QDBusObjectPath& device, const QDBusMessage& msg) {
    m_agent->handleRequest(BluetoothAgent::Passkey, device, msg);
    return 0;
}

void BluetoothAgentAdaptor::DisplayPasskey(const QDBusObjectPath& device, uint passkey, ushort entered) {
    m_agent->handleDisplay(
        BluetoothAgent::DisplayPasskey, device, u"%1"_s.arg(passkey, 6, 10, QChar(u'0')), entered);
}

void BluetoothAgentAdaptor::RequestConfirmation(const QDBusObjectPath& device, uint passkey, const QDBusMessage& msg) {
    m_agent->handleRequest(BluetoothAgent::Confirm, device, msg, u"%1"_s.arg(passkey, 6, 10, QChar(u'0')));
}

void BluetoothAgentAdaptor::RequestAuthorization(const QDBusObjectPath& device, const QDBusMessage& msg) {
    m_agent->handleRequest(BluetoothAgent::Authorize, device, msg);
}

void BluetoothAgentAdaptor::AuthorizeService(
    const QDBusObjectPath& device, const QString& uuid, const QDBusMessage& msg) {
    Q_UNUSED(uuid)
    m_agent->handleAuthorizeService(device, msg);
}

void BluetoothAgentAdaptor::Cancel() {
    m_agent->handleCancel();
}

BluetoothAgent::BluetoothAgent(QObject* parent)
    : QObject(parent) {
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        qCWarning(lcBluetoothAgent) << "Failed to connect to system bus:" << bus.lastError().message();
        return;
    }

    new BluetoothAgentAdaptor(this);
    if (!bus.registerObject(k_agentPath, this, QDBusConnection::ExportAdaptors)) {
        qCWarning(lcBluetoothAgent) << "Failed to export the agent:" << bus.lastError().message();
        return;
    }

    // bluetoothd forgets its agents when it restarts: register again when it's back
    m_watcher = new QDBusServiceWatcher(k_bluezService, bus,
        QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration, this);
    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered, this, &BluetoothAgent::registerWithBluez);
    connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered, this, [this] {
        clear();
        setRegistered(false);
    });

    registerWithBluez();
}

BluetoothAgent::Kind BluetoothAgent::kind() const {
    return m_kind;
}

QString BluetoothAgent::deviceName() const {
    return m_deviceName;
}

QString BluetoothAgent::deviceAddress() const {
    return m_deviceAddress;
}

QString BluetoothAgent::deviceIcon() const {
    return m_deviceIcon;
}

QString BluetoothAgent::code() const {
    return m_code;
}

int BluetoothAgent::entered() const {
    return m_entered;
}

bool BluetoothAgent::registered() const {
    return m_registered;
}

void BluetoothAgent::accept() {
    if (!m_hasPending || (m_kind != Confirm && m_kind != Authorize && m_kind != AuthorizeService))
        return;

    QDBusConnection::systemBus().send(m_pending.createReply());
    m_hasPending = false;
    clear();
}

void BluetoothAgent::submit(const QString& value) {
    if (!m_hasPending)
        return;

    if (m_kind == PinCode) {
        if (value.isEmpty())
            return;
        QDBusConnection::systemBus().send(m_pending.createReply(value));
    } else if (m_kind == Passkey) {
        bool ok = false;
        const uint passkey = value.toUInt(&ok);
        if (!ok || passkey > 999999)
            return;
        QDBusConnection::systemBus().send(m_pending.createReply(QVariant::fromValue(passkey)));
    } else {
        return;
    }
    m_hasPending = false;
    clear();
}

void BluetoothAgent::reject() {
    if (m_kind == DisplayPinCode || m_kind == DisplayPasskey) {
        // Nothing waits for an answer here: the pairing itself is stopped
        const auto msg = QDBusMessage::createMethodCall(k_bluezService, m_devicePath, k_deviceIface, u"CancelPairing"_s);
        QDBusConnection::systemBus().asyncCall(msg);
        clear();
        return;
    }
    clear(k_rejected);
}

void BluetoothAgent::handleRelease() {
    qCInfo(lcBluetoothAgent) << "BlueZ released the agent";
    clear();
    setRegistered(false);
}

void BluetoothAgent::handleRequest(Kind kind, const QDBusObjectPath& device, const QDBusMessage& msg, const QString& code) {
    // BlueZ asks one thing at a time; anything still shown is over
    clear(k_canceled);
    msg.setDelayedReply(true);
    m_pending = msg;
    m_hasPending = true;
    show(kind, device.path(), code, 0);
}

void BluetoothAgent::handleDisplay(Kind kind, const QDBusObjectPath& device, const QString& code, int entered) {
    // DisplayPasskey comes again for every key typed on the device: only the count changes
    if (m_kind == kind && m_devicePath == device.path() && m_code == code) {
        m_entered = entered;
        emit requestChanged();
        return;
    }

    clear(k_canceled);
    show(kind, device.path(), code, entered);
    // Shown until the device is paired, or BlueZ cancels
    watchDevice(device.path());
}

void BluetoothAgent::handleAuthorizeService(const QDBusObjectPath& device, const QDBusMessage& msg) {
    // A paired device opening its connections (audio, calls, controls...) needs no question: it
    // was let in when it paired
    auto getMsg = QDBusMessage::createMethodCall(k_bluezService, device.path(), k_propertiesIface, u"Get"_s);
    getMsg.setArguments({ k_deviceIface, u"Paired"_s });
    const QDBusReply<QVariant> paired = QDBusConnection::systemBus().call(getMsg, QDBus::Block, 2000);
    if (paired.isValid() && paired.value().toBool()) {
        QDBusConnection::systemBus().send(msg.createReply());
        return;
    }

    handleRequest(AuthorizeService, device, msg);
}

void BluetoothAgent::handleCancel() {
    // BlueZ gave up on the question (the device went away, or it waited too long)
    m_hasPending = false;
    clear();
}

void BluetoothAgent::handleDevicePropertiesChanged(
    const QString& iface, const QVariantMap& changed, const QStringList& invalidated) {
    Q_UNUSED(invalidated)
    if (iface != k_deviceIface)
        return;
    if (changed.value(u"Paired"_s).toBool() && (m_kind == DisplayPinCode || m_kind == DisplayPasskey))
        clear();
}

void BluetoothAgent::registerWithBluez() {
    auto msg = QDBusMessage::createMethodCall(k_bluezService, k_bluezPath, k_agentManagerIface, u"RegisterAgent"_s);
    msg.setArguments({ QVariant::fromValue(QDBusObjectPath(k_agentPath)), k_capability });
    const auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* self) {
        const QDBusPendingReply<> reply = *self;
        self->deleteLater();
        // Already registered: this connection's agent is still there, it only needs to be the default
        if (reply.isError() && reply.error().name() != u"org.bluez.Error.AlreadyExists"_s) {
            // Without BlueZ, the service watcher registers it once bluetoothd starts
            qCWarning(lcBluetoothAgent) << "Failed to register the agent:" << reply.error().message();
            return;
        }
        requestDefault();
    });
    // NOLINTNEXTLINE(clang-analyzer-cplusplus.NewDeleteLeaks) watcher is parented and self-deletes
}

void BluetoothAgent::requestDefault() {
    auto msg = QDBusMessage::createMethodCall(k_bluezService, k_bluezPath, k_agentManagerIface, u"RequestDefaultAgent"_s);
    msg.setArguments({ QVariant::fromValue(QDBusObjectPath(k_agentPath)) });
    const auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* self) {
        const QDBusPendingReply<> reply = *self;
        self->deleteLater();
        if (reply.isError()) {
            qCWarning(lcBluetoothAgent) << "Failed to become the default agent:" << reply.error().message();
            return;
        }
        qCInfo(lcBluetoothAgent) << "Registered as BlueZ's default agent";
        setRegistered(true);
    });
    // NOLINTNEXTLINE(clang-analyzer-cplusplus.NewDeleteLeaks) watcher is parented and self-deletes
}

void BluetoothAgent::setRegistered(bool registered) {
    if (registered == m_registered)
        return;
    m_registered = registered;
    emit registeredChanged();
}

void BluetoothAgent::show(Kind kind, const QString& path, const QString& code, int entered) {
    m_kind = kind;
    m_devicePath = path;
    m_code = code;
    m_entered = entered;

    // The name the user knows it by (its alias, which is its own name unless renamed)
    auto msg = QDBusMessage::createMethodCall(k_bluezService, path, k_propertiesIface, u"GetAll"_s);
    msg.setArguments({ k_deviceIface });
    const QDBusReply<QVariantMap> props = QDBusConnection::systemBus().call(msg, QDBus::Block, 2000);
    if (props.isValid()) {
        m_deviceName = props.value().value(u"Alias"_s).toString();
        m_deviceAddress = props.value().value(u"Address"_s).toString();
        m_deviceIcon = props.value().value(u"Icon"_s).toString();
    } else {
        qCWarning(lcBluetoothAgent) << "Failed to read the device at" << path << ":" << props.error().message();
        m_deviceName.clear();
        m_deviceAddress.clear();
        m_deviceIcon.clear();
    }

    qCInfo(lcBluetoothAgent) << "Asking about" << m_deviceAddress << ":" << kind;
    emit requestChanged();
}

void BluetoothAgent::clear(const QString& error) {
    if (m_hasPending) {
        QDBusConnection::systemBus().send(m_pending.createErrorReply(error.isEmpty() ? k_canceled : error, {}));
        m_hasPending = false;
    }
    m_pending = QDBusMessage();
    unwatchDevice();

    if (m_kind == None)
        return;
    m_kind = None;
    m_devicePath.clear();
    m_deviceName.clear();
    m_deviceAddress.clear();
    m_deviceIcon.clear();
    m_code.clear();
    m_entered = 0;
    emit requestChanged();
}

void BluetoothAgent::watchDevice(const QString& path) {
    unwatchDevice();
    const bool ok = QDBusConnection::systemBus().connect(k_bluezService, path, k_propertiesIface,
        u"PropertiesChanged"_s, this, SLOT(handleDevicePropertiesChanged(QString, QVariantMap, QStringList)));
    if (ok)
        m_watchedPath = path;
}

void BluetoothAgent::unwatchDevice() {
    if (m_watchedPath.isEmpty())
        return;
    QDBusConnection::systemBus().disconnect(k_bluezService, m_watchedPath, k_propertiesIface,
        u"PropertiesChanged"_s, this, SLOT(handleDevicePropertiesChanged(QString, QVariantMap, QStringList)));
    m_watchedPath.clear();
}

} // namespace taris::services
