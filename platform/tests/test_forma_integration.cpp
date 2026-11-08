#include "FormaIntegration.h"

#include <KConfig>
#include <KConfigGroup>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLockFile>
#include <QSet>
#include <QTemporaryDir>
#include <QtTest>

using KosPlatform::FormaIntegration;

namespace {
QString mayo(const char *name)
{
    return QStringLiteral("io.github.egely1337.Mayonnaise.") + QString::fromLatin1(name) + QStringLiteral(".desktop");
}

QString forma(const char *name)
{
    return QStringLiteral("io.github.skjsbsnq.Forma.") + QString::fromLatin1(name) + QStringLiteral(".desktop");
}

struct Fixture {
    QTemporaryDir temporary;
    QString config = temporary.filePath(QStringLiteral("config"));
    QString state = temporary.filePath(QStringLiteral("state"));
    QSet<QString> installed;

    FormaIntegration integration()
    {
        return FormaIntegration(config, state, [this](const QString &id) { return installed.contains(id); });
    }
    QString configFile(const char *name = "mimeapps.list") const
    {
        return QDir(config).filePath(QString::fromLatin1(name));
    }
    QString stateFile() const { return QDir(state).filePath(QStringLiteral("forma-integration.json")); }
};

bool writeBytes(const QString &path, const QByteArray &bytes)
{
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) return false;
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size() && file.flush();
}

QByteArray readBytes(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return {};
    return file.readAll();
}

QJsonObject readState(const Fixture &fixture)
{
    return QJsonDocument::fromJson(readBytes(fixture.stateFile())).object();
}

QString readEntry(const QString &path, const QString &key, const char *groupName = "Default Applications")
{
    KConfig config(path, KConfig::SimpleConfig);
    return KConfigGroup(&config, groupName).readEntry(key, QString());
}

bool hasEntry(const QString &path, const QString &key, const char *groupName = "Default Applications")
{
    KConfig config(path, KConfig::SimpleConfig);
    return KConfigGroup(&config, groupName).hasKey(key);
}

bool writeEntry(const QString &path, const QString &key, const QString &value,
                const char *groupName = "Default Applications")
{
    KConfig config(path, KConfig::SimpleConfig);
    KConfigGroup(&config, groupName).writeEntry(key, value);
    return config.sync();
}

QJsonObject backupEntry(const QJsonObject &state, const QString &file, const QString &key)
{
    const auto entries = state.value(QStringLiteral("entries")).toArray();
    for (const auto &value : entries) {
        const auto row = value.toObject();
        if (row.value(QStringLiteral("file")).toString() == file
            && row.value(QStringLiteral("key")).toString() == key) return row;
    }
    return {};
}

QJsonObject emptyState()
{
    return {{QStringLiteral("schema"), 1}, {QStringLiteral("enabled"), false},
            {QStringLiteral("restorePending"), false}, {QStringLiteral("pendingAction"), QString()},
            {QStringLiteral("error"), QString()}, {QStringLiteral("entries"), QJsonArray()}};
}
} // namespace

class FormaIntegrationTest : public QObject
{
    Q_OBJECT
private slots:
    void defaultOffDoesNotWrite();
    void registryAndPreferredRoles();
    void terminalExecutionPreferencesRemainUntouched();
    void legacyTerminalBackupsCanRestore();
    void missingApplicationsAndAudioFallback();
    void restoresOriginalAndAbsentKeys();
    void repeatEnableAndNewInstallationKeepFirstBackup();
    void userChangesAreNotOverwrittenOnDisable();
    void corruptStateIsRejected_data();
    void corruptStateIsRejected();
    void concurrentWriterIsRejected();
    void immutablePreferenceDoesNotReportTakeover();
    void backupFailureDoesNotChangeConfigAndCanRetry();
    void syncFailureRetainsBackupAndCanRecover();
    void incompleteFinalSaveCanRestore();
    void incompleteRestoreCanRetry();
    void previousAudioOwnerCanRestore();
};

