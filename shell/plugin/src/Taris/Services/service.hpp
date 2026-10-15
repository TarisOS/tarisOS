// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <qobject.h>
#include <qset.h>

namespace taris::services {

class Service : public QObject {
    Q_OBJECT

public:
    explicit Service(QObject* parent = nullptr);

    void ref(QObject* sender);
    void unref(QObject* sender);

private:
    QSet<QObject*> m_refs;

    virtual void start() = 0;
    virtual void stop() = 0;
};

} // namespace taris::services
