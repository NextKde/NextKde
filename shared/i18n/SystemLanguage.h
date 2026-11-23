#pragma once

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
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

// ListenFree's existing two-language settings enum. New common-app catalogs
// must not select an unsupported value (its QML treats unknown values as Chinese).
inline QString settingsValue(const QStringList &languages = QLocale::system().uiLanguages())
{
    return isChinese(languages) ? QStringLiteral("ZhCn") : QStringLiteral("EnUs");
}

// --- The Shell's persisted UI language -------------------------------------
// Settings → Theme stores "auto", "zh-CN", "pt-BR" or "en"; the Shell resolves
// "auto" from the system locale (see shared/qml/i18n/I18n.qml). The Shell pins
// its state directory (StateDir pragma in shell/shell.qml), so every launch
// mode reads and writes the same file. Native strings in the Settings process
// must follow that choice too, or they appear in the other language while the
// QML UI is in the selected one.
inline QString persistedChoice()
{
    QString stateHome = qEnvironmentVariable("XDG_STATE_HOME");
    if (stateHome.isEmpty())
        stateHome = QDir::homePath() + QStringLiteral("/.local/state");
    QFile file(stateHome + QStringLiteral("/quickshell/kos/i18n/language.json"));
    if (!file.open(QIODevice::ReadOnly) || file.size() > 4096)
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject())
        return {};
    const QString choice = document.object().value(QStringLiteral("language")).toString();
    if (choice == QStringLiteral("auto") || choice == QStringLiteral("zh-CN")
        || choice == QStringLiteral("pt-BR") || choice == QStringLiteral("en"))
        return choice;
    return {};
}

// Effective UI language booleans: a pinned choice wins, "auto" (or no saved
// choice) follows the system locale exactly like the Shell does.
inline bool uiIsChinese()
{
    const QString choice = persistedChoice();
    if (choice == QStringLiteral("zh-CN")) return true;
    if (choice == QStringLiteral("pt-BR") || choice == QStringLiteral("en")) return false;
    return isChinese();
}

inline bool uiIsPortuguese()
{
    const QString choice = persistedChoice();
    if (choice == QStringLiteral("pt-BR")) return true;
    if (choice == QStringLiteral("zh-CN") || choice == QStringLiteral("en")) return false;
    return isPortuguese();
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
