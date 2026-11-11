#include "AppCatalog.h"
#include <QtTest>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDateTime>
#include <QFileInfo>
#include <QProcess>
#include <QTemporaryDir>
#include <QLockFile>
#include <QCryptographicHash>
#include <QNetworkProxy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QScopeGuard>

class CatalogTest : public QObject {
    Q_OBJECT
    QTemporaryDir root;
    QString fingerprint;
    QByteArray publicKey;
    QByteArray gpg(const QStringList& args, const QByteArray& input = {})
    {
        QProcess process;
        process.setProgram("gpg");
        process.setArguments(QStringList{"--homedir", root.filePath("gnupg"), "--batch", "--yes", "--pinentry-mode", "loopback", "--passphrase", ""} + args);
        process.start();
        if (!process.waitForStarted(5000)) return {};
        process.write(input); process.closeWriteChannel();
        if (!process.waitForFinished(20000)) { process.kill(); process.waitForFinished(); return {}; }
        return process.exitCode() == 0 ? process.readAllStandardOutput() : QByteArray{};
    }
    bool write(const QString& path, const QByteArray& bytes)
    {
        QDir().mkpath(QFileInfo(path).absolutePath()); QFile file(path);
        return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
    }
    QVariantMap catalog(int sequence = 1) const
    {
        const auto now = QDateTime::currentDateTimeUtc();
        return {{"schemaVersion", 1}, {"sourceId", "fixture"}, {"sequence", sequence},
            {"issuedAt", now.addSecs(-60).toString(Qt::ISODate)}, {"expiresAt", now.addDays(1).toString(Qt::ISODate)},
            {"apps", QVariantList{QVariantMap{{"appId", "org.example.Notes"}, {"key", "notes"}, {"format", "flatpak"},
                {"name", QVariantMap{{"en", "Notes"}}}, {"description", QVariantMap{{"en", "A notes app"}}}, {"repository", "Example/Notes"},
                {"manifest", "flatpak-release.json"}, {"status", "active"}}}}};
    }
    QByteArray signature(const QByteArray& bytes) { return gpg({"--armor", "--detach-sign", "--output", "-"}, bytes); }
    bool snapshot(const QVariantMap& value)
    {
        const auto bytes = QJsonDocument::fromVariant(value).toJson();
        const auto sig = signature(bytes);
        return !sig.isEmpty() && write(AppCatalog::stateDirectory() + (AppCatalog::testMode() ? "/test/catalogs/fixture.json" : "/catalogs/fixture.json"),
            QJsonDocument::fromVariant(QVariantMap{{"catalog", bytes.toBase64()}, {"signature", sig.toBase64()}}).toJson());
    }
private slots:
    void pageRefreshPolicy()
    {
        const auto now = QDateTime::currentDateTimeUtc();
        auto data = catalog(); data["schemaVersion"] = 2;
        QVariantMap state{{"lastSuccess", now.toString(Qt::ISODate)}, {"error", ""}};
        QVERIFY(!AppCatalog::needsRefresh(data, state, now));
        QVERIFY(AppCatalog::needsRefresh({}, state, now));
        QVERIFY(AppCatalog::needsRefresh(data, {}, now));
        QVERIFY(!AppCatalog::needsRefresh(data, state, now.addSecs(1799)));
        QVERIFY(AppCatalog::needsRefresh(data, state, now.addSecs(1800)));
        QVERIFY(AppCatalog::needsRefresh(data, state, now.addSecs(-60)));
        auto expired = data; expired["expiresAt"] = now.toString(Qt::ISODate);
        QVERIFY(AppCatalog::needsRefresh(expired, state, now));
        // Old clients wrote only lastChecked; new clients preserve successful
        // freshness across failures instead of treating a failed request as fresh.
        QVariantMap legacy{{"lastChecked", now.toString(Qt::ISODate)}, {"error", ""}};
        QVERIFY(!AppCatalog::needsRefresh(data, legacy, now));
        legacy["error"] = "offline";
        QVERIFY(AppCatalog::needsRefresh(data, legacy, now));
        QVERIFY(AppCatalog::needsRefresh(catalog(), state, now));
        state["clientCatalogSchema"] = 2;
        QVERIFY(!AppCatalog::needsRefresh(catalog(), state, now));
        state["lastSuccess"] = now.addSecs(-1800).toString(Qt::ISODate);
        state["lastChecked"] = now.toString(Qt::ISODate);
        state["error"] = "offline";
        QVERIFY(AppCatalog::needsRefresh(data, state, now));
    }
    void initTestCase()
    {
        QVERIFY(root.isValid());
        qputenv("XDG_CONFIG_HOME", root.filePath("config").toUtf8());
        qputenv("XDG_STATE_HOME", root.filePath("state").toUtf8());
        QVERIFY(QDir().mkpath(root.filePath("gnupg")));
        QVERIFY(QFile::setPermissions(root.filePath("gnupg"), QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner));
        gpg({"--quick-generate-key", "Catalog Test <test@example.invalid>", "ed25519", "sign", "1d"});
        const auto listing = gpg({"--with-colons", "--list-keys"});
        for (const auto& line : listing.split('\n')) if (line.startsWith("fpr:")) { fingerprint = QString::fromLatin1(line.split(':').value(9)); break; }
        QVERIFY2(!fingerprint.isEmpty(), "The VM test environment requires gpg and gpgv");
        publicKey = gpg({"--export", fingerprint});
        QVERIFY(!publicKey.isEmpty());
        QVERIFY(write(root.filePath("public.gpg"), publicKey));
        QCOMPARE(AppCatalog::addSource("fixture", "Example/catalog", fingerprint, root.filePath("public.gpg")), QString());
    }
    void pinnedIconValidationAndCache()
    {
        const auto png = QByteArray::fromBase64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a9sAAAAASUVORK5CYII=");
        const auto digest = QString::fromLatin1(QCryptographicHash::hash(png, QCryptographicHash::Sha256).toHex());
        QVariantMap icon{{"url", "https://raw.githubusercontent.com/Example/catalog/" + QString(40, 'a') + "/icons/org.example.Notes.png"},
            {"sha256", digest}, {"size", png.size()}};
        auto data = catalog(); auto entry = data.value("apps").toList().first().toMap(); entry["icon"] = icon;
        data["apps"] = QVariantList{entry};
        QCOMPARE(AppCatalog::validateUpdate(data, {}, "fixture"), QString());
        QVERIFY(AppCatalog::iconFile(entry).isEmpty());
        const auto path = AppCatalog::stateDirectory() + "/icons/" + digest + ".png";
        QVERIFY(write(path, png)); QVERIFY(!AppCatalog::iconFile(entry).isEmpty());
        QVERIFY(write(path, png + "changed")); QVERIFY(AppCatalog::iconFile(entry).isEmpty());
        icon["url"] = "https://raw.githubusercontent.com/Example/catalog/main/icons/org.example.Notes.png";
        entry["icon"] = icon; data["apps"] = QVariantList{entry};
        QVERIFY(!AppCatalog::validateUpdate(data, {}, "fixture").isEmpty());
        entry.remove("icon"); data["apps"] = QVariantList{entry}; data["schemaVersion"] = 2;
        QVERIFY(!AppCatalog::validateUpdate(data, {}, "fixture").isEmpty());
        entry["release"] = QVariant(); data["apps"] = QVariantList{entry};
        QCOMPARE(AppCatalog::validateUpdate(data, {}, "fixture"), QString());
    }
    void freshCatalogOnlyRetriesMissingIcons()
    {
        QFile config(root.filePath("config/kos-settings/app-sources.json"));
        QVERIFY(config.open(QIODevice::ReadOnly));
        const auto original = config.readAll(); config.close();
        const auto oldProxy = QNetworkProxy::applicationProxy();
        const auto restore = qScopeGuard([&] {
            write(config.fileName(), original);
            QNetworkProxy::setApplicationProxy(oldProxy);
        });
        QVERIFY(write(config.fileName(), QJsonDocument::fromVariant(QVariantMap{{"sources", QVariantList{QVariantMap{
            {"id", "fixture"}, {"repository", "Example/catalog"}, {"fingerprint", fingerprint},
            {"publicKey", publicKey.toBase64()}}}}}).toJson()));
        const auto png = QByteArray::fromBase64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a9sAAAAASUVORK5CYII=");
        const auto digest = QString::fromLatin1(QCryptographicHash::hash(png, QCryptographicHash::Sha256).toHex());
        auto data = catalog(); data["schemaVersion"] = 2;
        auto entry = data.value("apps").toList().first().toMap();
        entry["release"] = QVariant();
        entry["icon"] = QVariantMap{{"url", "https://raw.githubusercontent.com/Example/catalog/" + QString(40, 'a') + "/icons/org.example.Notes.png"},
            {"size", png.size()}, {"sha256", digest}};
        data["apps"] = QVariantList{entry};
        QVERIFY(snapshot(data));
        const auto path = AppCatalog::stateDirectory() + "/icons/" + digest + ".png";
        QFile::remove(path);
        const QVariantMap fresh{{"lastSuccess", QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}, {"error", ""}};
        QVERIFY(AppCatalog::writeState("source-fixture", fresh));
        QTcpServer proxy; QVERIFY(proxy.listen(QHostAddress::LocalHost));
        QNetworkProxy::setApplicationProxy(QNetworkProxy(QNetworkProxy::HttpProxy, "127.0.0.1", proxy.serverPort()));
        QByteArray requests;
        connect(&proxy, &QTcpServer::newConnection, this, [&] {
            auto socket = proxy.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
                requests += socket->readAll();
                socket->write("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                socket->disconnectFromHost();
            });
        });
        QCOMPARE(AppCatalog::refresh([] { return false; }, true), QString());
        QVERIFY(requests.contains("raw.githubusercontent.com"));
        QVERIFY(!requests.contains("api.github.com"));
        QVERIFY(AppCatalog::iconFile(entry).isEmpty());
        QVERIFY(AppCatalog::find("org.example.Notes").value("active").toBool());
        const auto firstRequests = requests;
        QCOMPARE(AppCatalog::refresh([] { return false; }, true), QString());
        QCOMPARE(requests, firstRequests); // Failed artwork is throttled too.
        QVERIFY(write(path, png));
        QVERIFY(AppCatalog::writeState("source-fixture", fresh));
        QCOMPARE(AppCatalog::refresh([] { return false; }, true), QString());
        QCOMPARE(requests, firstRequests); // Valid cached bytes require no download.
        QVERIFY(!AppCatalog::iconFile(entry).isEmpty());
    }
    void githubBoundaries()
    {
        QVERIFY(AppCatalog::githubRepository("third-party/notes"));
        QVERIFY(!AppCatalog::githubRepository("https://github.com/third-party/notes"));
        QVERIFY(!AppCatalog::githubRepository("../notes"));
        QVERIFY(AppCatalog::githubUrl(QUrl("https://github.com/third-party/notes/releases/download/v1.0.0/app.flatpak"), "third-party/notes", false));
        QVERIFY(!AppCatalog::githubUrl(QUrl("https://github.com/attacker/notes/releases/download/v1.0.0/app.flatpak"), "third-party/notes", false));
        QVERIFY(!AppCatalog::githubUrl(QUrl("https://raw.githubusercontent.com/third-party/notes/main/app.flatpak"), "third-party/notes", false));
        QVERIFY(!AppCatalog::githubUrl(QUrl("https://release-assets.githubusercontent.com/file"), "third-party/notes", false));
        QVERIFY(AppCatalog::githubUrl(QUrl("https://release-assets.githubusercontent.com/file"), "third-party/notes", true));
    }
    void signatureIsMandatoryForDirectory()
    {
        const QByteArray bytes = "a directory";
        const auto sig = signature(bytes);
        QVERIFY(AppCatalog::verify(bytes, sig, publicKey, fingerprint));
        QVERIFY(!AppCatalog::verify(bytes + "tampered", sig, publicKey, fingerprint));
        QVERIFY(!AppCatalog::verify(bytes, {}, publicKey, fingerprint));
        QVERIFY(!AppCatalog::verify(bytes, sig, publicKey, QString(40, '0')));
    }
    void rollbackAndExpiry()
    {
        const auto first = catalog(2);
        QVERIFY(AppCatalog::validateUpdate(first, {}, "fixture").isEmpty());
        QVERIFY(AppCatalog::validateUpdate(first, first, "fixture").isEmpty());
        QVERIFY(!AppCatalog::validateUpdate(catalog(1), first, "fixture").isEmpty());
        auto changed = first; changed["apps"] = QVariantList{};
        QVERIFY(!AppCatalog::validateUpdate(changed, first, "fixture").isEmpty());
        auto expired = catalog(3); expired["issuedAt"] = QDateTime::currentDateTimeUtc().addDays(-2).toString(Qt::ISODate);
        expired["expiresAt"] = QDateTime::currentDateTimeUtc().addDays(-1).toString(Qt::ISODate);
        QVERIFY(!AppCatalog::validateUpdate(expired, first, "fixture").isEmpty());
    }
    void signedDirectoryAddsUnsignedDeveloperEntry()
    {
        QVERIFY(snapshot(catalog()));
        const auto app = AppCatalog::find("org.example.Notes");
        QVERIFY(app.value("active").toBool());
        QVERIFY(app.value("publisher").toMap().isEmpty());
        QCOMPARE(app.value("repository").toString(), QString("Example/Notes"));
    }
    void malformedLocalizationAndCommands()
    {
        for (const auto& change : QVariantList{
                 QVariantMap{{"name", QVariantMap{{"zh-CN", "笔记"}}}},
                 QVariantMap{{"description", QVariantMap{{"en", 42}}}},
                 QVariantMap{{"name", QVariantMap{{"en", "bad\nname"}}}},
                 QVariantMap{{"command", "sh installer"}},
                 QVariantMap{{"publisher", "invalid"}}}) {
            auto value = catalog();
            auto entry = value.value("apps").toList().first().toMap();
            entry.insert(change.toMap());
            value["apps"] = QVariantList{entry};
            QVERIFY(!AppCatalog::validateUpdate(value, {}, "fixture").isEmpty());
        }
    }
    void withdrawalKeepsReceiptWithoutAuthorizingUpdate()
    {
        QVERIFY(snapshot(catalog()));
        const auto entry = AppCatalog::find("org.example.Notes");
        QVERIFY(AppCatalog::recordInstallation("org.example.Notes", {{"entry", entry}, {"sourceId", "fixture"}, {"commit", QString(64, 'a')}}));
        auto next = catalog(2); next["apps"] = QVariantList{};
        QVERIFY(snapshot(next));
        const auto withdrawn = AppCatalog::find("org.example.Notes");
        QVERIFY(!withdrawn.isEmpty());
        QVERIFY(!withdrawn.value("active").toBool());
        QCOMPARE(withdrawn.value("status").toString(), QString("withdrawn"));
    }
    void uninstallForgetsOwnershipButKeepsCatalogHistory()
    {
        QVERIFY(snapshot(catalog(2)));
        const auto path = AppCatalog::stateDirectory() + "/catalogs/fixture.json";
        QFile file(path); QVERIFY(file.open(QIODevice::ReadOnly));
        const auto history = file.readAll(); file.close();
        QVERIFY(!AppCatalog::receipt("org.example.Notes").isEmpty());
        QCOMPARE(AppCatalog::removeSource("fixture"), QString());
        QVERIFY(!AppCatalog::find("org.example.Notes").value("active").toBool());
        QVERIFY(!AppCatalog::forgetInstallation("../invalid"));
        QVERIFY(AppCatalog::forgetInstallation("org.example.Notes"));
        QVERIFY(AppCatalog::receipt("org.example.Notes").isEmpty());
        QVERIFY(AppCatalog::find("org.example.Notes").isEmpty());
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), history); file.close();
        QVERIFY(AppCatalog::forgetInstallation("org.example.Notes"));
        QCOMPARE(AppCatalog::addSource("fixture", "Example/catalog", fingerprint, root.filePath("public.gpg")), QString());
        QVERIFY(AppCatalog::find("org.example.Notes").value("active").toBool());
    }
    void tamperedCacheCannotAuthorizeInstall()
    {
        QVERIFY(snapshot(catalog(3)));
        const auto path = AppCatalog::stateDirectory() + "/catalogs/fixture.json";
        QFile file(path); QVERIFY(file.open(QIODevice::ReadOnly));
        auto envelope = QJsonDocument::fromJson(file.readAll()).object().toVariantMap(); file.close();
        auto changed = catalog(4); changed["sourceId"] = "attacker";
        envelope["catalog"] = QJsonDocument::fromVariant(changed).toJson().toBase64();
        QVERIFY(write(path, QJsonDocument::fromVariant(envelope).toJson()));
        QVERIFY(!AppCatalog::find("org.example.Notes").value("active").toBool());
    }
    void testModeSeparatesSourcesAndInvalidatesPlans()
    {
        QVERIFY(snapshot(catalog(5)));
        const auto normal = AppCatalog::find("org.example.Notes");
        const auto digest = AppCatalog::entryDigest(normal);
        QVERIFY(AppCatalog::writeState("preferences", {{"automaticUpdates", false}}));
        QVERIFY(AppCatalog::recordInstallation("org.example.Notes", {{"entry", normal}, {"sourceId", "fixture"}, {"commit", QString(64, 'a')}}));
        QCOMPARE(AppCatalog::setTestMode(true), QString());
        QVERIFY(AppCatalog::testMode());
        QVERIFY(AppCatalog::sources().isEmpty());
        QVERIFY(AppCatalog::readState("preferences").isEmpty());
        QVERIFY(!AppCatalog::receipt("org.example.Notes").isEmpty());
        QVERIFY(!AppCatalog::find("org.example.Notes").value("active").toBool());
        QCOMPARE(AppCatalog::addSource("fixture", "Example/test-catalog", fingerprint, root.filePath("public.gpg")), QString());
        QVERIFY(snapshot(catalog(1))); // Independent sequence history.
        auto test = AppCatalog::find("org.example.Notes");
        QVERIFY(test.value("active").toBool());
        QCOMPARE(test.value("appId"), normal.value("appId"));
        QVERIFY(test.value("testMode").toBool());
        const auto before = AppCatalog::entryDigest(test);
        QCOMPARE(AppCatalog::selectAppRelease("org.example.Notes", "Example/Notes", "v1.0.0-rc.1"), QString());
        test = AppCatalog::find("org.example.Notes");
        QCOMPARE(test.value("releaseTag").toString(), QString("v1.0.0-rc.1"));
        QVERIFY(AppCatalog::entryDigest(test) != before);
        QVERIFY(!AppCatalog::selectAppRelease("org.example.Notes", "Other/Notes", "v1.0.0").isEmpty());
        QVERIFY(!AppCatalog::selectAppRelease("org.example.Notes", "Example/Notes", "../evil").isEmpty());
        QVERIFY(AppCatalog::githubUrl(QUrl("https://api.github.com/repos/Example/Notes/releases/tags/v1.0.0-rc.1"), "Example/Notes", false));
        QVERIFY(!AppCatalog::githubUrl(QUrl("https://api.github.com/repos/Other/Notes/releases/tags/v1.0.0"), "Example/Notes", false));
        {
            QLockFile operation(AppCatalog::stateDirectory() + "/context.lock"); QVERIFY(operation.tryLock(0));
            QCOMPARE(AppCatalog::setTestMode(false), QString("BUSY"));
            QCOMPARE(AppCatalog::selectAppRelease("org.example.Notes", "Example/Notes", "v1.0.1"), QString("BUSY"));
        }
        QVERIFY(AppCatalog::recordInstallation("org.example.Notes", {{"entry", test}, {"sourceId", "fixture"}, {"commit", QString(64, 'b')}}));
        QCOMPARE(AppCatalog::setTestMode(false), QString());
        for (const auto& source : AppCatalog::sources())
            if (source.toMap().value("id").toString() == "fixture") QCOMPARE(source.toMap().value("sequence").toInt(), 5);
        QCOMPARE(AppCatalog::readState("preferences").value("automaticUpdates").toBool(), false);
        QVERIFY(AppCatalog::entryDigest(normal) != digest); // Even switching back invalidates old plans.
        QVERIFY(!AppCatalog::find("org.example.Notes").value("active").toBool()); // Test installation is not adopted.
        QVERIFY(!AppCatalog::receipt("org.example.Notes").isEmpty()); // No automatic uninstall.
        QVERIFY(!AppCatalog::githubUrl(QUrl("https://api.github.com/repos/Example/Notes/releases/tags/v1.0.0"), "Example/Notes", false));
        QVERIFY(!AppCatalog::selectAppRelease("org.example.Notes", "Example/Notes", "v1.0.0").isEmpty());
        QVERIFY(AppCatalog::forgetInstallation("org.example.Notes"));
        QVERIFY(AppCatalog::find("org.example.Notes").value("active").toBool());
        QCOMPARE(AppCatalog::setTestMode(true), QString());
        QCOMPARE(AppCatalog::sources().first().toMap().value("sequence").toInt(), 1);
        QCOMPARE(AppCatalog::selectSourceRelease("fixture", "Example/test-catalog", "catalog-2"), QString());
        QVERIFY(!AppCatalog::find("org.example.Notes").value("active").toBool()); // Await the selected signed directory.
        QCOMPARE(AppCatalog::setTestMode(false), QString());
    }
};
QTEST_GUILESS_MAIN(CatalogTest)
#include "catalog.moc"
