// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <qquickimageprovider.h>

#include "imagecacher.hpp"

namespace taris::images {

class CachingImageProvider : public QQuickAsyncImageProvider {
public:
    using FillMode = ImageCacher::FillMode;

    explicit CachingImageProvider(FillMode fillMode);

    QQuickImageResponse* requestImageResponse(const QString& id, const QSize& requestedSize) override;

private:
    FillMode m_fillMode;
};

} // namespace taris::images
