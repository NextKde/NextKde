#include "WidgetPackageIndex.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

namespace {

bool writeTextFile(const QString &path, const QByteArray &content)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    return file.write(content) == content.size();
}

bool createValidPackageDir(const QString &pkgDir, const QString &id, const QByteArray &extraMetadata = {})
{
    const QByteArray metadata = extraMetadata.isEmpty()
        ? QByteArray("{\n"
                     "  \"id\": \"" + id.toUtf8() + "\",\n"
                     "  \"name\": \"Test Widget\",\n"
                     "  \"version\": \"0.1.0\",\n"
                     "  \"sdkVersion\": 1,\n"
                     "  \"style\": \"macos\",\n"
                     "  \"sizes\": [[2, 2], [3, 2]],\n"
                     "  \"defaultSize\": [2, 2]\n"
                     "}\n")
        : extraMetadata;
    return writeTextFile(pkgDir + "/metadata.json", metadata)
        && writeTextFile(pkgDir + "/Widget.qml", "import QtQuick\nItem {}\n")
        && writeTextFile(pkgDir + "/Snapshot.qml", "import QtQuick\nQtObject { function getSnapshot(s) { return {} } }\n");
}

QJsonObject findInvalid(const QJsonArray &invalid, const QString &id)
{
    for (const QJsonValue &val : invalid) {
        const QJsonObject obj = val.toObject();
        if (obj.value(QStringLiteral("id")).toString() == id)
            return obj;
    }
    return {};
}

}

class WidgetPackageIndexTest : public QObject
{
    Q_OBJECT

private slots:
    void discoversValidPackageWithRevisionAndSettings()
    {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());

        const QString dataRoot = temp.filePath(QStringLiteral("data"));
        const QString pkgDir = dataRoot + QStringLiteral("/kos/widgets/org.example.valid.clock");
        QVERIFY(createValidPackageDir(pkgDir, QStringLiteral("org.example.valid.clock")));
        QVERIFY(writeTextFile(pkgDir + QStringLiteral("/Settings.qml"), "import QtQuick\nItem {}\n"));

        const QJsonObject snap = KosPlatform::WidgetPackageIndex::snapshotForRoots({dataRoot});
        QCOMPARE(snap.value(QStringLiteral("sdkVersion")).toInt(), 1);
        const QJsonArray packages = snap.value(QStringLiteral("packages")).toArray();
        QCOMPARE(packages.size(), 1);
        QCOMPARE(snap.value(QStringLiteral("invalidPackages")).toArray().size(), 0);

