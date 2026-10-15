// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <qdbusconnection.h>
#include <qdbusunixfiledescriptor.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qstringlist.h>
#include <qvariant.h>

#include <optional>

namespace taris::services {

class SessionManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Whether the shell handles the power key instead of logind: a handle-power-key inhibitor,
    // which the system drops by itself if the shell exits
    Q_PROPERTY(bool handlePowerKey READ handlePowerKey WRITE setHandlePowerKey NOTIFY handlePowerKeyChanged)
    // Whether the shell handles closing the lid instead of logind (Settings > Power: Stash or
    // nothing), the same way: a handle-lid-switch inhibitor
    Q_PROPERTY(bool handleLidSwitch READ handleLidSwitch WRITE setHandleLidSwitch NOTIFY handleLidSwitchChanged)
    // Whether nothing may put the Mac to sleep, the lid included, whatever its setting (while a Stash
    // runs, until the shut down): a sleep and handle-lid-switch block inhibitor
    Q_PROPERTY(bool blockSleep READ blockSleep WRITE setBlockSleep NOTIFY blockSleepChanged)
    // Whether sleep waits for the lock screen (Settings > Power, lock before sleep): a delay
    // inhibitor, taken again after each resume and given up by allowSleep() once the session is
    // locked. logind sleeps anyway once InhibitDelayMaxSec has passed
    Q_PROPERTY(bool delaySleep READ delaySleep WRITE setDelaySleep NOTIFY delaySleepChanged)

public:
    explicit SessionManager(QObject* parent = nullptr);

    Q_INVOKABLE void logout();
    Q_INVOKABLE void suspend();
    Q_INVOKABLE void suspendThenHibernate();
    Q_INVOKABLE void hibernate();
    Q_INVOKABLE void poweroff();
    Q_INVOKABLE void reboot();

    Q_INVOKABLE bool exec(const QStringList& command);
    // The lock screen is up: the sleep logind announced (aboutToSleep) may go ahead
    Q_INVOKABLE void allowSleep();

    [[nodiscard]] bool handlePowerKey() const;
    void setHandlePowerKey(bool handle);

    [[nodiscard]] bool handleLidSwitch() const;
    void setHandleLidSwitch(bool handle);

    [[nodiscard]] bool blockSleep() const;
    void setBlockSleep(bool block);

    [[nodiscard]] bool delaySleep() const;
    void setDelaySleep(bool delay);

signals:
    void handlePowerKeyChanged();
    void handleLidSwitchChanged();
    void blockSleepChanged();
    void delaySleepChanged();
    void aboutToSleep();
    void resumed();
    void lockRequested();
    void unlockRequested();

private slots:
    void handlePrepareForSleep(bool sleep);
    void handleLockRequested();
    void handleUnlockRequested();

private:
    [[nodiscard]] static std::optional<QDBusConnection> getSystemBus();
    [[nodiscard]] static bool queryHibernateAvailable();
    void call(const QString& path, const QString& iface, const QString& method, const QVariantList& args = {});
    void callManager(const QString& method);
    void callSession(const QString& method);
    void takeSleepInhibitor();

    QString m_sessionPath;
    QDBusUnixFileDescriptor m_powerKeyInhibitor;
    QDBusUnixFileDescriptor m_lidSwitchInhibitor;
    QDBusUnixFileDescriptor m_blockSleepInhibitor;
    bool m_delaySleep = false;
    QDBusUnixFileDescriptor m_sleepInhibitor;
};

} // namespace taris::services
