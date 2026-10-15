// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#include "sessionmanager.hpp"

#include <qdbusconnection.h>
#include <qdbuserror.h>
#include <qdbusmessage.h>
#include <qdbuspendingcall.h>
#include <qdbuspendingreply.h>
#include <qdbusreply.h>
#include <qdbusunixfiledescriptor.h>
#include <qloggingcategory.h>

#include "core/toaster.hpp"
#include "util/i18n.hpp"

namespace {

Q_LOGGING_CATEGORY(lcSessionManager, "taris.services.sessionmanager", QtInfoMsg)

} // namespace

namespace taris::services {

using Qt::StringLiterals::operator""_s;
using util::i18n::mark;

namespace {

const QString k_loginService = u"org.freedesktop.login1"_s;
const QString k_loginPath = u"/org/freedesktop/login1"_s;
const QString k_loginIface = u"org.freedesktop.login1.Manager"_s;
const QString k_sessionIface = u"org.freedesktop.login1.Session"_s;

} // namespace

SessionManager::SessionManager(QObject* parent)
    : QObject(parent) {
    auto bus = getSystemBus();
    if (!bus)
        return;

    bool ok = bus->connect(
        k_loginService, k_loginPath, k_loginIface, u"PrepareForSleep"_s, this, SLOT(handlePrepareForSleep(bool)));
    if (!ok)
        qCWarning(lcSessionManager) << "Failed to connect to PrepareForSleep signal:" << bus->lastError().message();

    auto sessionMsg = QDBusMessage::createMethodCall(k_loginService, k_loginPath, k_loginIface, u"GetSession"_s);
    sessionMsg.setArguments({ u"auto"_s });
    const QDBusReply<QDBusObjectPath> sessionReply = bus->call(sessionMsg);
    if (!sessionReply.isValid()) {
        qCWarning(lcSessionManager) << "Failed to get session path:" << sessionReply.error().message();
        return;
    }
    m_sessionPath = sessionReply.value().path();

    ok = bus->connect(k_loginService, m_sessionPath, k_sessionIface, u"Lock"_s, this, SLOT(handleLockRequested()));
    if (!ok)
        qCWarning(lcSessionManager) << "Failed to connect to Lock signal:" << bus->lastError().message();

    ok = bus->connect(k_loginService, m_sessionPath, k_sessionIface, u"Unlock"_s, this, SLOT(handleUnlockRequested()));
    if (!ok)
        qCWarning(lcSessionManager) << "Failed to connect to Unlock signal:" << bus->lastError().message();
}

bool SessionManager::exec(const QStringList& command) {
    if (command.isEmpty()) {
        return false;
    }

    static const QHash<QString, void (SessionManager::*)()> k_cmds = {
        { u"logout"_s, &SessionManager::logout },
        { u"suspend"_s, &SessionManager::suspend },
        { u"suspendthenhibernate"_s, &SessionManager::suspendThenHibernate },
        { u"hibernate"_s, &SessionManager::hibernate },
        { u"poweroff"_s, &SessionManager::poweroff },
        { u"reboot"_s, &SessionManager::reboot },
    };

    auto cmd = command.first();
    // Alias systemctl and loginctl to raw dbus calls (only match exact command)
    if ((cmd == u"systemctl"_s || cmd == u"loginctl"_s) && command.size() == 2)
        cmd = command.at(1);
    if (cmd == u"loginctl"_s && command.size() == 3 && command.at(1) == u"terminate-user"_s && command.at(2).isEmpty())
        cmd = u"logout"_s; // Manual alias `loginctl terminate-user ''` -> logout

    // Normalise command
    cmd = cmd.remove(u'-').remove(u'_').toLower();

    const auto methodPtr = k_cmds.value(cmd, nullptr);
    if (methodPtr) {
        (this->*methodPtr)();
        return true;
    }

    return false;
}

bool SessionManager::handlePowerKey() const {
    return m_powerKeyInhibitor.isValid();
}

void SessionManager::setHandlePowerKey(bool handle) {
    if (handle == handlePowerKey())
        return;

    if (!handle) {
        // Closing the inhibitor's descriptor gives the power key back to logind
        m_powerKeyInhibitor = QDBusUnixFileDescriptor();
        emit handlePowerKeyChanged();
        return;
    }

    auto bus = getSystemBus();
    if (!bus)
        return;

    auto msg = QDBusMessage::createMethodCall(k_loginService, k_loginPath, k_loginIface, u"Inhibit"_s);
    msg.setArguments({ u"handle-power-key"_s, u"TarisOS"_s, u"The power button locks or sleeps"_s, u"block"_s });
    const QDBusReply<QDBusUnixFileDescriptor> reply = bus->call(msg);
    if (!reply.isValid()) {
        qCWarning(lcSessionManager) << "Failed to take the power key from logind:" << reply.error().message();
        return;
    }
    m_powerKeyInhibitor = reply.value();
    emit handlePowerKeyChanged();
}

bool SessionManager::handleLidSwitch() const {
    return m_lidSwitchInhibitor.isValid();
}

void SessionManager::setHandleLidSwitch(bool handle) {
    if (handle == handleLidSwitch())
        return;

    if (!handle) {
        // Closing the inhibitor's descriptor gives the lid back to logind
        m_lidSwitchInhibitor = QDBusUnixFileDescriptor();
        emit handleLidSwitchChanged();
        return;
    }

    auto bus = getSystemBus();
    if (!bus)
        return;

    auto msg = QDBusMessage::createMethodCall(k_loginService, k_loginPath, k_loginIface, u"Inhibit"_s);
    msg.setArguments({ u"handle-lid-switch"_s, u"TarisOS"_s, u"Closing the lid stashes"_s, u"block"_s });
    const QDBusReply<QDBusUnixFileDescriptor> reply = bus->call(msg);
    if (!reply.isValid()) {
        qCWarning(lcSessionManager) << "Failed to take the lid switch from logind:" << reply.error().message();
        return;
    }
    m_lidSwitchInhibitor = reply.value();
    emit handleLidSwitchChanged();
}

bool SessionManager::blockSleep() const {
    return m_blockSleepInhibitor.isValid();
}

void SessionManager::setBlockSleep(bool block) {
    if (block == blockSleep())
        return;

    if (!block) {
        m_blockSleepInhibitor = QDBusUnixFileDescriptor();
        emit blockSleepChanged();
        return;
    }

    auto bus = getSystemBus();
    if (!bus)
        return;

    auto msg = QDBusMessage::createMethodCall(k_loginService, k_loginPath, k_loginIface, u"Inhibit"_s);
    msg.setArguments({ u"sleep:handle-lid-switch"_s, u"TarisOS"_s, u"Stashing"_s, u"block"_s });
    const QDBusReply<QDBusUnixFileDescriptor> reply = bus->call(msg);
    if (!reply.isValid()) {
        qCWarning(lcSessionManager) << "Failed to block sleep:" << reply.error().message();
        return;
    }
    m_blockSleepInhibitor = reply.value();
    emit blockSleepChanged();
}

bool SessionManager::delaySleep() const {
    return m_delaySleep;
}

void SessionManager::setDelaySleep(bool delay) {
    if (delay == m_delaySleep)
        return;

    m_delaySleep = delay;
    if (delay)
        takeSleepInhibitor();
    else
        allowSleep();
    emit delaySleepChanged();
}

void SessionManager::allowSleep() {
    // Closing the inhibitor's descriptor lets logind go ahead
    m_sleepInhibitor = QDBusUnixFileDescriptor();
}

void SessionManager::takeSleepInhibitor() {
    if (m_sleepInhibitor.isValid())
        return;

    auto bus = getSystemBus();
    if (!bus)
        return;

    auto msg = QDBusMessage::createMethodCall(k_loginService, k_loginPath, k_loginIface, u"Inhibit"_s);
    msg.setArguments({ u"sleep"_s, u"TarisOS"_s, u"Locking the screen first"_s, u"delay"_s });
    const QDBusReply<QDBusUnixFileDescriptor> reply = bus->call(msg);
    if (!reply.isValid()) {
        qCWarning(lcSessionManager) << "Failed to take a sleep delay inhibitor:" << reply.error().message();
        return;
    }
    m_sleepInhibitor = reply.value();
}

void SessionManager::logout() {
    callSession(u"Terminate"_s);
}

void SessionManager::suspend() {
    callManager(u"Suspend"_s);
}

void SessionManager::suspendThenHibernate() {
    if (queryHibernateAvailable()) {
        callManager(u"SuspendThenHibernate"_s);
    } else {
        // Fall back to suspend when no hibernate
        qCInfo(lcSessionManager) << "SuspendThenHibernate unavailable, falling back to suspend";
        callManager(u"Suspend"_s);
    }
}

void SessionManager::hibernate() {
    if (queryHibernateAvailable()) {
        callManager(u"Hibernate"_s);
    } else {
        qCWarning(lcSessionManager) << "Hibernate unavailable, ignoring hibernate request";

        Toaster::instance()->toast(mark(u"Hibernate failed"_s), mark(u"Enable hibernation to use this feature."_s),
            u"warning"_s, Toast::Type::Warning);
    }
}

void SessionManager::poweroff() {
    callManager(u"PowerOff"_s);
}

void SessionManager::reboot() {
    callManager(u"Reboot"_s);
}

std::optional<QDBusConnection> SessionManager::getSystemBus() {
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        qCWarning(lcSessionManager) << "Failed to connect to system bus:" << bus.lastError().message();
        return std::nullopt;
    }
    return bus;
}

