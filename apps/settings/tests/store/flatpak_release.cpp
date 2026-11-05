// Exercise internal validation without adding a caller-configurable trust or URL API.
#include "../../src/FlatpakRelease.cpp"
#include <QtTest>
#include "https_fixture.h"

class FlatpakReleaseTest : public QObject {
    Q_OBJECT
    const QString appId = QStringLiteral("org.nextks.calendar");
    QByteArray manifest(const QJsonObject &changes = {}) const
    {
        QJsonObject bundle{{"asset", "org.nextks.calendar-0.2.0-x86_64.flatpak"},
            {"ref", "app/org.nextks.calendar/x86_64/stable"},
            {"commit", QString(64, 'a')}, {"sha256", QString(64, 'b')}, {"size", 1234}};
        for (auto it = changes.begin(); it != changes.end(); ++it) bundle[it.key()] = it.value();
        return QJsonDocument(QJsonObject{{"schemaVersion", 1}, {"appId", appId},
            {"version", "0.2.0"}, {"revision", QString(40, 'c')},
            {"bundles", QJsonObject{{"x86_64", bundle}}}}).toJson();
    }
    void rejected(const QByteArray &bytes, const QString &expected, const QString &arch = "x86_64")
    {
        try {
            parseManifest(appId, arch, bytes);
            QFAIL("Malformed release was accepted");
        } catch (const Failure &failure) {
            QCOMPARE(failure.code, expected);
        }
    }
    QSslCertificate certificate;
    QSslKey privateKey;
    QSslConfiguration originalSsl;
private slots:
    void initTestCase()
    {
        originalSsl = QSslConfiguration::defaultConfiguration();
        QTemporaryDir keys(QDir::currentPath() + "/tmp/release-tls-XXXXXX");
        QVERIFY(keys.isValid());
        QProcess openssl;
        openssl.start("openssl", {"req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=api.github.com", "-addext", "subjectAltName=DNS:api.github.com,DNS:github.com",
            "-keyout", keys.filePath("key.pem"), "-out", keys.filePath("cert.pem")});
        QVERIFY(openssl.waitForFinished(10000));
        QCOMPARE(openssl.exitCode(), 0);
        QFile certFile(keys.filePath("cert.pem")), keyFile(keys.filePath("key.pem"));
        QVERIFY(certFile.open(QIODevice::ReadOnly));
        QVERIFY(keyFile.open(QIODevice::ReadOnly));
        certificate = QSslCertificate(certFile.readAll());
        privateKey = QSslKey(keyFile.readAll(), QSsl::Rsa);
        QVERIFY(!certificate.isNull());
        QVERIFY(!privateKey.isNull());
        auto ssl = originalSsl;
        ssl.setCaCertificates({certificate});
        QSslConfiguration::setDefaultConfiguration(ssl);
    }
    void cleanupTestCase() { QSslConfiguration::setDefaultConfiguration(originalSsl); }
    void networkResponses_data()
    {
        QTest::addColumn<int>("status");
        QTest::addColumn<QByteArray>("headers");
        QTest::addColumn<QString>("code");
        QTest::newRow("success") << 200 << QByteArray{} << QString{};
        QTest::newRow("missing") << 404 << QByteArray{} << QString("RELEASE_UNAVAILABLE");
        QTest::newRow("rate-limit") << 429 << QByteArray("Retry-After: 12\r\n") << QString("RATE_LIMITED");
        QTest::newRow("api-rate-limit") << 403 << QByteArray("X-RateLimit-Remaining: 0\r\n") << QString("RATE_LIMITED");
        QTest::newRow("forbidden") << 403 << QByteArray{} << QString("DOWNLOAD_FAILED");
        QTest::newRow("untrusted-redirect") << 302 << QByteArray("Location: https://example.com/asset\r\n") << QString("UNTRUSTED_URL");
    }
    void networkResponses()
    {
        QFETCH(int, status); QFETCH(QByteArray, headers); QFETCH(QString, code);
        ReleaseHttpsFixture server(certificate, privateKey);
        QVERIFY(server.isListening());
        server.responses = {{status, "fixture", headers}};
        Download download("kos-apps", [] { return false; }, [](const QString&, int) {}, 4000);
        QString actual;
        try { QCOMPARE(download.fetch(QUrl("https://api.github.com/repos/NextKde/kos-apps/releases/latest"), 64), QByteArray("fixture")); }
        catch (const Failure& failure) { actual = failure.code; }
        QCOMPARE(actual, code);
        QCOMPARE(server.requests, 1);
        QVERIFY(server.targets.first().startsWith("CONNECT api.github.com:443 "));
    }
    void invalidDiscovery_data()
    {
        QTest::addColumn<QByteArray>("response"); QTest::addColumn<QString>("code");
        QTest::newRow("malformed-json") << QByteArray("{broken") << QString("INVALID_RELEASE");
        QTest::newRow("draft") << QByteArray(R"({"tag_name":"v0.2.0","draft":true,"prerelease":false})") << QString("INVALID_RELEASE");
        QTest::newRow("prerelease") << QByteArray(R"({"tag_name":"v0.2.0","draft":false,"prerelease":true})") << QString("INVALID_RELEASE");
        QTest::newRow("missing-assets") << QByteArray(R"({"tag_name":"v0.2.0","draft":false,"prerelease":false,"assets":[]})") << QString("RELEASE_UNAVAILABLE");
    }
    void invalidDiscovery()
    {
        QFETCH(QByteArray, response); QFETCH(QString, code);
        ReleaseHttpsFixture server(certificate, privateKey);
        QVERIFY(server.isListening());
        server.responses = {{200, response, {}}};
        const auto result = FlatpakRelease::discover(appId, "x86_64", [] { return false; }, [](const QString&, int) {});
        QCOMPARE(result.value("code").toString(), code);
        QCOMPARE(server.requests, 1);
    }
    void transientFailuresRetry_data()
    {
        QTest::addColumn<bool>("disconnect");
        QTest::newRow("server-error") << false;
        QTest::newRow("connection-lost") << true;
    }
    void transientFailuresRetry()
    {
        QFETCH(bool, disconnect);
        ReleaseHttpsFixture server(certificate, privateKey);
        QVERIFY(server.isListening());
        server.responses = {{503, {}, {}, false, disconnect}, {200, "recovered", {}}};
        Download download("kos-apps", [] { return false; }, [](const QString&, int) {}, 5000);
        try { QCOMPARE(download.fetch(QUrl("https://api.github.com/repos/NextKde/kos-apps/releases/latest"), 64), QByteArray("recovered")); }
        catch (const Failure& failure) { QFAIL(qPrintable(failure.code + ": " + failure.message)); }
        QCOMPARE(server.requests, 2);
    }
    void cancellationAndBudget_data()
    {
        QTest::addColumn<bool>("cancel"); QTest::addColumn<bool>("backoff");
        QTest::newRow("cancel-transfer") << true << false;
        QTest::newRow("cancel-backoff") << true << true;
        QTest::newRow("timeout-transfer") << false << false;
        QTest::newRow("timeout-backoff") << false << true;
    }
    void cancellationAndBudget()
    {
        QFETCH(bool, cancel); QFETCH(bool, backoff);
        ReleaseHttpsFixture server(certificate, privateKey);
        QVERIFY(server.isListening());
        server.responses = {{backoff ? 503 : 200, {}, {}, !backoff}};
        QElapsedTimer elapsed; elapsed.start();
        Download download("kos-apps", [&] { return cancel && elapsed.elapsed() >= 300; },
            [](const QString&, int) {}, cancel ? 4000 : 350);
        try { download.fetch(QUrl("https://api.github.com/repos/NextKde/kos-apps/releases/latest"), 64); QFAIL("Unfinished download succeeded"); }
        catch (const Failure& failure) { QCOMPARE(failure.code, cancel ? QString("CANCELLED") : QString("NETWORK_TIMEOUT")); }
        QCOMPARE(server.requests, 1);
        QVERIFY(elapsed.elapsed() < 2500);
    }
    void retryExhaustion()
    {
        ReleaseHttpsFixture server(certificate, privateKey);
        QVERIFY(server.isListening());
        server.responses = {{503, {}, {}}};
        Download download("kos-apps", [] { return false; }, [](const QString&, int) {}, 10000);
        try { download.fetch(QUrl("https://api.github.com/repos/NextKde/kos-apps/releases/latest"), 64); QFAIL("Persistent server error succeeded"); }
        catch (const Failure& failure) { QCOMPARE(failure.code, QString("DOWNLOAD_FAILED")); }
        QCOMPARE(server.requests, 3);
    }
    void untrustedTlsIsNotRetried()
    {
        ReleaseHttpsFixture server(certificate, privateKey);
        QVERIFY(server.isListening());
        auto ssl = QSslConfiguration::defaultConfiguration();
        const auto trusted = ssl;
        ssl.setCaCertificates({});
        QSslConfiguration::setDefaultConfiguration(ssl);
        Download download("kos-apps", [] { return false; }, [](const QString&, int) {}, 4000);
        QString code;
        try { download.fetch(QUrl("https://api.github.com/repos/NextKde/kos-apps/releases/latest"), 64); }
        catch (const Failure& failure) { code = failure.code; }
        QSslConfiguration::setDefaultConfiguration(trusted);
        QCOMPARE(code, QString("DOWNLOAD_FAILED"));
        QCOMPARE(server.requests, 0);
        QCOMPARE(server.targets.size(), 1);
    }
    void signedLengthMismatchLeavesNoPartialFile()
    {
        ReleaseHttpsFixture server(certificate, privateKey);
        QVERIFY(server.isListening());
        server.responses = {{200, "short", {}}};
        QTemporaryDir temporary(QDir::currentPath() + "/tmp/release-short-XXXXXX");
        QVERIFY(temporary.isValid());
        Download download("kos-apps", [] { return false; }, [](const QString&, int) {}, 4000);
        try { download.fetch(QUrl("https://github.com/NextKde/kos-apps/releases/download/v0.2.0/app.flatpak"), 64, temporary.filePath("bundle.flatpak"), 12); QFAIL("Wrong signed length accepted"); }
        catch (const Failure& failure) { QCOMPARE(failure.code, QString("RESPONSE_TOO_LARGE")); }
        QVERIFY(QDir(temporary.path()).entryList(QDir::Files | QDir::Hidden | QDir::NoDotAndDotDot).isEmpty());
        QCOMPARE(server.requests, 1);
    }
    void oversizedDownloadLeavesNoPartialFile()
    {
        ReleaseHttpsFixture server(certificate, privateKey);
        QVERIFY(server.isListening());
        server.responses = {{200, "too-large", {}}};
        QTemporaryDir temporary(QDir::currentPath() + "/tmp/release-size-XXXXXX");
        QVERIFY(temporary.isValid());
        const auto path = temporary.filePath("bundle.flatpak");
        Download download("kos-apps", [] { return false; }, [](const QString&, int) {}, 4000);
        try { download.fetch(QUrl("https://github.com/NextKde/kos-apps/releases/download/v0.2.0/app.flatpak"), 4, path, 4); QFAIL("Oversized response accepted"); }
        catch (const Failure& failure) { QCOMPARE(failure.code, QString("RESPONSE_TOO_LARGE")); }
        QVERIFY(QDir(temporary.path()).entryList(QDir::Files | QDir::Hidden | QDir::NoDotAndDotDot).isEmpty());
        QCOMPARE(server.requests, 1);
    }
    void runtimePolicyDoesNotAuthorizeApplications()
    {
        QCOMPARE(FlatpakTrustPolicy::remotes.size(), std::size_t(1));
        const auto &remote = FlatpakTrustPolicy::remotes.front();
        QCOMPARE(QByteArray(remote.url), "https://dl.flathub.org/repo/");
        QCOMPARE(QByteArray(remote.primaryFingerprint), "6E5C05D979C76DAF93C081354184DD4D907A7CAE");
        QVERIFY(remote.runtimes);
        QVERIFY(!remote.applications);
    }
    void versionComparison()
    {
        bool valid = false;
        QCOMPARE(FlatpakRelease::compareVersions("0.2.0", "0.1.9", &valid), 1); QVERIFY(valid);
        QCOMPARE(FlatpakRelease::compareVersions("1.0.0", "1.0.0", &valid), 0); QVERIFY(valid);
        QCOMPARE(FlatpakRelease::compareVersions("1.0.0", "2.0.0", &valid), -1); QVERIFY(valid);
        for (const auto &version : {"01.2.0", "v0.2.0", "0.2", "0.2.0-beta", "-1.2.0", "18446744073709551616.0.0"}) {
            FlatpakRelease::compareVersions(version, "0.2.0", &valid); QVERIFY(!valid);
        }
    }
    void fixedRepositoryUrls()
    {
        QVERIFY(validUrl(QUrl("https://api.github.com/repos/NextKde/kos-apps/releases/latest"), "kos-apps", false));
        QVERIFY(validUrl(QUrl("https://github.com/NextKde/kos-apps/releases/download/v0.2.0/asset.flatpak"), "kos-apps", false));
        QVERIFY(validUrl(QUrl("https://release-assets.githubusercontent.com/asset?token=fixture"), "kos-apps", true));
        for (const auto &url : {
                 "http://github.com/NextKde/kos-apps/releases/download/v0.2.0/a",
                 "https://user@github.com/NextKde/kos-apps/releases/download/v0.2.0/a",
                 "https://github.com:444/NextKde/kos-apps/releases/download/v0.2.0/a",
                 "https://github.com/Other/kos-apps/releases/download/v0.2.0/a",
                 "https://github.com/NextKde/kos-calendar/releases/download/v0.2.0/a",
                 "https://github.com/NextKde/kos-apps-evil/releases/download/v0.2.0/a",
                 "https://127.0.0.1/asset", "https://example.com/asset"}) {
            QVERIFY2(!validUrl(QUrl(url), "kos-apps", true), url);
        }
        QVERIFY(!validUrl(QUrl("https://release-assets.githubusercontent.com/a"), "kos-apps", false));
        QVERIFY(!validUrl(QUrl("https://api.github.com/repos/NextKde/kos-apps/releases/latest?other=1"), "kos-apps", false));
    }
    void manifestIdentityAndArchitecture()
    {
        const auto result = parseManifest(appId, "x86_64", manifest());
        QCOMPARE(result["version"].toString(), "0.2.0");
        QCOMPARE(result["branch"].toString(), "stable");
        rejected(manifest(), "ARCH_UNAVAILABLE", "aarch64");
        rejected("{broken", "INVALID_RELEASE");
        for (const auto &field : {"appId", "version", "revision", "schemaVersion"}) {
            auto object = QJsonDocument::fromJson(manifest()).object(); object[field] = "wrong";
            rejected(QJsonDocument(object).toJson(), "INVALID_RELEASE");
        }
        for (const auto &id : {"org.nextks.calculator", "org.nextks.weather", "org.nextkde.ListenFree"}) {
            auto object = QJsonDocument::fromJson(manifest()).object(); object["appId"] = id;
            auto bundles = object["bundles"].toObject(); auto bundle = bundles["x86_64"].toObject();
            bundle["ref"] = QString("app/%1/x86_64/stable").arg(id); bundles["x86_64"] = bundle;
            object["bundles"] = bundles;
            QCOMPARE(parseManifest(id, "x86_64", QJsonDocument(object).toJson())["version"].toString(), "0.2.0");
        }
    }
    void invalidBundle_data()
    {
        QTest::addColumn<QString>("field"); QTest::addColumn<QJsonValue>("value");
        QTest::newRow("other-app") << QString("ref") << QJsonValue("app/org.nextks.weather/x86_64/stable");
        QTest::newRow("other-arch") << QString("ref") << QJsonValue("app/org.nextks.calendar/aarch64/stable");
        QTest::newRow("other-branch") << QString("ref") << QJsonValue("app/org.nextks.calendar/x86_64/beta");
        QTest::newRow("short-commit") << QString("commit") << QJsonValue("abc");
        QTest::newRow("bad-hash") << QString("sha256") << QJsonValue(QString(64, 'x'));
        QTest::newRow("traversal") << QString("asset") << QJsonValue("../other.flatpak");
        QTest::newRow("zero-size") << QString("size") << QJsonValue(0);
        QTest::newRow("fractional-size") << QString("size") << QJsonValue(1.5);
        QTest::newRow("oversize") << QString("size") << QJsonValue(3.0 * 1024 * 1024 * 1024);
        QTest::newRow("string-size") << QString("size") << QJsonValue("1234");
    }
    void invalidBundle()
    {
        QFETCH(QString, field); QFETCH(QJsonValue, value);
        rejected(manifest({{field, value}}), "INVALID_RELEASE");
    }
    void genuinePublisherSignatureAndTampering()
    {
        // Public, offline specimen from the retained 03c92ed SDK candidate;
        // this is verification evidence, not a published release or trust source.
        const QByteArray bytes = R"({
  "schemaVersion": 1,
  "appId": "org.nextks.calculator",
  "version": "0.2.0",
  "revision": "03c92edd0b0c9f54013ba8c63ee1e591482eb928",
  "bundles": {
    "x86_64": {
      "ref": "app/org.nextks.calculator/x86_64/stable",
      "commit": "67629e9097b2c0b85634452f76c88660d4741415336d267e2982968dc2dc545c",
      "asset": "org.nextks.calculator-0.2.0-x86_64.flatpak",
      "size": 661776,
      "sha256": "3d393bd0200abdc9351fffa04b140c973dd8e4051e2766f39afebcc247882636"
    }
  }
}
)";
        const auto signature = QByteArray::fromBase64(
            "iQGzBAABCAAdFiEEXuP4f+gD/NFHuzTBTu3EiF6MqhMFAmrr3jAACgkQTu3EiF6MqhMcUAv/YZimoPi6f4NacoJf8sJabXFfHthKqvr0oz4dc/XAN0/QHjBg31H+GC0T3qMtWxMLPkJ2aP0S9rPPQpQu/H2cAEtCSm//ep7QI7RZBo5dW/DhJ2aLwT+11CAfwQEJSwCh6JDm3JTyLae5G2x4A3tLdnMK4VW2mYXCf2Zdhmk9H2FrgTN02L2UaDXk7RMa7pF+MXpcAS7uix8sgpg1dp7GyMiXtqdBjsbQQgG8DMflt/0BbEUG4Hlm3KlfuQ0ADKJc9GG3Pax8c5Mh88moxkxOY+jnw8qzXfIhC2K5tBIWTMJ6edC7iQbe5Pk3qKIg14I06febwCek/dA341S4/X0ldvU048cp4v0SsCBsrFM+KADTW0xxeuUi8A2Bnyvcy7olT9vGY8Pc+VoZjPwxLl9jBpfqQG1VPrtJGNWgoXMN3IJF8x+Dfris/zzX7LgC07IC+2ohIJNnCOZEhhS5Fg94SrZWWXpTjYtnYKF6p9qObQo4i4rEq3OrW4JV9Oxv6oCQ");
        QVERIFY(verify("org.nextks.calculator", bytes, signature, [] { return false; }));
        QCOMPARE(parseManifest("org.nextks.calculator", "x86_64", bytes)["version"].toString(), "0.2.0");
        auto altered = bytes;
        altered.replace("0.2.0", "0.2.1");
        QVERIFY(!verify("org.nextks.calculator", altered, signature, [] { return false; }));
        auto broken = signature;
        broken[broken.size() / 2] = char(broken.at(broken.size() / 2) ^ 1);
        QVERIFY(!verify("org.nextks.calculator", bytes, broken, [] { return false; }));
        QVERIFY(!verify("unknown", bytes, signature, [] { return false; }));

        ReleaseHttpsFixture server(certificate, privateKey);
        QVERIFY(server.isListening());
        const auto metadata = QString("org.nextks.calculator.flatpak-release.json");
        QJsonArray assets;
        for (const auto& name : {metadata, metadata + ".sig", QString("org.nextks.calculator-0.2.0-x86_64.flatpak")})
            assets.append(QJsonObject{{"name", name}, {"browser_download_url",
                "https://github.com/NextKde/kos-apps/releases/download/v0.2.0/" + name}});
        const auto release = QJsonDocument(QJsonObject{{"tag_name", "v0.2.0"}, {"draft", false},
            {"prerelease", false}, {"assets", assets}}).toJson();
        // The retained public specimen is genuine, but is not a published Latest.
        server.responses = {{200, release, {}}, {200, bytes, {}}, {200, signature, {}},
            {200, QByteArray(661776, 'x'), {}}};
        const auto discovery = FlatpakRelease::discover("org.nextks.calculator", "x86_64",
            [] { return false; }, [](const QString&, int) {});
        QVERIFY2(!discovery.contains("code"), qPrintable(discovery.value("message").toString()));
        QCOMPARE(discovery.value("commit").toString(), QString("67629e9097b2c0b85634452f76c88660d4741415336d267e2982968dc2dc545c"));
        QCOMPARE(server.requests, 3);
        QTemporaryDir temporary(QDir::currentPath() + "/tmp/release-digest-XXXXXX");
        QVERIFY(temporary.isValid());
        const auto downloaded = FlatpakRelease::download("org.nextks.calculator", discovery, temporary.path(),
            [] { return false; }, [](const QString&, int) {});
        QCOMPARE(downloaded.value("code").toString(), QString("INTEGRITY_FAILED"));
        QCOMPARE(server.requests, 4);
    }
    void invalidSignatureCannotReachDownload()
    {
        QVERIFY(!verify(appId, manifest(), {}, [] { return false; }));
        QVERIFY(!verify("unknown", manifest(), "fake", [] { return false; }));
        const auto result = FlatpakRelease::download(appId, {{"manifest", manifest().toBase64()},
            {"signature", QByteArray("fake").toBase64()}, {"arch", "x86_64"}},
            QDir::currentPath() + "/tmp", [] { return false; }, [](const QString &, int) {});
        QCOMPARE(result["code"].toString(), "FLATPAK_UNTRUSTED");
    }
    void cancellationStopsBeforeNetwork()
    {
        const auto result = FlatpakRelease::discover(appId, "x86_64", [] { return true; }, [](const QString &, int) {});
        QCOMPARE(result["code"].toString(), "CANCELLED");
    }
};

int main(int argc, char **argv)
{
    QDir().mkpath("tmp");
    QTemporaryDir fixture(QDir::currentPath() + "/tmp/flatpak-release-XXXXXX");
    if (!fixture.isValid()) return 1;
    qputenv("HOME", fixture.path().toUtf8());
    qputenv("XDG_CACHE_HOME", (fixture.path() + "/cache").toUtf8());
    QCoreApplication application(argc, argv);
    FlatpakReleaseTest test;
    return QTest::qExec(&test, argc, argv);
}
#include "flatpak_release.moc"