void FormaIntegrationTest::defaultOffDoesNotWrite()
{
    Fixture f;
    QVERIFY(f.temporary.isValid());
    f.installed = {mayo("Finder"), mayo("Terminal")};
    auto integration = f.integration();
    const auto status = integration.snapshot();
    QVERIFY(status.value(QStringLiteral("ready")).toBool());
    QVERIFY(!status.value(QStringLiteral("enabled")).toBool());
    QVERIFY(!status.value(QStringLiteral("busy")).toBool());
    QVERIFY(status.value(QStringLiteral("error")).toString().isEmpty());
    QCOMPARE(status.value(QStringLiteral("applications")).toArray().size(), 11);
    QVERIFY(integration.preferredDesktopId(QStringLiteral("finder")).isEmpty());
    QVERIFY(!integration.setEnabled(false).value(QStringLiteral("enabled")).toBool());
    QVERIFY(!QFileInfo::exists(f.config));
    QVERIFY(!QFileInfo::exists(f.state));
    QCOMPARE(FormaIntegration::finderDesktopId(), mayo("Finder"));
}

void FormaIntegrationTest::registryAndPreferredRoles()
{
    Fixture f;
    auto integration = f.integration();
    const auto applications = integration.snapshot().value(QStringLiteral("applications")).toArray();
    for (const auto &value : applications) f.installed.insert(value.toObject().value(QStringLiteral("desktopId")).toString());
    const auto status = integration.setEnabled(true);
    QVERIFY2(status.value(QStringLiteral("ready")).toBool(), qPrintable(status.value(QStringLiteral("error")).toString()));
    QVERIFY(status.value(QStringLiteral("enabled")).toBool());
    QSet<QString> roles;
    const auto installed = status.value(QStringLiteral("applications")).toArray();
    for (const auto &value : installed) {
        const auto application = value.toObject();
        const QString role = application.value(QStringLiteral("role")).toString();
        roles.insert(role);
        QVERIFY(!application.value(QStringLiteral("name")).toString().isEmpty());
        QVERIFY(application.value(QStringLiteral("installed")).toBool());
        QCOMPARE(integration.preferredDesktopId(role), application.value(QStringLiteral("desktopId")).toString());
    }
    QCOMPARE(roles.size(), 11);
    QVERIFY(!roles.contains(QStringLiteral("settings")));
    QVERIFY(!roles.contains(QStringLiteral("browser")));
    QCOMPARE(integration.preferredDesktopId(QStringLiteral("mail")), forma("Mail"));
    QCOMPARE(integration.preferredDesktopId(QStringLiteral("appstore")), forma("AppStore"));
    QCOMPARE(integration.preferredDesktopId(QStringLiteral("screenshot")), forma("Screenshot"));
    QVERIFY(integration.preferredDesktopId(QStringLiteral("settings")).isEmpty());
    QVERIFY(integration.preferredDesktopId(QStringLiteral("browser")).isEmpty());
    QVERIFY(integration.preferredDesktopId(QStringLiteral("unknown")).isEmpty());
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("x-scheme-handler/mailto")), forma("Mail") + QLatin1Char(';'));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("x-scheme-handler/appstream")), forma("AppStore") + QLatin1Char(';'));
    QVERIFY(!hasEntry(f.configFile(), QStringLiteral("application/pdf")));
    QVERIFY(!hasEntry(f.configFile(), QStringLiteral("application/zip")));
    QVERIFY(!hasEntry(f.configFile(), QStringLiteral("x-scheme-handler/https")));
    f.installed.remove(mayo("Finder"));
    QVERIFY(integration.preferredDesktopId(QStringLiteral("finder")).isEmpty());
}

void FormaIntegrationTest::terminalExecutionPreferencesRemainUntouched()
{
    Fixture f;
    f.installed = {mayo("Terminal")};
    const QByteArray original = "[General]\nTerminalApplication=konsole\n"
        "TerminalService=org.kde.konsole.desktop\nBrowserApplication=browser.desktop\n";
    QVERIFY(writeBytes(f.configFile("kdeglobals"), original));
    auto integration = f.integration();
    QVERIFY(!integration.snapshot().value(QStringLiteral("terminalCommandSupported")).toBool());
    const auto enabled = integration.setEnabled(true);
    QVERIFY(enabled.value(QStringLiteral("ready")).toBool());
    QVERIFY(!enabled.value(QStringLiteral("terminalCommandSupported")).toBool());
    QCOMPARE(integration.preferredDesktopId(QStringLiteral("terminal")), mayo("Terminal"));
    QCOMPARE(readBytes(f.configFile("kdeglobals")), original);
    QVERIFY(readState(f).value(QStringLiteral("entries")).toArray().isEmpty());
    QVERIFY(!QFileInfo::exists(f.configFile()));
    QVERIFY(integration.setEnabled(false).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readBytes(f.configFile("kdeglobals")), original);
    QVERIFY(integration.preferredDesktopId(QStringLiteral("terminal")).isEmpty());
}

