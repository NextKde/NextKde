#include "AppCatalog.h"
#include "WidgetPackages.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QtTest>

class WidgetStoreTest : public QObject {
    Q_OBJECT
    QTemporaryDir root;

    bool writeFile(const QString& path, const QByteArray& bytes)
    {
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile file(path);
        return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
    }

    QByteArray readFile(const QString& path)
    {
        QFile file(path);
        return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
    }

    bool createValidWidgetSource(const QString& dirPath, const QString& id, const QString& version, int sdkVersion = 1)
    {
        const QByteArray metadata = QJsonDocument(QJsonObject{
            {"id", id},
            {"name", "Demo Widget"},
            {"version", version},
            {"sdkVersion", sdkVersion},
            {"style", "material"},
            {"sizes", QJsonArray{QJsonArray{2, 2}}},
            {"defaultSize", QJsonArray{2, 2}}
        }).toJson();
        const QByteArray qml = "import QtQuick\nItem { property var snapshot: null; required property var widgetSize; required property var appearance }\n";
        const QByteArray snap = "import QtQuick\nItem { function getSnapshot(size) { return ({ ok: true }) } }\n";
        return writeFile(dirPath + "/metadata.json", metadata)
            && writeFile(dirPath + "/Widget.qml", qml)
            && writeFile(dirPath + "/Snapshot.qml", snap);
    }

    QByteArray packTarGz(const QString& parentDir, const QString& folderName, const QString& outFile)
    {
        QProcess proc;
        proc.setProgram(QStandardPaths::findExecutable("tar"));
        proc.setArguments({"-czf", outFile, "-C", parentDir, folderName});
        proc.start();
        if (!proc.waitForFinished(10000) || proc.exitCode() != 0)
            return {};
        return readFile(outFile);
    }

    QByteArray packZip(const QString& parentDir, const QString& folderName, const QString& outFile)
    {
        const QString bsdTar = QStandardPaths::findExecutable("bsdtar");
        QProcess proc;
        if (!bsdTar.isEmpty()) {
            proc.setProgram(bsdTar);
            proc.setArguments({"--format", "zip", "-cf", outFile, "-C", parentDir, folderName});
        } else {
            proc.setWorkingDirectory(parentDir);
            proc.setProgram(QStandardPaths::findExecutable("zip"));
            proc.setArguments({"-rq", outFile, folderName});
        }
        proc.start();
        if (!proc.waitForFinished(10000) || proc.exitCode() != 0)
            return {};
        return readFile(outFile);
    }

private slots:
    void initTestCase()
    {
        QVERIFY(root.isValid());
        qputenv("HOME", root.filePath("home").toUtf8());
        qputenv("XDG_DATA_HOME", root.filePath("data").toUtf8());
        qputenv("XDG_STATE_HOME", root.filePath("state").toUtf8());
        qputenv("XDG_CONFIG_HOME", root.filePath("config").toUtf8());
    }

    void semverComparison()
    {
        QCOMPARE(WidgetPackages::compareSemver("1.0.0", "1.0.0"), 0);
        QCOMPARE(WidgetPackages::compareSemver("1.0.0-rc.1", "1.0.0"), -1);
        QCOMPARE(WidgetPackages::compareSemver("1.0.0-alpha.2", "1.0.0-alpha.10"), -1);
        QCOMPARE(WidgetPackages::compareSemver("1.1.0", "1.0.9"), 1);
        QCOMPARE(WidgetPackages::compareSemver("2.0.0", "1.99.99"), 1);
    }

    void deployUpdateAndRemoveTarGzAndZip()
    {
        QTemporaryDir src;
        QVERIFY(src.isValid());
        QVERIFY(createValidWidgetSource(src.filePath("v1/demo"), "org.example.DemoWidget", "1.0.0"));
        const QByteArray tarBytes = packTarGz(src.filePath("v1"), "demo", src.filePath("demo-1.0.0.tar.gz"));
        QVERIFY(!tarBytes.isEmpty());
        const QString tarSha = QString::fromLatin1(QCryptographicHash::hash(tarBytes, QCryptographicHash::Sha256).toHex());

        const QString installRoot = WidgetPackages::widgetInstallRoot();
        const auto r1 = WidgetPackages::deployVerifiedArchive(
            "org.example.DemoWidget", "1.0.0", "demo-1.0.0.tar.gz",
            tarSha, tarBytes.size(), tarBytes, installRoot, false, "", false);
        QCOMPARE(r1.code, QString());
        QCOMPARE(r1.installedVersion, QString("1.0.0"));
        QVERIFY(QFileInfo::exists(installRoot + "/org.example.DemoWidget/metadata.json"));

        // Upgrade via .zip/.koswidget archive.
        QVERIFY(createValidWidgetSource(src.filePath("v2/demo"), "org.example.DemoWidget", "1.1.0"));
        const QByteArray zipBytes = packZip(src.filePath("v2"), "demo", src.filePath("demo-1.1.0.koswidget"));
        QVERIFY(!zipBytes.isEmpty());
        const QString zipSha = QString::fromLatin1(QCryptographicHash::hash(zipBytes, QCryptographicHash::Sha256).toHex());

        const auto r2 = WidgetPackages::deployVerifiedArchive(
            "org.example.DemoWidget", "1.1.0", "demo-1.1.0.koswidget",
            zipSha, zipBytes.size(), zipBytes, installRoot, true, "1.0.0", false);
        QCOMPARE(r2.code, QString());
        QCOMPARE(r2.installedVersion, QString("1.1.0"));

        // Reject downgrade outside test mode.
        const auto downgrade = WidgetPackages::deployVerifiedArchive(
            "org.example.DemoWidget", "1.0.0", "demo-1.0.0.tar.gz",
            tarSha, tarBytes.size(), tarBytes, installRoot, true, "1.1.0", false);
        QCOMPARE(downgrade.code, QString("VERSION_CONFLICT"));

        // Allow downgrade when explicitly permitted (test mode).
        const auto testDowngrade = WidgetPackages::deployVerifiedArchive(
            "org.example.DemoWidget", "1.0.0", "demo-1.0.0.tar.gz",
            tarSha, tarBytes.size(), tarBytes, installRoot, true, "1.1.0", true);
        QCOMPARE(testDowngrade.code, QString());

        // Uninstall cleanly removes managed directory.
        const auto removed = WidgetPackages::removeManagedPackage("org.example.DemoWidget", installRoot);
        QCOMPARE(removed.code, QString());
        QVERIFY(!QFileInfo::exists(installRoot + "/org.example.DemoWidget"));
    }

