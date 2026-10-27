#pragma once

#include <QLocale>
#include <QStringList>
#include <QCoreApplication>
#include <QLibraryInfo>
#include <QTranslator>

namespace Kos::I18n {
inline QString primaryLanguage(const QStringList &languages)
{
    return languages.value(0).toLower().replace('_', '-');
}

// Use the primary UI language, not a later fallback or the date/number locale.
inline bool isChinese(const QStringList &languages = QLocale::system().uiLanguages())
{
    const QString primary = primaryLanguage(languages);
    return primary == QStringLiteral("zh") || primary.startsWith(QStringLiteral("zh-"));
}

// Every Portuguese variant uses the Brazilian catalog, the only one shipped.
inline bool isPortuguese(const QStringList &languages = QLocale::system().uiLanguages())
{
    const QString primary = primaryLanguage(languages);
    return primary == QStringLiteral("pt") || primary.startsWith(QStringLiteral("pt-"));
}

// Qt catalog suffix for the selected UI language: zh_CN, pt_BR or en_US.
inline QString localeName()
{
    if (isChinese())
        return QStringLiteral("zh_CN");
    if (isPortuguese())
        return QStringLiteral("pt_BR");
    return QStringLiteral("en_US");
}

inline QLocale locale()
{
    return QLocale(localeName());
}

inline QString settingsValue()
{
    if (isChinese())
        return QStringLiteral("ZhCn");
    if (isPortuguese())
        return QStringLiteral("PtBr");
    return QStringLiteral("EnUs");
}

// Keep these alive for the application's lifetime, including native dialogs
// and Qt Quick's standard Save/Cancel buttons.
class QtCatalogs {
public:
    QtCatalogs() {
        const QString name = localeName();
        if (name == QStringLiteral("en_US")) return;
        const QString path = QLibraryInfo::path(QLibraryInfo::TranslationsPath);
        if (base.load(QStringLiteral("qtbase_") + name, path))
            QCoreApplication::installTranslator(&base);
        if (declarative.load(QStringLiteral("qtdeclarative_") + name, path))
            QCoreApplication::installTranslator(&declarative);
    }
private:
    QTranslator base;
    QTranslator declarative;
};
}