void FormaIntegrationTest::legacyTerminalBackupsCanRestore()
{
    Fixture f;
    QVERIFY(writeBytes(f.configFile("kdeglobals"),
        "[General]\nTerminalApplication=forma-terminal\n"
        "TerminalService=io.github.egely1337.Mayonnaise.Terminal.desktop\n"));
    QJsonObject application{{QStringLiteral("file"), QStringLiteral("kdeglobals")},
        {QStringLiteral("group"), QStringLiteral("General")},
        {QStringLiteral("key"), QStringLiteral("TerminalApplication")},
        {QStringLiteral("existed"), true}, {QStringLiteral("original"), QStringLiteral("konsole")},
        {QStringLiteral("owned"), QStringLiteral("forma-terminal")},
        {QStringLiteral("previousOwned"), QString()}};
    auto service = application;
    service.insert(QStringLiteral("key"), QStringLiteral("TerminalService"));
    service.insert(QStringLiteral("existed"), false);
    service.insert(QStringLiteral("original"), QString());
    service.insert(QStringLiteral("owned"), mayo("Terminal"));
    auto state = emptyState();
    state.insert(QStringLiteral("enabled"), true);
    state.insert(QStringLiteral("entries"), QJsonArray{application, service});
    QVERIFY(writeBytes(f.stateFile(), QJsonDocument(state).toJson()));
    auto integration = f.integration();
    QVERIFY(integration.setEnabled(false).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readEntry(f.configFile("kdeglobals"), QStringLiteral("TerminalApplication"), "General"), QStringLiteral("konsole"));
    QVERIFY(!hasEntry(f.configFile("kdeglobals"), QStringLiteral("TerminalService"), "General"));
}

void FormaIntegrationTest::missingApplicationsAndAudioFallback()
{
    Fixture f;
    f.installed = {mayo("VideoPlayer")};
    QVERIFY(writeBytes(f.configFile(), "[Default Applications]\ntext/plain=kos-text.desktop;\n"));
    auto integration = f.integration();
    QVERIFY(integration.setEnabled(true).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("audio/mpeg")), mayo("VideoPlayer") + QLatin1Char(';'));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("audio/flac")), mayo("VideoPlayer") + QLatin1Char(';'));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("video/mp4")), mayo("VideoPlayer") + QLatin1Char(';'));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("text/plain")), QStringLiteral("kos-text.desktop;"));
    QVERIFY(!hasEntry(f.configFile(), QStringLiteral("inode/directory")));
    QVERIFY(!hasEntry(f.configFile(), QStringLiteral("image/png")));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("audio/opus")), mayo("VideoPlayer") + QLatin1Char(';'));
    QVERIFY(!hasEntry(f.configFile(), QStringLiteral("x-scheme-handler/mailto")));
    QVERIFY(!hasEntry(f.configFile(), QStringLiteral("x-scheme-handler/appstream")));
    QVERIFY(!QFileInfo::exists(f.configFile("kdeglobals")));
    QVERIFY(!QFileInfo::exists(f.configFile("kde-mimeapps.list")));
    QVERIFY(integration.preferredDesktopId(QStringLiteral("music")).isEmpty());
    QCOMPARE(integration.preferredDesktopId(QStringLiteral("video")), mayo("VideoPlayer"));
    f.installed.clear();
    QVERIFY(integration.setEnabled(false).value(QStringLiteral("ready")).toBool());
    QVERIFY(!hasEntry(f.configFile(), QStringLiteral("audio/mpeg")));
}

