// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#include "appearanceconfig.hpp"

#include "tokens.hpp"

namespace taris::config {

namespace {

// Helper: connect all changed signals from a token object to a single valuesChanged signal,
// plus connect the local scaleChanged signal.
template <typename Source, typename Target> void connectTokenSignals(Source* source, Target* target) {
    const auto* meta = source->metaObject();

    for (int i = meta->propertyOffset(); i < meta->propertyCount(); ++i) {
        const auto prop = meta->property(i);

        if (prop.hasNotifySignal())
            QObject::connect(source, prop.notifySignal(), target,
                target->metaObject()->method(target->metaObject()->indexOfSignal("valuesChanged()")));
    }

    QObject::connect(target, &Target::scaleChanged, target, &Target::valuesChanged);
}

} // namespace

// AppearanceRounding

void AppearanceRounding::bindTokens(RoundingTokens* tokens) {
    m_tokens = tokens;
    connectTokenSignals(tokens, this);
}

int AppearanceRounding::extraSmall() const {
    return m_tokens ? static_cast<int>(m_tokens->extraSmall() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceRounding::small() const {
    return m_tokens ? static_cast<int>(m_tokens->small() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceRounding::medium() const {
    return m_tokens ? static_cast<int>(m_tokens->medium() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceRounding::large() const {
    return m_tokens ? static_cast<int>(m_tokens->large() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceRounding::largeIncreased() const {
    return m_tokens ? static_cast<int>(m_tokens->largeIncreased() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceRounding::extraLarge() const {
    return m_tokens ? static_cast<int>(m_tokens->extraLarge() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceRounding::extraLargeIncreased() const {
    return m_tokens ? static_cast<int>(m_tokens->extraLargeIncreased() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceRounding::extraExtraLarge() const {
    return m_tokens ? static_cast<int>(m_tokens->extraExtraLarge() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceRounding::full() const {
    return m_tokens ? m_tokens->full() : 0;
}

// AppearanceSpacing

void AppearanceSpacing::bindTokens(SpacingTokens* tokens) {
    m_tokens = tokens;
    connectTokenSignals(tokens, this);
}

int AppearanceSpacing::extraSmall() const {
    return m_tokens ? static_cast<int>(m_tokens->extraSmall() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceSpacing::small() const {
    return m_tokens ? static_cast<int>(m_tokens->small() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceSpacing::medium() const {
    return m_tokens ? static_cast<int>(m_tokens->medium() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceSpacing::large() const {
    return m_tokens ? static_cast<int>(m_tokens->large() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceSpacing::largeIncreased() const {
    return m_tokens ? static_cast<int>(m_tokens->largeIncreased() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceSpacing::extraLarge() const {
    return m_tokens ? static_cast<int>(m_tokens->extraLarge() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceSpacing::extraLargeIncreased() const {
    return m_tokens ? static_cast<int>(m_tokens->extraLargeIncreased() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearanceSpacing::extraExtraLarge() const {
    return m_tokens ? static_cast<int>(m_tokens->extraExtraLarge() * m_scale * k_interfaceBaseScale) : 0;
}

// AppearancePadding

void AppearancePadding::bindTokens(PaddingTokens* tokens) {
    m_tokens = tokens;
    connectTokenSignals(tokens, this);
}

int AppearancePadding::extraSmall() const {
    return m_tokens ? static_cast<int>(m_tokens->extraSmall() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearancePadding::small() const {
    return m_tokens ? static_cast<int>(m_tokens->small() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearancePadding::medium() const {
    return m_tokens ? static_cast<int>(m_tokens->medium() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearancePadding::large() const {
    return m_tokens ? static_cast<int>(m_tokens->large() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearancePadding::largeIncreased() const {
    return m_tokens ? static_cast<int>(m_tokens->largeIncreased() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearancePadding::extraLarge() const {
    return m_tokens ? static_cast<int>(m_tokens->extraLarge() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearancePadding::extraLargeIncreased() const {
    return m_tokens ? static_cast<int>(m_tokens->extraLargeIncreased() * m_scale * k_interfaceBaseScale) : 0;
}

int AppearancePadding::extraExtraLarge() const {
    return m_tokens ? static_cast<int>(m_tokens->extraExtraLarge() * m_scale * k_interfaceBaseScale) : 0;
}

// AnimDurations

void AnimDurations::bindTokens(AnimDurationTokens* tokens) {
    m_tokens = tokens;
    connectTokenSignals(tokens, this);
}

bool AnimDurations::suspended() const {
    return m_suspended;
}

void AnimDurations::setSuspended(bool suspended) {
    if (m_suspended == suspended)
        return;
    m_suspended = suspended;
    emit valuesChanged();
}

int AnimDurations::scaled(qreal duration) const {
    return m_suspended ? 0 : static_cast<int>(duration * m_scale);
}

int AnimDurations::small() const {
    return m_tokens ? scaled(m_tokens->small()) : 0;
}

int AnimDurations::normal() const {
    return m_tokens ? scaled(m_tokens->normal()) : 0;
}

int AnimDurations::large() const {
    return m_tokens ? scaled(m_tokens->large()) : 0;
}

int AnimDurations::extraLarge() const {
    return m_tokens ? scaled(m_tokens->extraLarge()) : 0;
}

int AnimDurations::expressiveFastSpatial() const {
    return m_tokens ? scaled(m_tokens->expressiveFastSpatial()) : 0;
}

int AnimDurations::expressiveDefaultSpatial() const {
    return m_tokens ? scaled(m_tokens->expressiveDefaultSpatial()) : 0;
}

int AnimDurations::expressiveSlowSpatial() const {
    return m_tokens ? scaled(m_tokens->expressiveSlowSpatial()) : 0;
}

int AnimDurations::expressiveFastEffects() const {
    return m_tokens ? scaled(m_tokens->expressiveFastEffects()) : 0;
}

int AnimDurations::expressiveDefaultEffects() const {
    return m_tokens ? scaled(m_tokens->expressiveDefaultEffects()) : 0;
}

int AnimDurations::expressiveSlowEffects() const {
    return m_tokens ? scaled(m_tokens->expressiveSlowEffects()) : 0;
}

} // namespace taris::config
