#pragma once

#include <QLocale>
#include <QStringList>
#include <QCoreApplication>
#include <QLibraryInfo>
#include <QTranslator>

namespace Kos::I18n {
// Use the primary UI language, not a later fallback or the date/number locale.
inline bool isChinese(const QStringList &languages = QLocale::system().uiLanguages())
{
    const QString primary = languages.value(0).toLower().replace('_', '-');
    return primary == QStringLiteral("zh") || primary.startsWith(QStringLiteral("zh-"));
}

inline QLocale locale()
{
    return QLocale(isChinese() ? QStringLiteral("zh_CN") : QStringLiteral("en_US"));
}

inline QString settingsValue()
{
    return isChinese() ? QStringLiteral("ZhCn") : QStringLiteral("EnUs");
}

// Keep these alive for the application's lifetime, including native dialogs
// and Qt Quick's standard Save/Cancel buttons.
class QtCatalogs {
public:
    QtCatalogs() {
        if (!isChinese()) return;
        const QString path = QLibraryInfo::path(QLibraryInfo::TranslationsPath);
        if (base.load(QStringLiteral("qtbase_zh_CN"), path))
            QCoreApplication::installTranslator(&base);
        if (declarative.load(QStringLiteral("qtdeclarative_zh_CN"), path))
            QCoreApplication::installTranslator(&declarative);
    }
private:
    QTranslator base;
    QTranslator declarative;
};
}