void FormaIntegrationTest::restoresOriginalAndAbsentKeys()
{
    Fixture f;
    f.installed = {mayo("Finder"), mayo("Terminal"), mayo("TextEditor")};
    const QByteArray mime = "[Default Applications]\ninode/directory=org.kde.dolphin.desktop;\n"
        "text/plain=kos-text.desktop;other.desktop;\ntext/html=browser.desktop;\n"
        "x-scheme-handler/http=browser.desktop;\nx-scheme-handler/https=browser.desktop;\n"
        "application/pdf=pdf.desktop;\napplication/zip=ark.desktop;\napplication/x-unknown=custom.desktop;\n"
        "[Other]\ncustom=leave-me\n";
    QVERIFY(writeBytes(f.configFile(), mime));
    QVERIFY(writeBytes(f.configFile("kde-mimeapps.list"),
        "[Default Applications]\ninode/directory=kde-original.desktop;\ntext/html=browser.desktop;\n"));
    QVERIFY(writeBytes(f.configFile("kdeglobals"),
        "[General]\nTerminalApplication=konsole --noclose\nBrowserApplication=browser.desktop\n"
        "[KDE]\nsettings=kos-settings.desktop\n"));
    auto integration = f.integration();
    QVERIFY(integration.setEnabled(true).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readEntry(f.configFile("kde-mimeapps.list"), QStringLiteral("inode/directory")), mayo("Finder") + QLatin1Char(';'));
    QCOMPARE(readEntry(f.configFile("kdeglobals"), QStringLiteral("TerminalApplication"), "General"), QStringLiteral("konsole --noclose"));
    QVERIFY(!hasEntry(f.configFile("kdeglobals"), QStringLiteral("TerminalService"), "General"));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("text/html")), QStringLiteral("browser.desktop;"));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("x-scheme-handler/https")), QStringLiteral("browser.desktop;"));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("application/pdf")), QStringLiteral("pdf.desktop;"));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("application/zip")), QStringLiteral("ark.desktop;"));
    QCOMPARE(readEntry(f.configFile("kdeglobals"), QStringLiteral("settings"), "KDE"), QStringLiteral("kos-settings.desktop"));
    const auto state = readState(f);
    QCOMPARE(state.value(QStringLiteral("schema")).toInt(), 1);
    const auto original = backupEntry(state, QStringLiteral("mimeapps.list"), QStringLiteral("text/plain"));
    QVERIFY(original.value(QStringLiteral("existed")).toBool());
    QCOMPARE(original.value(QStringLiteral("original")).toString(), QStringLiteral("kos-text.desktop;other.desktop;"));
    QVERIFY(backupEntry(state, QStringLiteral("kdeglobals"), QStringLiteral("TerminalApplication")).isEmpty());
    QVERIFY(backupEntry(state, QStringLiteral("kdeglobals"), QStringLiteral("TerminalService")).isEmpty());
    QVERIFY(integration.setEnabled(true).value(QStringLiteral("ready")).toBool());
    QCOMPARE(backupEntry(readState(f), QStringLiteral("mimeapps.list"), QStringLiteral("text/plain")), original);
    QVERIFY(integration.setEnabled(false).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("inode/directory")), QStringLiteral("org.kde.dolphin.desktop;"));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("text/plain")), QStringLiteral("kos-text.desktop;other.desktop;"));
    QVERIFY(!hasEntry(f.configFile(), QStringLiteral("application/json")));
    QCOMPARE(readEntry(f.configFile("kde-mimeapps.list"), QStringLiteral("inode/directory")), QStringLiteral("kde-original.desktop;"));
    QVERIFY(!hasEntry(f.configFile("kde-mimeapps.list"), QStringLiteral("text/plain")));
    QCOMPARE(readEntry(f.configFile("kdeglobals"), QStringLiteral("TerminalApplication"), "General"), QStringLiteral("konsole --noclose"));
    QVERIFY(!hasEntry(f.configFile("kdeglobals"), QStringLiteral("TerminalService"), "General"));
    QCOMPARE(readEntry(f.configFile("kdeglobals"), QStringLiteral("BrowserApplication"), "General"), QStringLiteral("browser.desktop"));
    QCOMPARE(readEntry(f.configFile("kdeglobals"), QStringLiteral("settings"), "KDE"), QStringLiteral("kos-settings.desktop"));
    for (const auto *key : {"text/html", "x-scheme-handler/http", "x-scheme-handler/https"})
        QCOMPARE(readEntry(f.configFile(), QString::fromLatin1(key)), QStringLiteral("browser.desktop;"));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("application/pdf")), QStringLiteral("pdf.desktop;"));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("application/zip")), QStringLiteral("ark.desktop;"));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("application/x-unknown")), QStringLiteral("custom.desktop;"));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("custom"), "Other"), QStringLiteral("leave-me"));
    QVERIFY(readState(f).value(QStringLiteral("entries")).toArray().isEmpty());
    QVERIFY(!integration.snapshot().value(QStringLiteral("restorePending")).toBool());
}