    void rejectsCorruptIncompatibleSymlinkAndExternalPackages()
    {
        QTemporaryDir src;
        QVERIFY(src.isValid());
        const QString installRoot = WidgetPackages::widgetInstallRoot();

        // 1. Wrong SHA-256 -> INTEGRITY_FAILED
        QVERIFY(createValidWidgetSource(src.filePath("ok/pkg"), "org.example.SafeWidget", "1.0.0"));
        const QByteArray okBytes = packTarGz(src.filePath("ok"), "pkg", src.filePath("ok.tar.gz"));
        QVERIFY(!okBytes.isEmpty());
        const auto badHash = WidgetPackages::deployVerifiedArchive(
            "org.example.SafeWidget", "1.0.0", "ok.tar.gz",
            QString(64, '0'), okBytes.size(), okBytes, installRoot, false, "", false);
        QCOMPARE(badHash.code, QString("INTEGRITY_FAILED"));
        QVERIFY(!QFileInfo::exists(installRoot + "/org.example.SafeWidget"));

        // 2. Incompatible sdkVersion -> INVALID_PACKAGE caught by WidgetPackageIndex
        QVERIFY(createValidWidgetSource(src.filePath("bad-sdk/pkg"), "org.example.SafeWidget", "1.0.0", 99));
        const QByteArray badSdkBytes = packTarGz(src.filePath("bad-sdk"), "pkg", src.filePath("bad-sdk.tar.gz"));
        QVERIFY(!badSdkBytes.isEmpty());
        const QString badSdkSha = QString::fromLatin1(QCryptographicHash::hash(badSdkBytes, QCryptographicHash::Sha256).toHex());
        const auto badSdk = WidgetPackages::deployVerifiedArchive(
            "org.example.SafeWidget", "1.0.0", "bad-sdk.tar.gz",
            badSdkSha, badSdkBytes.size(), badSdkBytes, installRoot, false, "", false);
        QCOMPARE(badSdk.code, QString("INVALID_PACKAGE"));
        QVERIFY(badSdk.message.contains("sdkVersion"));

        // 3. Symlink inside archive -> INVALID_PACKAGE
        QVERIFY(createValidWidgetSource(src.filePath("sym/pkg"), "org.example.SafeWidget", "1.0.0"));
        QVERIFY(QFile::link("/etc/passwd", src.filePath("sym/pkg/leak.txt")));
        const QByteArray symBytes = packTarGz(src.filePath("sym"), "pkg", src.filePath("sym.tar.gz"));
        QVERIFY(!symBytes.isEmpty());
        const QString symSha = QString::fromLatin1(QCryptographicHash::hash(symBytes, QCryptographicHash::Sha256).toHex());
        const auto symRes = WidgetPackages::deployVerifiedArchive(
            "org.example.SafeWidget", "1.0.0", "sym.tar.gz",
            symSha, symBytes.size(), symBytes, installRoot, false, "", false);
        QCOMPARE(symRes.code, QString("INVALID_PACKAGE"));

        // 4. Symlinked external install cannot be removed by removeManagedPackage
        QDir().mkpath(installRoot);
        QVERIFY(QFile::link(src.filePath("ok/pkg"), installRoot + "/org.example.ExternalLink"));
        const auto extRemove = WidgetPackages::removeManagedPackage("org.example.ExternalLink", installRoot);
        QCOMPARE(extRemove.code, QString("NOT_MANAGED"));
        QVERIFY(QFileInfo(installRoot + "/org.example.ExternalLink").isSymLink());
    }
};

QTEST_GUILESS_MAIN(WidgetStoreTest)
#include "widget_store.moc"
