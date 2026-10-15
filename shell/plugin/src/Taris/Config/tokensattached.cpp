// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#include "tokensattached.hpp"

#include <qhash.h>
#include <qpointer.h>
#include <qquickitem.h>

#include "common.hpp"

namespace taris::config {

namespace {

const AppearanceConfig* resolveAppearance(const ConfigRoot* config, bool complete, const char* prop, QObject* parent) {
    if (config)
        return config->appearance();
    if ((complete || !qobject_cast<QQuickItem*>(parent)) && parent)
        qCWarning(lcConfig, "Tokens.%s accessed without a screen set on %s", prop, parent->metaObject()->className());
    return ConfigSingleton::instance()->appearance();
}

// Every item's Tokens used to build its own font and animation tokens (each font style's fonts,
// every easing curve, and their connections to the config), twice for an item that then learnt
// its screen. They're the same for every item on a screen, so items share them: one FontTokens
// per font config (global, or a screen's), owned by that config, and one AnimTokens (always
// global).
FontTokens* sharedFont(AppearanceFont* font) {
    static QHash<const AppearanceFont*, QPointer<FontTokens>> shared;
    auto& tokens = shared[font];
    if (!tokens) {
        tokens = new FontTokens(font);
        tokens->bindFont(font);
    }
    return tokens;
}

AnimTokens* sharedAnim() {
    static QPointer<AnimTokens> tokens;
    if (!tokens) {
        auto* const curves = TokensSingleton::instance()->appearance()->curves();
        tokens = new AnimTokens(curves);
        tokens->bindDurations(ConfigSingleton::instance()->appearance()->anim()->durations());
        tokens->bindCurves(curves);
    }
    return tokens;
}

} // namespace

Tokens::Tokens(QObject* parent)
    : QQuickAttachedPropertyPropagator(parent) {
    bindAnim();
    bindFont();
    initialize();
}

void Tokens::classBegin() {}

void Tokens::componentComplete() {
    m_complete = true;
}

QString Tokens::screen() const {
    return m_screen;
}

void Tokens::inheritScreen(const QString& screen) {
    if (screen == m_screen)
        return;

    m_screen = screen;

    if (m_screen.isEmpty()) {
        m_config = nullptr;
        m_tokens = nullptr;
    } else {
        m_config = ConfigSingleton::instance()->forScreen(m_screen);
        m_tokens = TokensSingleton::instance()->forScreen(m_screen);
    }

    bindFont();
    propagateScreen();
    emit sourceChanged();
}

void Tokens::propagateScreen() {
    const auto children = attachedChildren();
    for (auto* const child : children) {
        auto* const tokens = qobject_cast<Tokens*>(child);
        if (tokens)
            tokens->inheritScreen(m_screen);
    }
}

void Tokens::attachedParentChange(
    QQuickAttachedPropertyPropagator* newParent, QQuickAttachedPropertyPropagator* oldParent) {
    Q_UNUSED(oldParent);
    const auto* tokens = qobject_cast<Tokens*>(newParent);
    if (tokens)
        inheritScreen(tokens->screen());
}

void Tokens::bindAnim() {
    m_anim = sharedAnim();
}

void Tokens::bindFont() {
    const auto* appearance = m_config ? m_config->appearance() : ConfigSingleton::instance()->appearance();
    m_font = sharedFont(appearance->font());
}

#define TOKENS_ATTACHED_GETTER(Type, name)                                                                             \
    const Type* Tokens::name() const {                                                                                 \
        auto* a = resolveAppearance(m_config, m_complete, #name, parent());                                            \
        return a ? a->name() : nullptr;                                                                                \
    }

TOKENS_ATTACHED_GETTER(AppearanceRounding, rounding)
TOKENS_ATTACHED_GETTER(AppearanceSpacing, spacing)
TOKENS_ATTACHED_GETTER(AppearancePadding, padding)

#undef TOKENS_ATTACHED_GETTER

const AppearanceTransparency* Tokens::transparency() {
    return ConfigSingleton::instance()->appearance()->transparency(); // Transparency is always global
}

const SizeTokens* Tokens::sizes() const {
    if (m_tokens)
        return m_tokens->sizes();
    if ((m_complete || !qobject_cast<QQuickItem*>(parent())) && parent())
        qCWarning(lcConfig, "Tokens.sizes accessed without a screen set on %s", parent()->metaObject()->className());
    return TokensSingleton::instance()->sizes();
}

const FontTokens* Tokens::font() const {
    return m_font;
}

const AnimTokens* Tokens::anim() const {
    return m_anim;
}

TokensRoot* Tokens::forScreen(const QString& screen) {
    return TokensSingleton::instance()->forScreen(screen);
}

Tokens* Tokens::qmlAttachedProperties(QObject* object) {
    return new Tokens(object);
}

} // namespace taris::config
