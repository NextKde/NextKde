#pragma once

#include <QByteArray>
#include <QImage>
#include <QString>

// Implementation-only contracts; not part of the JSONL protocol.
namespace KosPlatform::Detail {

QString clipboardStateDir();

// Decodes content and renders the shared preview size. The QImage overload
// reuses an image the caller already decoded (the pin path needs one decode
// just to tell image from text), avoiding a second full decode of a
// potentially 4K screenshot.
QString clipboardWriteThumb(const QByteArray &content, const QString &path);
QString clipboardWriteThumb(const QImage &image, const QString &path);

} // namespace KosPlatform::Detail