void FormaIntegrationTest::repeatEnableAndNewInstallationKeepFirstBackup()
{
    Fixture f;
    f.installed = {mayo("VideoPlayer")};
    QVERIFY(writeBytes(f.configFile(), "[Default Applications]\naudio/mpeg=old-music.desktop;\ntext/plain=old-text.desktop;\n"));
    auto integration = f.integration();
    QVERIFY(integration.setEnabled(true).value(QStringLiteral("ready")).toBool());
    const auto first = backupEntry(readState(f), QStringLiteral("mimeapps.list"), QStringLiteral("audio/mpeg"));
    f.installed.insert(mayo("Music"));
    f.installed.insert(mayo("TextEditor"));
    QVERIFY(integration.setEnabled(true).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("audio/mpeg")), mayo("Music") + QLatin1Char(';'));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("audio/opus")), mayo("Music") + QLatin1Char(';'));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("text/plain")), mayo("TextEditor") + QLatin1Char(';'));
    const auto updated = backupEntry(readState(f), QStringLiteral("mimeapps.list"), QStringLiteral("audio/mpeg"));
    QCOMPARE(updated.value(QStringLiteral("original")), first.value(QStringLiteral("original")));
    QCOMPARE(updated.value(QStringLiteral("existed")), first.value(QStringLiteral("existed")));
    QVERIFY(integration.setEnabled(true).value(QStringLiteral("ready")).toBool());
    QVERIFY(integration.setEnabled(false).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("audio/mpeg")), QStringLiteral("old-music.desktop;"));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("text/plain")), QStringLiteral("old-text.desktop;"));
    QVERIFY(!hasEntry(f.configFile(), QStringLiteral("audio/opus")));
}

void FormaIntegrationTest::userChangesAreNotOverwrittenOnDisable()
{
    Fixture f;
    f.installed = {mayo("TextEditor"), mayo("Terminal")};
    QVERIFY(writeBytes(f.configFile(), "[Default Applications]\ntext/plain=original.desktop;\n"));
    auto integration = f.integration();
    QVERIFY(integration.setEnabled(true).value(QStringLiteral("ready")).toBool());
    QVERIFY(writeEntry(f.configFile(), QStringLiteral("text/plain"), QStringLiteral("user-chosen.desktop;")));
    QVERIFY(writeEntry(f.configFile(), QStringLiteral("application/json"), QStringLiteral("user-json.desktop;")));
    QVERIFY(writeEntry(f.configFile("kdeglobals"), QStringLiteral("TerminalService"), QStringLiteral("user-terminal.desktop"), "General"));
    QVERIFY(integration.setEnabled(false).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("text/plain")), QStringLiteral("user-chosen.desktop;"));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("application/json")), QStringLiteral("user-json.desktop;"));
    QCOMPARE(readEntry(f.configFile("kdeglobals"), QStringLiteral("TerminalService"), "General"), QStringLiteral("user-terminal.desktop"));
    QVERIFY(!hasEntry(f.configFile("kdeglobals"), QStringLiteral("TerminalApplication"), "General"));
}