        const QJsonObject pkg = packages.at(0).toObject();
        QCOMPARE(pkg.value(QStringLiteral("id")).toString(), QStringLiteral("org.example.valid.clock"));
        QCOMPARE(pkg.value(QStringLiteral("hasSettings")).toBool(), true);
        QCOMPARE(pkg.value(QStringLiteral("containers")).toArray(), QJsonArray{QStringLiteral("desktop")});
        QCOMPARE(pkg.value(QStringLiteral("dockUnits")).toInt(), 4);
        QVERIFY(!pkg.value(QStringLiteral("revision")).toString().isEmpty());
        QVERIFY(pkg.value(QStringLiteral("widgetEntry")).toString().endsWith(QStringLiteral("/Widget.qml")));
        QVERIFY(pkg.value(QStringLiteral("settingsEntry")).toString().endsWith(QStringLiteral("/Settings.qml")));
    }

    void supportsSymlinkedPackageRootAndResolvesCanonicalPaths()
    {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());

        const QString devDir = temp.filePath(QStringLiteral("dev/my-clock"));
        QVERIFY(createValidPackageDir(devDir, QStringLiteral("org.example.symlink.clock")));

        const QString dataRoot = temp.filePath(QStringLiteral("data"));
        const QString widgetsDir = dataRoot + QStringLiteral("/kos/widgets");
        QVERIFY(QDir().mkpath(widgetsDir));
        const QString linkPath = widgetsDir + QStringLiteral("/org.example.symlink.clock");
        QVERIFY(QFile::link(devDir, linkPath));

        const QJsonObject snap = KosPlatform::WidgetPackageIndex::snapshotForRoots({dataRoot});
        const QJsonArray packages = snap.value(QStringLiteral("packages")).toArray();
        QCOMPARE(packages.size(), 1);
        QCOMPARE(snap.value(QStringLiteral("invalidPackages")).toArray().size(), 0);

        const QJsonObject pkg = packages.at(0).toObject();
        const QString canonicalDevDir = QFileInfo(devDir).canonicalFilePath();
        QCOMPARE(pkg.value(QStringLiteral("rootPath")).toString(), canonicalDevDir);
        QCOMPARE(pkg.value(QStringLiteral("widgetEntry")).toString(), canonicalDevDir + QStringLiteral("/Widget.qml"));
    }

    void rejectsEscapingEntrySymlinkWithDiagnostic()
    {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());

        const QString outsideFile = temp.filePath(QStringLiteral("outside.qml"));
        QVERIFY(writeTextFile(outsideFile, "import QtQuick\nItem {}\n"));

        const QString dataRoot = temp.filePath(QStringLiteral("data"));
        const QString pkgDir = dataRoot + QStringLiteral("/kos/widgets/org.example.escape");
        QVERIFY(writeTextFile(pkgDir + QStringLiteral("/metadata.json"),
            "{\n"
            "  \"id\": \"org.example.escape\",\n"
            "  \"name\": \"Escape\",\n"
            "  \"version\": \"0.1.0\",\n"
            "  \"sdkVersion\": 1,\n"
            "  \"style\": \"material\",\n"
            "  \"sizes\": [[2, 2]],\n"
            "  \"defaultSize\": [2, 2]\n"
            "}\n"));
        QVERIFY(writeTextFile(pkgDir + QStringLiteral("/Snapshot.qml"),
            "import QtQuick\nQtObject { function getSnapshot(s) { return {} } }\n"));
        QVERIFY(QFile::link(outsideFile, pkgDir + QStringLiteral("/Widget.qml")));

        const QJsonObject snap = KosPlatform::WidgetPackageIndex::snapshotForRoots({dataRoot});
        QCOMPARE(snap.value(QStringLiteral("packages")).toArray().size(), 0);
        const QJsonArray invalid = snap.value(QStringLiteral("invalidPackages")).toArray();
        QCOMPARE(invalid.size(), 1);
        const QJsonObject err = findInvalid(invalid, QStringLiteral("org.example.escape"));
        QCOMPARE(err.value(QStringLiteral("code")).toString(), QStringLiteral("missing-entry"));
        QVERIFY(!err.value(QStringLiteral("reason")).toString().isEmpty());
        QVERIFY(err.value(QStringLiteral("reason")).toString().contains(QStringLiteral("Widget.qml")));
    }

    void reportsSpecificInvalidMetadataReasons()
    {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());

        const QString dataRoot = temp.filePath(QStringLiteral("data"));
        const QString widgetsRoot = dataRoot + QStringLiteral("/kos/widgets/");

        // 1. Missing style
        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.nostyle"),
            QStringLiteral("org.example.nostyle"),
            "{\"id\":\"org.example.nostyle\",\"name\":\"NoStyle\",\"version\":\"1.0\",\"sdkVersion\":1,\"sizes\":[[2,2]],\"defaultSize\":[2,2]}"));

        // 2. ID mismatch
        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.mismatch"),
            QStringLiteral("org.example.other")));

        // 3. defaultSize not in sizes
        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.baddefault"),
            QStringLiteral("org.example.baddefault"),
            "{\"id\":\"org.example.baddefault\",\"name\":\"BadDef\",\"version\":\"1.0\",\"sdkVersion\":1,\"style\":\"macos\",\"sizes\":[[2,2]],\"defaultSize\":[3,2]}"));

        // 4. Malformed JSON
        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.badjson"),
            QStringLiteral("org.example.badjson"),
            "{ \"id\": \"org.example.badjson\", }"));

        // 5. Newer sdkVersion than supported
        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.oldsdk"),
            QStringLiteral("org.example.oldsdk"),
            "{\"id\":\"org.example.oldsdk\",\"name\":\"OldSdk\",\"version\":\"1.0\",\"sdkVersion\":2,\"style\":\"macos\",\"sizes\":[[2,2]],\"defaultSize\":[2,2]}"));

        // 6. Non-object i18n
        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.badi18n"),
            QStringLiteral("org.example.badi18n"),
            "{\"id\":\"org.example.badi18n\",\"name\":\"BadI18n\",\"version\":\"1.0\",\"sdkVersion\":1,\"style\":\"macos\",\"sizes\":[[2,2]],\"defaultSize\":[2,2],\"i18n\":[]}"));

        const QJsonObject snap = KosPlatform::WidgetPackageIndex::snapshotForRoots({dataRoot});
        QCOMPARE(snap.value(QStringLiteral("packages")).toArray().size(), 0);
        const QJsonArray invalid = snap.value(QStringLiteral("invalidPackages")).toArray();
        QCOMPARE(invalid.size(), 6);

        QCOMPARE(findInvalid(invalid, QStringLiteral("org.example.badi18n")).value(QStringLiteral("code")).toString(), QStringLiteral("invalid-metadata"));
        QVERIFY(findInvalid(invalid, QStringLiteral("org.example.badi18n")).value(QStringLiteral("reason")).toString().contains(QStringLiteral("i18n")));

        QCOMPARE(findInvalid(invalid, QStringLiteral("org.example.nostyle")).value(QStringLiteral("code")).toString(), QStringLiteral("invalid-metadata"));
        QVERIFY(findInvalid(invalid, QStringLiteral("org.example.nostyle")).value(QStringLiteral("reason")).toString().contains(QStringLiteral("style")));
        QCOMPARE(findInvalid(invalid, QStringLiteral("org.example.mismatch")).value(QStringLiteral("code")).toString(), QStringLiteral("invalid-metadata"));
        QVERIFY(findInvalid(invalid, QStringLiteral("org.example.mismatch")).value(QStringLiteral("reason")).toString().contains(QStringLiteral("directory name")));
        QCOMPARE(findInvalid(invalid, QStringLiteral("org.example.baddefault")).value(QStringLiteral("code")).toString(), QStringLiteral("invalid-metadata"));
        QVERIFY(findInvalid(invalid, QStringLiteral("org.example.baddefault")).value(QStringLiteral("reason")).toString().contains(QStringLiteral("defaultSize")));
        QCOMPARE(findInvalid(invalid, QStringLiteral("org.example.badjson")).value(QStringLiteral("code")).toString(), QStringLiteral("invalid-json"));
        QVERIFY(findInvalid(invalid, QStringLiteral("org.example.badjson")).value(QStringLiteral("reason")).toString().contains(QStringLiteral("Invalid metadata.json")));
        QCOMPARE(findInvalid(invalid, QStringLiteral("org.example.oldsdk")).value(QStringLiteral("code")).toString(), QStringLiteral("sdk-too-new"));
        QVERIFY(findInvalid(invalid, QStringLiteral("org.example.oldsdk")).value(QStringLiteral("reason")).toString().contains(QStringLiteral("sdkVersion")));
    }

    void enforcesSdkVersionRangeAndMinApiRevision()
    {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());

        const QString dataRoot = temp.filePath(QStringLiteral("data"));
        const QString widgetsRoot = dataRoot + QStringLiteral("/kos/widgets/");

        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.v1.plain"),
            QStringLiteral("org.example.v1.plain")));

        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.v1.needsapi2"),
            QStringLiteral("org.example.v1.needsapi2"),
            "{\"id\":\"org.example.v1.needsapi2\",\"name\":\"NeedsApi2\",\"version\":\"1.0\",\"sdkVersion\":1,\"minApiRevision\":2,\"style\":\"macos\",\"sizes\":[[2,2]],\"defaultSize\":[2,2]}"));

        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.bad.apirev"),
            QStringLiteral("org.example.bad.apirev"),
            "{\"id\":\"org.example.bad.apirev\",\"name\":\"BadApi\",\"version\":\"1.0\",\"sdkVersion\":1,\"minApiRevision\":0,\"style\":\"macos\",\"sizes\":[[2,2]],\"defaultSize\":[2,2]}"));

        // Under [1, 1] and apiRevision 1: v1.plain succeeds; needsapi2 -> api-too-old; bad.apirev -> invalid-metadata.
        const QJsonObject snap1 = KosPlatform::WidgetPackageIndex::snapshotForRoots({dataRoot}, 1, 1, 1);
        QCOMPARE(snap1.value(QStringLiteral("minSdkVersion")).toInt(), 1);
        QCOMPARE(snap1.value(QStringLiteral("maxSdkVersion")).toInt(), 1);
        QCOMPARE(snap1.value(QStringLiteral("apiRevision")).toInt(), 1);
        QCOMPARE(snap1.value(QStringLiteral("packages")).toArray().size(), 1);
        QCOMPARE(snap1.value(QStringLiteral("packages")).toArray().at(0).toObject().value(QStringLiteral("minApiRevision")).toInt(), 1);
        const QJsonArray inv1 = snap1.value(QStringLiteral("invalidPackages")).toArray();
        QCOMPARE(inv1.size(), 2);
        QCOMPARE(findInvalid(inv1, QStringLiteral("org.example.v1.needsapi2")).value(QStringLiteral("code")).toString(), QStringLiteral("api-too-old"));
        QCOMPARE(findInvalid(inv1, QStringLiteral("org.example.bad.apirev")).value(QStringLiteral("code")).toString(), QStringLiteral("invalid-metadata"));

        // Transition window [1, 2] and apiRevision 2: both v1.plain and needsapi2 succeed.
        const QJsonObject snap2 = KosPlatform::WidgetPackageIndex::snapshotForRoots({dataRoot}, 1, 2, 2);
        QCOMPARE(snap2.value(QStringLiteral("packages")).toArray().size(), 2);

        // Drop sdkVersion 1 ([2, 2]): v1.plain and needsapi2 are both rejected as sdk-too-old.
        const QJsonObject snap3 = KosPlatform::WidgetPackageIndex::snapshotForRoots({dataRoot}, 2, 2, 2);
        QCOMPARE(snap3.value(QStringLiteral("packages")).toArray().size(), 0);
        const QJsonArray inv3 = snap3.value(QStringLiteral("invalidPackages")).toArray();
        QCOMPARE(findInvalid(inv3, QStringLiteral("org.example.v1.plain")).value(QStringLiteral("code")).toString(), QStringLiteral("sdk-too-old"));
        QCOMPARE(findInvalid(inv3, QStringLiteral("org.example.v1.needsapi2")).value(QStringLiteral("code")).toString(), QStringLiteral("sdk-too-old"));
    }

    void watcherEmitsOnPackageAddAndInPlaceEdit()
    {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());

        const QString dataRoot = temp.filePath(QStringLiteral("data"));
        QVERIFY(QDir().mkpath(dataRoot));

        KosPlatform::WidgetPackageIndex::WidgetPackageWatcher watcher({dataRoot});
        QSignalSpy spy(&watcher, &KosPlatform::WidgetPackageIndex::WidgetPackageWatcher::snapshotChanged);

        const QString devDir = temp.filePath(QStringLiteral("dev/live-widget"));
        QVERIFY(createValidPackageDir(devDir, QStringLiteral("org.example.live.clock")));

        const QString widgetsDir = dataRoot + QStringLiteral("/kos/widgets");
        QVERIFY(QDir().mkpath(widgetsDir));
        QVERIFY(QFile::link(devDir, widgetsDir + QStringLiteral("/org.example.live.clock")));

        QTRY_COMPARE_WITH_TIMEOUT(spy.count(), 1, 2000);
        const QJsonObject firstSnap = spy.takeFirst().at(0).toJsonObject();
        const QJsonArray firstPkgs = firstSnap.value(QStringLiteral("packages")).toArray();
        QCOMPARE(firstPkgs.size(), 1);
        const QString rev1 = firstPkgs.at(0).toObject().value(QStringLiteral("revision")).toString();
        QVERIFY(!rev1.isEmpty());

        QTest::qWait(20);
        QVERIFY(writeTextFile(devDir + QStringLiteral("/Widget.qml"), "import QtQuick\nItem { property int v: 2 }\n"));

        QTRY_COMPARE_WITH_TIMEOUT(spy.count(), 1, 2000);
        const QJsonObject secondSnap = spy.takeFirst().at(0).toJsonObject();
        const QJsonArray secondPkgs = secondSnap.value(QStringLiteral("packages")).toArray();
        QCOMPARE(secondPkgs.size(), 1);
        const QString rev2 = secondPkgs.at(0).toObject().value(QStringLiteral("revision")).toString();
        QVERIFY(rev2 != rev1);
    }

    void validatesContainersAndDockUnits()
    {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());

        const QString dataRoot = temp.filePath(QStringLiteral("data"));
        const QString widgetsRoot = dataRoot + QStringLiteral("/kos/widgets/");

        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.dock.clock"),
            QStringLiteral("org.example.dock.clock"),
            "{\"id\":\"org.example.dock.clock\",\"name\":\"DockClock\",\"version\":\"1.0\",\"sdkVersion\":1,\"style\":\"macos\",\"containers\":[\"desktop\",\"dock\"],\"dockUnits\":3,\"sizes\":[[2,2]],\"defaultSize\":[2,2]}"));

        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.bad.container"),
            QStringLiteral("org.example.bad.container"),
            "{\"id\":\"org.example.bad.container\",\"name\":\"BadC\",\"version\":\"1.0\",\"sdkVersion\":1,\"style\":\"macos\",\"containers\":[\"lockscreen\"],\"sizes\":[[2,2]],\"defaultSize\":[2,2]}"));

        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.empty.container"),
            QStringLiteral("org.example.empty.container"),
            "{\"id\":\"org.example.empty.container\",\"name\":\"EmptyC\",\"version\":\"1.0\",\"sdkVersion\":1,\"style\":\"macos\",\"containers\":[],\"sizes\":[[2,2]],\"defaultSize\":[2,2]}"));

        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.dup.container"),
            QStringLiteral("org.example.dup.container"),
            "{\"id\":\"org.example.dup.container\",\"name\":\"DupC\",\"version\":\"1.0\",\"sdkVersion\":1,\"style\":\"macos\",\"containers\":[\"dock\",\"dock\"],\"sizes\":[[2,2]],\"defaultSize\":[2,2]}"));

        QVERIFY(createValidPackageDir(widgetsRoot + QStringLiteral("org.example.bad.units"),
            QStringLiteral("org.example.bad.units"),
            "{\"id\":\"org.example.bad.units\",\"name\":\"BadU\",\"version\":\"1.0\",\"sdkVersion\":1,\"style\":\"macos\",\"containers\":[\"dock\"],\"dockUnits\":5,\"sizes\":[[2,2]],\"defaultSize\":[2,2]}"));

        const QJsonObject snap = KosPlatform::WidgetPackageIndex::snapshotForRoots({dataRoot});
        const QJsonArray pkgs = snap.value(QStringLiteral("packages")).toArray();
        QCOMPARE(pkgs.size(), 1);
        const QJsonObject valid = pkgs.at(0).toObject();
        QCOMPARE(valid.value(QStringLiteral("containers")).toArray(), QJsonArray({QStringLiteral("desktop"), QStringLiteral("dock")}));
        QCOMPARE(valid.value(QStringLiteral("dockUnits")).toInt(), 3);

        const QJsonArray invalid = snap.value(QStringLiteral("invalidPackages")).toArray();
        QCOMPARE(invalid.size(), 4);
        QCOMPARE(findInvalid(invalid, QStringLiteral("org.example.bad.container")).value(QStringLiteral("code")).toString(), QStringLiteral("invalid-metadata"));
        QCOMPARE(findInvalid(invalid, QStringLiteral("org.example.empty.container")).value(QStringLiteral("code")).toString(), QStringLiteral("invalid-metadata"));
        QCOMPARE(findInvalid(invalid, QStringLiteral("org.example.dup.container")).value(QStringLiteral("code")).toString(), QStringLiteral("invalid-metadata"));
        QCOMPARE(findInvalid(invalid, QStringLiteral("org.example.bad.units")).value(QStringLiteral("code")).toString(), QStringLiteral("invalid-metadata"));
    }

    void expandsMultiWidgetPackageAndBlocksNamespaceHijack()
    {
        QTemporaryDir temp;
        QVERIFY(temp.isValid());

        const QString dataRoot = temp.filePath(QStringLiteral("data"));
        const QString pkgDir = dataRoot + QStringLiteral("/kos/widgets/org.example.weatherpack");

        QVERIFY(writeTextFile(dataRoot + QStringLiteral("/outside.qml"), "import QtQuick\nItem {}\n"));
        QVERIFY(writeTextFile(pkgDir + QStringLiteral("/metadata.json"),
            "{\n"
            "  \"id\": \"org.example.weatherpack\",\n"
            "  \"name\": \"Weather Pack\",\n"
            "  \"version\": \"1.0.0\",\n"
            "  \"sdkVersion\": 1,\n"
            "  \"widgets\": [\n"
            "    {\n"
            "      \"id\": \"org.example.weatherpack.macos\",\n"
            "      \"name\": \"Weather (macOS)\",\n"
            "      \"style\": \"macos\",\n"
            "      \"sizes\": [[2, 2], [3, 2]],\n"
            "      \"defaultSize\": [2, 2],\n"
            "      \"widgetEntry\": \"macos/Widget.qml\",\n"
            "      \"snapshotEntry\": \"macos/Snapshot.qml\"\n"
            "    },\n"
            "    {\n"
            "      \"id\": \"org.example.weatherpack.material\",\n"
            "      \"name\": \"Weather (Material)\",\n"
            "      \"style\": \"material\",\n"
            "      \"sizes\": [[2, 2]],\n"
            "      \"defaultSize\": [2, 2],\n"
            "      \"widgetEntry\": \"material/Widget.qml\",\n"
            "      \"snapshotEntry\": \"material/Snapshot.qml\"\n"
            "    },\n"
            "    {\n"
            "      \"id\": \"org.other.hijack\",\n"
            "      \"name\": \"Hijack\",\n"
            "      \"style\": \"macos\",\n"
            "      \"sizes\": [[2, 2]],\n"
            "      \"defaultSize\": [2, 2],\n"
            "      \"widgetEntry\": \"macos/Widget.qml\",\n"
            "      \"snapshotEntry\": \"macos/Snapshot.qml\"\n"
            "    },\n"
            "    {\n"
            "      \"id\": \"org.example.weatherpack.escape\",\n"
            "      \"name\": \"Escape\",\n"
            "      \"style\": \"macos\",\n"
            "      \"sizes\": [[2, 2]],\n"
            "      \"defaultSize\": [2, 2],\n"
            "      \"widgetEntry\": \"../../outside.qml\",\n"
            "      \"snapshotEntry\": \"macos/Snapshot.qml\"\n"
            "    }\n"
            "  ]\n"
            "}\n"));
        QVERIFY(writeTextFile(pkgDir + QStringLiteral("/macos/Widget.qml"), "import QtQuick\nItem { property int v: 1 }\n"));
        QVERIFY(writeTextFile(pkgDir + QStringLiteral("/macos/Snapshot.qml"), "import QtQuick\nQtObject { function getSnapshot(s) { return {} } }\n"));
        QVERIFY(writeTextFile(pkgDir + QStringLiteral("/macos/Settings.qml"), "import QtQuick\nItem {}\n"));
        QVERIFY(writeTextFile(pkgDir + QStringLiteral("/material/Widget.qml"), "import QtQuick\nItem {}\n"));
        QVERIFY(writeTextFile(pkgDir + QStringLiteral("/material/Snapshot.qml"), "import QtQuick\nQtObject { function getSnapshot(s) { return {} } }\n"));

        const QJsonObject snap = KosPlatform::WidgetPackageIndex::snapshotForRoots({dataRoot});
        const QJsonArray pkgs = snap.value(QStringLiteral("packages")).toArray();
        QCOMPARE(pkgs.size(), 2);

        const QJsonObject macEntry = pkgs.at(0).toObject();
        QCOMPARE(macEntry.value(QStringLiteral("id")).toString(), QStringLiteral("org.example.weatherpack.macos"));
        QCOMPARE(macEntry.value(QStringLiteral("packageId")).toString(), QStringLiteral("org.example.weatherpack"));
        QCOMPARE(macEntry.value(QStringLiteral("style")).toString(), QStringLiteral("macos"));
        QCOMPARE(macEntry.value(QStringLiteral("hasSettings")).toBool(), true);
        QVERIFY(macEntry.value(QStringLiteral("widgetEntry")).toString().endsWith(QStringLiteral("/macos/Widget.qml")));

        const QJsonObject matEntry = pkgs.at(1).toObject();
        QCOMPARE(matEntry.value(QStringLiteral("id")).toString(), QStringLiteral("org.example.weatherpack.material"));
        QCOMPARE(matEntry.value(QStringLiteral("packageId")).toString(), QStringLiteral("org.example.weatherpack"));
        QCOMPARE(matEntry.value(QStringLiteral("style")).toString(), QStringLiteral("material"));
        QCOMPARE(matEntry.value(QStringLiteral("hasSettings")).toBool(), false);

        const QJsonArray invalid = snap.value(QStringLiteral("invalidPackages")).toArray();
        QCOMPARE(invalid.size(), 2);
        QCOMPARE(findInvalid(invalid, QStringLiteral("org.other.hijack")).value(QStringLiteral("code")).toString(), QStringLiteral("invalid-metadata"));
        QCOMPARE(findInvalid(invalid, QStringLiteral("org.example.weatherpack.escape")).value(QStringLiteral("code")).toString(), QStringLiteral("missing-entry"));

        // Watcher catches edits inside nested multi-widget subdirectories.
        KosPlatform::WidgetPackageIndex::WidgetPackageWatcher watcher({dataRoot});
        QSignalSpy spy(&watcher, &KosPlatform::WidgetPackageIndex::WidgetPackageWatcher::snapshotChanged);
        QTest::qWait(20);
        QVERIFY(writeTextFile(pkgDir + QStringLiteral("/macos/Widget.qml"), "import QtQuick\nItem { property int v: 99 }\n"));
        QTRY_COMPARE_WITH_TIMEOUT(spy.count(), 1, 2000);
        const QJsonObject updated = spy.takeFirst().at(0).toJsonObject();
        QCOMPARE(updated.value(QStringLiteral("packages")).toArray().size(), 2);
        QVERIFY(updated.value(QStringLiteral("packages")).toArray().at(0).toObject().value(QStringLiteral("revision")).toString()
            != macEntry.value(QStringLiteral("revision")).toString());
    }
};

QTEST_MAIN(WidgetPackageIndexTest)
#include "test_widget_package_index.moc"
