// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <qhash.h>
#include <qjsonvalue.h>
#include <qtclasshelpermacros.h>

namespace taris::settings {

class Quarantine {
public:
    explicit Quarantine() = default;
    virtual ~Quarantine() = default;

    virtual void insert(const QString& key, const QJsonValue& value) = 0;
    [[nodiscard]] virtual bool remove(const QString& key) = 0;
    [[nodiscard]] virtual bool isEmpty() const = 0;
    [[nodiscard]] virtual QJsonValue apply(const QJsonValue& json) const = 0;

    Q_DISABLE_COPY_MOVE(Quarantine)
};

class ObjectQuarantine : public Quarantine {
public:
    void insert(const QString& key, const QJsonValue& value) override;
    [[nodiscard]] bool remove(const QString& key) override;
    [[nodiscard]] bool isEmpty() const override;
    [[nodiscard]] QJsonValue apply(const QJsonValue& json) const override;

private:
    QHash<QString, QJsonValue> m_quarantine;
};

} // namespace taris::settings