void FormaIntegrationTest::corruptStateIsRejected_data()
{
    QTest::addColumn<QByteArray>("bytes");
    QTest::newRow("invalid-json") << QByteArray("{broken");
    auto state = emptyState();
    state.insert(QStringLiteral("schema"), 2);
    QTest::newRow("unsupported-schema") << QJsonDocument(state).toJson();
    state = emptyState();
    state.insert(QStringLiteral("enabled"), QStringLiteral("true"));
    QTest::newRow("wrong-type") << QJsonDocument(state).toJson();
    state = emptyState();
    state.insert(QStringLiteral("enabled"), true);
    QJsonObject entry{{QStringLiteral("file"), QStringLiteral("../outside")},
        {QStringLiteral("group"), QStringLiteral("Default Applications")},
        {QStringLiteral("key"), QStringLiteral("text/plain")}, {QStringLiteral("existed"), false},
        {QStringLiteral("original"), QString()}, {QStringLiteral("owned"), mayo("TextEditor") + QLatin1Char(';')},
        {QStringLiteral("previousOwned"), QString()}};
    state.insert(QStringLiteral("entries"), QJsonArray{entry});
    QTest::newRow("path-injection") << QJsonDocument(state).toJson();
    entry.insert(QStringLiteral("file"), QStringLiteral("mimeapps.list"));
    entry.insert(QStringLiteral("key"), QStringLiteral("x-scheme-handler/https"));
    state.insert(QStringLiteral("entries"), QJsonArray{entry});
    QTest::newRow("browser-key-injection") << QJsonDocument(state).toJson();
    entry.insert(QStringLiteral("key"), QStringLiteral("text/plain"));
    state.insert(QStringLiteral("entries"), QJsonArray{entry, entry});
    QTest::newRow("duplicate-key") << QJsonDocument(state).toJson();
    entry.insert(QStringLiteral("owned"), QStringLiteral("unexpected.desktop;"));
    state.insert(QStringLiteral("entries"), QJsonArray{entry});
    QTest::newRow("owned-value-injection") << QJsonDocument(state).toJson();
    QTest::newRow("oversized") << QByteArray(512 * 1024 + 1, ' ');
}

void FormaIntegrationTest::corruptStateIsRejected()
{
    QFETCH(QByteArray, bytes);
    Fixture f;
    f.installed = {mayo("TextEditor")};
    const QByteArray configBytes = "[Default Applications]\ntext/plain=original.desktop;\n";
    QVERIFY(writeBytes(f.configFile(), configBytes));
    QVERIFY(writeBytes(f.stateFile(), bytes));
    auto integration = f.integration();
    QVERIFY(!integration.snapshot().value(QStringLiteral("ready")).toBool());
    QVERIFY(!integration.snapshot().value(QStringLiteral("available")).toBool());
    const auto result = integration.setEnabled(true);
    QVERIFY(!result.value(QStringLiteral("ready")).toBool());
    QVERIFY(!result.value(QStringLiteral("enabled")).toBool());
    QVERIFY(!result.value(QStringLiteral("error")).toString().isEmpty());
    QVERIFY(!integration.setEnabled(false).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readBytes(f.configFile()), configBytes);
    QCOMPARE(readBytes(f.stateFile()), bytes);
    QVERIFY(!QFileInfo::exists(QDir(f.state).filePath(QStringLiteral("forma-integration.lock"))));
    QVERIFY(!QFileInfo::exists(f.temporary.filePath(QStringLiteral("outside"))));
}

void FormaIntegrationTest::immutablePreferenceDoesNotReportTakeover()
{
    Fixture f;
    f.installed = {mayo("TextEditor")};
    const QByteArray original = "[Default Applications]\ntext/plain[$i]=original.desktop;\n";
    QVERIFY(writeBytes(f.configFile(), original));
    auto integration = f.integration();
    const auto state = integration.setEnabled(true);
    QVERIFY(!state.value(QStringLiteral("ready")).toBool());
    QVERIFY(state.value(QStringLiteral("available")).toBool());
    QVERIFY(!state.value(QStringLiteral("enabled")).toBool());
    QCOMPARE(readBytes(f.configFile()), original);
    QVERIFY(!QFileInfo::exists(f.stateFile()));
}

void FormaIntegrationTest::concurrentWriterIsRejected()
{
    Fixture f;
    f.installed = {mayo("Finder")};
    auto integration = f.integration();
    QVERIFY(integration.setEnabled(true).value(QStringLiteral("ready")).toBool());
    const auto before = readBytes(f.stateFile());
    const auto configBefore = readBytes(f.configFile());
    QLockFile lock(QDir(f.state).filePath(QStringLiteral("forma-integration.lock")));
    QVERIFY(lock.tryLock(0));
    const auto result = integration.setEnabled(false);
    QVERIFY(!result.value(QStringLiteral("ready")).toBool());
    QVERIFY(result.value(QStringLiteral("enabled")).toBool());
    QVERIFY(!result.value(QStringLiteral("busy")).toBool());
    QCOMPARE(readBytes(f.stateFile()), before);
    QCOMPARE(readBytes(f.configFile()), configBefore);
    lock.unlock();
    QVERIFY(integration.setEnabled(false).value(QStringLiteral("ready")).toBool());
}

