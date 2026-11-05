// Exercise internal validation without adding a caller-configurable trust or URL API.
#include "../../src/FlatpakRelease.cpp"
#include <QtTest>

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
private slots:
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