bool SessionManager::queryHibernateAvailable() {
    auto bus = getSystemBus();
    if (!bus)
        return false;

    const auto hibernateMsg =
        QDBusMessage::createMethodCall(k_loginService, k_loginPath, k_loginIface, u"CanHibernate"_s);
    const QDBusReply<QString> hibernateReply = bus->call(hibernateMsg);
    if (!hibernateReply.isValid()) {
        qCWarning(lcSessionManager) << "Failed to query hibernate support:" << hibernateReply.error().message();
    } else {
        const auto state = hibernateReply.value();
        return state == u"yes"_s || state == u"challenge"_s;
    }

    return false;
}

void SessionManager::call(const QString& path, const QString& iface, const QString& method, const QVariantList& args) {
    auto bus = getSystemBus();
    if (!bus)
        return;

    auto msg = QDBusMessage::createMethodCall(k_loginService, path, iface, method);
    msg.setArguments(args);

    const auto* watcher = new QDBusPendingCallWatcher(bus->asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [method](QDBusPendingCallWatcher* self) {
        const QDBusPendingReply<> reply = *self;
        if (reply.isError())
            qCWarning(lcSessionManager) << "Call to" << method << "failed:" << reply.error().message();
        self->deleteLater();
    });
    // NOLINTNEXTLINE(clang-analyzer-cplusplus.NewDeleteLeaks) watcher is parented and self-deletes
}

void SessionManager::callManager(const QString& method) {
    call(k_loginPath, k_loginIface, method, { /* interactive = */ true });
}

void SessionManager::callSession(const QString& method) {
    if (m_sessionPath.isEmpty()) {
        qCWarning(lcSessionManager) << "Cannot call" << method << "- no session path";
        return;
    }

    call(m_sessionPath, k_sessionIface, method);
}

void SessionManager::handlePrepareForSleep(bool sleep) {
    if (sleep) {
        emit aboutToSleep();
    } else {
        // For the next sleep: the last one was let go (allowSleep) or logind stopped waiting
        if (m_delaySleep)
            takeSleepInhibitor();
        emit resumed();
    }
}

void SessionManager::handleLockRequested() {
    emit lockRequested();
}

void SessionManager::handleUnlockRequested() {
    emit unlockRequested();
}

} // namespace taris::services