void FormaIntegrationTest::backupFailureDoesNotChangeConfigAndCanRetry()
{
    Fixture f;
    const QByteArray original = "[Default Applications]\ntext/plain=original.desktop;\n";
    QVERIFY(writeBytes(f.configFile(), original));
    bool sabotage = true;
    FormaIntegration integration(f.config, f.state, [&](const QString &id) {
        // Deterministic failure between the initial state read and write-ahead save.
        if (sabotage) {
            sabotage = false;
            QDir().mkpath(f.stateFile());
        }
        return id == mayo("TextEditor");
    });
    const auto result = integration.setEnabled(true);
    QVERIFY(!result.value(QStringLiteral("ready")).toBool());
    QVERIFY(!result.value(QStringLiteral("enabled")).toBool());
    QCOMPARE(readBytes(f.configFile()), original);
    QVERIFY(QDir().rmdir(f.stateFile()));
    QVERIFY(integration.setEnabled(true).value(QStringLiteral("ready")).toBool());
    QVERIFY(integration.setEnabled(false).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("text/plain")), QStringLiteral("original.desktop;"));
}

void FormaIntegrationTest::syncFailureRetainsBackupAndCanRecover()
{
    Fixture f;
    f.installed = {mayo("TextEditor")};
    const QByteArray original = "[Default Applications]\ntext/plain=original.desktop;\n";
    QVERIFY(writeBytes(f.configFile(), original));
    const auto directoryPermissions = QFileInfo(f.config).permissions();
    const auto filePermissions = QFileInfo(f.configFile()).permissions();
    struct RestorePermissions {
        QString directory;
        QString file;
        QFileDevice::Permissions directoryPermissions;
        QFileDevice::Permissions filePermissions;
        ~RestorePermissions() {
            QFile::setPermissions(directory, directoryPermissions);
            QFile::setPermissions(file, filePermissions);
        }
    } restore{f.config, f.configFile(), directoryPermissions, filePermissions};
    QVERIFY(QFile::setPermissions(f.config, QFileDevice::ReadOwner | QFileDevice::ExeOwner));
    QVERIFY(QFile::setPermissions(f.configFile(), QFileDevice::ReadOwner));
    if (QFileInfo(f.config).isWritable() || QFileInfo(f.configFile()).isWritable())
        QSKIP("This environment bypasses read-only permissions (for example root)");
    auto integration = f.integration();
    const auto failed = integration.setEnabled(true);
    QVERIFY(!failed.value(QStringLiteral("ready")).toBool());
    QVERIFY(!failed.value(QStringLiteral("enabled")).toBool());
    QVERIFY(failed.value(QStringLiteral("restorePending")).toBool());
    QVERIFY(!failed.value(QStringLiteral("error")).toString().isEmpty());
    QCOMPARE(readBytes(f.configFile()), original);
    QVERIFY(!readState(f).value(QStringLiteral("entries")).toArray().isEmpty());
    QVERIFY(QFile::setPermissions(f.config, directoryPermissions));
    QVERIFY(QFile::setPermissions(f.configFile(), filePermissions));
    auto retry = f.integration();
    QVERIFY(retry.snapshot().value(QStringLiteral("restorePending")).toBool());
    QVERIFY(retry.setEnabled(true).value(QStringLiteral("ready")).toBool());
    QVERIFY(retry.setEnabled(false).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("text/plain")), QStringLiteral("original.desktop;"));
}

