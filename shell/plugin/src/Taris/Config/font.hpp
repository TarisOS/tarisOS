// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <qlist.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qvariantmap.h>

#include "settings/objectnode.hpp"
#include "fontbuilder.hpp"

namespace taris::config {

class AppearanceFont;
class FontStyleBase;
class IconFontStyle;

class FontBuilders : public QObject {
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(taris::config::FontBuilder large READ large NOTIFY buildersChanged FINAL)
    Q_PROPERTY(taris::config::FontBuilder medium READ medium NOTIFY buildersChanged FINAL)
    Q_PROPERTY(taris::config::FontBuilder small READ small NOTIFY buildersChanged FINAL)

public:
    explicit FontBuilders(const FontStyleBase* style, QObject* parent = nullptr);

    [[nodiscard]] FontBuilder large() const;
    [[nodiscard]] FontBuilder medium() const;
    [[nodiscard]] FontBuilder small() const;

signals:
    void buildersChanged();

protected:
    const FontStyleBase* m_style;
};

class IconFontBuilders : public FontBuilders {
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(taris::config::FontBuilder extraLarge READ extraLarge NOTIFY buildersChanged FINAL)

public:
    explicit IconFontBuilders(const IconFontStyle* style, QObject* parent = nullptr);

    [[nodiscard]] FontBuilder extraLarge() const;
};

class FontStyleBase : public QObject {
    Q_OBJECT

    Q_PROPERTY(QFont large READ large NOTIFY fontsChanged FINAL)
    Q_PROPERTY(QFont medium READ medium NOTIFY fontsChanged FINAL)
    Q_PROPERTY(QFont small READ small NOTIFY fontsChanged FINAL)

public:
    explicit FontStyleBase(QObject* parent = nullptr);

    virtual void bind(settings::ObjectNode* cfg);
    void setScale(qreal scale);

    [[nodiscard]] QFont large() const;
    [[nodiscard]] QFont medium() const;
    [[nodiscard]] QFont small() const;

signals:
    void fontsChanged();

protected:
    virtual void rebuild();

    static QFont buildFont(const settings::ObjectNode* cfg, const QString& fallbackFamily, qreal scale);

    settings::ObjectNode* m_cfg = nullptr;
    // Disconnecting by sender (disconnect(m_cfg, nullptr, this, nullptr)) searches every
    // connection the shared config nodes have, one per Tokens of every item: with hundreds of
    // items that made building a panel slow. These are disconnected one by one instead.
    QList<QMetaObject::Connection> m_connections;
    qreal m_scale = 1;
    QFont m_large;
    QFont m_medium;
    QFont m_small;
};

class FontStyle : public FontStyleBase {
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(taris::config::FontBuilders* builders READ builders CONSTANT FINAL)

public:
    explicit FontStyle(QObject* parent = nullptr);

    [[nodiscard]] FontBuilders* builders() const;

private:
    FontBuilders* m_builders;
};

class IconFontStyle : public FontStyleBase {
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(QFont extraLarge READ extraLarge NOTIFY fontsChanged FINAL)
    Q_PROPERTY(taris::config::IconFontBuilders* builders READ builders CONSTANT FINAL)

public:
    explicit IconFontStyle(QObject* parent = nullptr);

    Q_INVOKABLE FontBuilder size(int pointSize);

    void bind(settings::ObjectNode* cfg) override;

    [[nodiscard]] QFont extraLarge() const;
    [[nodiscard]] IconFontBuilders* builders() const;

protected:
    void rebuild() override;

private:
    QFont m_extraLarge;
    QMetaObject::Connection m_extraLargeConnection;
    IconFontBuilders* m_builders;
};

class FontTokens : public QObject {
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(taris::config::FontStyle* headline READ headline CONSTANT FINAL)
    Q_PROPERTY(taris::config::FontStyle* title READ title CONSTANT FINAL)
    Q_PROPERTY(taris::config::FontStyle* body READ body CONSTANT FINAL)
    Q_PROPERTY(taris::config::FontStyle* label READ label CONSTANT FINAL)
    Q_PROPERTY(taris::config::FontStyle* mono READ mono CONSTANT FINAL)
    Q_PROPERTY(taris::config::IconFontStyle* icon READ icon CONSTANT FINAL)
    Q_PROPERTY(taris::config::FontBuilder clock READ clock NOTIFY clockChanged FINAL)
    Q_PROPERTY(QString workspaces READ workspaces NOTIFY workspacesChanged FINAL)

public:
    explicit FontTokens(QObject* parent = nullptr);

    void bindFont(AppearanceFont* font);

    [[nodiscard]] FontStyle* headline() const;
    [[nodiscard]] FontStyle* title() const;
    [[nodiscard]] FontStyle* body() const;
    [[nodiscard]] FontStyle* label() const;
    [[nodiscard]] FontStyle* mono() const;
    [[nodiscard]] IconFontStyle* icon() const;
    [[nodiscard]] FontBuilder clock() const;
    [[nodiscard]] QString workspaces() const;

signals:
    void clockChanged();
    void workspacesChanged();

private:
    void rebuildClock();
    void rebuildScale();

    AppearanceFont* m_font = nullptr;
    QList<QMetaObject::Connection> m_fontConnections;
    FontStyle* m_headline;
    FontStyle* m_title;
    FontStyle* m_body;
    FontStyle* m_label;
    FontStyle* m_mono;
    IconFontStyle* m_icon;
    QFont m_clock;
};

} // namespace taris::config
