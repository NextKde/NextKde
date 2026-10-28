#pragma once

#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>

namespace Kos::App {

// Prefer the native faces when installed, with explicit Latin/CJK fallbacks.
// Keep this opt-in: application typography must not change the desktop font.
inline void applyDesktopTypography(QGuiApplication &application)
{
    const QStringList available = QFontDatabase::families();
    QStringList families;
    for (const QString &candidate : {QStringLiteral("SF Pro Text"),
             QStringLiteral("SF Pro"), QStringLiteral("Inter"),
             QStringLiteral("PingFang SC"), QStringLiteral("Noto Sans CJK SC"),
             QStringLiteral("Source Han Sans CN")}) {
        if (available.contains(candidate, Qt::CaseInsensitive))
            families.append(candidate);
    }
    QFont font = application.font();
    if (!families.isEmpty())
        font.setFamilies(families);
    font.setPixelSize(13);
    font.setWeight(QFont::Normal);
    font.setHintingPreference(QFont::PreferNoHinting);
    application.setFont(font);
}

} // namespace Kos::App