void FormaIntegrationTest::incompleteFinalSaveCanRestore()
{
    Fixture f;
    f.installed = {mayo("TextEditor")};
    QVERIFY(writeBytes(f.configFile(), "[Default Applications]\ntext/plain=original.desktop;\n"));
    auto integration = f.integration();
    QVERIFY(integration.setEnabled(true).value(QStringLiteral("ready")).toBool());
    // Model a crash/final QSaveFile failure after config sync, before enabled is committed.
    auto pending = readState(f);
    pending.insert(QStringLiteral("enabled"), false);
    pending.insert(QStringLiteral("restorePending"), true);
    pending.insert(QStringLiteral("pendingAction"), QStringLiteral("apply"));
    pending.insert(QStringLiteral("error"), QStringLiteral("Final save failed"));
    QVERIFY(writeBytes(f.stateFile(), QJsonDocument(pending).toJson()));
    auto recovered = f.integration();
    const auto status = recovered.snapshot();
    QVERIFY(!status.value(QStringLiteral("ready")).toBool());
    QVERIFY(!status.value(QStringLiteral("enabled")).toBool());
    QVERIFY(status.value(QStringLiteral("restorePending")).toBool());
    QVERIFY(recovered.preferredDesktopId(QStringLiteral("text")).isEmpty());
    QVERIFY(recovered.setEnabled(false).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("text/plain")), QStringLiteral("original.desktop;"));
    QVERIFY(!hasEntry(f.configFile(), QStringLiteral("application/json")));
}

void FormaIntegrationTest::incompleteRestoreCanRetry()
{
    Fixture f;
    f.installed = {mayo("TextEditor")};
    QVERIFY(writeBytes(f.configFile(), "[Default Applications]\ntext/plain=original.desktop;\n"));
    auto integration = f.integration();
    QVERIFY(integration.setEnabled(true).value(QStringLiteral("ready")).toBool());
    auto pending = readState(f);
    pending.insert(QStringLiteral("restorePending"), true);
    pending.insert(QStringLiteral("pendingAction"), QStringLiteral("restore"));
    QVERIFY(writeBytes(f.stateFile(), QJsonDocument(pending).toJson()));
    QVERIFY(writeEntry(f.configFile(), QStringLiteral("text/plain"), QStringLiteral("original.desktop;")));
    QVERIFY(writeEntry(f.configFile(), QStringLiteral("application/json"), QStringLiteral("user-json.desktop;")));
    auto recovered = f.integration();
    const auto before = readBytes(f.configFile());
    QVERIFY(!recovered.setEnabled(true).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readBytes(f.configFile()), before);
    QVERIFY(recovered.setEnabled(false).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("text/plain")), QStringLiteral("original.desktop;"));
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("application/json")), QStringLiteral("user-json.desktop;"));
    QVERIFY(!recovered.snapshot().value(QStringLiteral("enabled")).toBool());
}

void FormaIntegrationTest::previousAudioOwnerCanRestore()
{
    Fixture f;
    f.installed = {mayo("VideoPlayer")};
    QVERIFY(writeBytes(f.configFile(), "[Default Applications]\naudio/mpeg=original.desktop;\n"));
    auto integration = f.integration();
    QVERIFY(integration.setEnabled(true).value(QStringLiteral("ready")).toBool());
    auto pending = readState(f);
    auto entries = pending.value(QStringLiteral("entries")).toArray();
    for (qsizetype i = 0; i < entries.size(); ++i) {
        auto row = entries.at(i).toObject();
        if (row.value(QStringLiteral("key")).toString() != QLatin1String("audio/mpeg")) continue;
        row.insert(QStringLiteral("previousOwned"), row.value(QStringLiteral("owned")));
        row.insert(QStringLiteral("owned"), mayo("Music") + QLatin1Char(';'));
        entries.replace(i, row);
    }
    pending.insert(QStringLiteral("entries"), entries);
    pending.insert(QStringLiteral("restorePending"), true);
    pending.insert(QStringLiteral("pendingAction"), QStringLiteral("apply"));
    QVERIFY(writeBytes(f.stateFile(), QJsonDocument(pending).toJson()));
    auto recovered = f.integration();
    QVERIFY(recovered.setEnabled(false).value(QStringLiteral("ready")).toBool());
    QCOMPARE(readEntry(f.configFile(), QStringLiteral("audio/mpeg")), QStringLiteral("original.desktop;"));
}

QTEST_GUILESS_MAIN(FormaIntegrationTest)
#include "test_forma_integration.moc"
