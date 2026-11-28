#include "KWinPluginAbi.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>

class KWinPluginAbiTest : public QObject {
    Q_OBJECT
private slots:
    void parsesKWinVersionAndConfigHeader();
    void parsesPluginIidAndBinaryPayload();
    void detectsMismatchAndMatchAcrossPlugins();
    void discoversPluginsFromManifestOrFallback();
};

void KWinPluginAbiTest::parsesKWinVersionAndConfigHeader()
{
    QCOMPARE(parseKWinVersionOutput(QStringLiteral("kwin 6.8.3\n")), QStringLiteral("6.8.3"));
    QCOMPARE(parseKWinVersionOutput(QStringLiteral("kwin 6.7.5-1\n")), QStringLiteral("6.7.5-1"));
    QVERIFY(parseKWinVersionOutput(QStringLiteral("unknown output")).isEmpty());

    const QString header = QStringLiteral(
        "/* generated */\n"
        "#define KWIN_VERSION_STRING \"6.8.3\"\n"
        "#define KWIN_PLUGIN_VERSION_STRING \"6.8.3\"\n");
    QCOMPARE(parseKWinConfigHeader(header), QStringLiteral("6.8.3"));
    QVERIFY(parseKWinConfigHeader(QStringLiteral("#define OTHER \"1.0\"\n")).isEmpty());
}

void KWinPluginAbiTest::parsesPluginIidAndBinaryPayload()
{
    QCOMPARE(parseEffectPluginIid(QStringLiteral("org.kde.kwin.EffectPluginFactory6.8.3")),
        QStringLiteral("6.8.3"));
    QVERIFY(parseEffectPluginIid(QStringLiteral("org.kde.kwin.EffectPluginFactory")).isEmpty());
    QVERIFY(parseEffectPluginIid(QStringLiteral("org.kde.other.Plugin6.8.3")).isEmpty());

    QByteArray payload;
    payload.append('\0');
    payload.append("ELF-header-noise");
    payload.append('\0');
    payload.append("org.kde.kwin.EffectPluginFactory6.7.5");
    payload.append('\0');
    payload.append("trailing");
    QCOMPARE(extractEffectPluginAbiFromBytes(payload), QStringLiteral("6.7.5"));

    QByteArray bareMarker("org.kde.kwin.EffectPluginFactory\0org.kde.kwin.EffectPluginFactory6.8.3\0", 71);
    QCOMPARE(extractEffectPluginAbiFromBytes(bareMarker), QStringLiteral("6.8.3"));
}

void KWinPluginAbiTest::detectsMismatchAndMatchAcrossPlugins()
{
    QTemporaryDir temp;
    QVERIFY(temp.isValid());
    const QString glassPath = temp.filePath(QStringLiteral("glass.so"));
    const QString bridgePath = temp.filePath(QStringLiteral("kos_bridge.so"));

    auto writeFakePlugin = [](const QString& path, const QByteArray& iid) {
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        QByteArray data("QTMETADATA ");
        data.append('\0');
        data.append(iid);
        data.append('\0');
        file.write(data);
    };

    writeFakePlugin(glassPath, "org.kde.kwin.EffectPluginFactory6.7.5");
    writeFakePlugin(bridgePath, "org.kde.kwin.EffectPluginFactory6.7.5");

    const KWinPluginAbiStatus mismatch = inspectKWinPluginAbi(
        QStringLiteral("6.8.3"), { glassPath, bridgePath });
    QVERIFY(mismatch.checked);
    QVERIFY(mismatch.mismatch);
    QCOMPARE(mismatch.kwinVersion, QStringLiteral("6.8.3"));
    QCOMPARE(mismatch.pluginVersion, QStringLiteral("6.7.5"));
    QCOMPARE(mismatch.mismatchedPlugins,
        QStringList({ QStringLiteral("glass"), QStringLiteral("kos_bridge") }));

    const KWinPluginAbiStatus match = inspectKWinPluginAbi(
        QStringLiteral("6.7.5"), { glassPath, bridgePath });
    QVERIFY(match.checked);
    QVERIFY(!match.mismatch);
    QCOMPARE(match.kwinVersion, QStringLiteral("6.7.5"));
    QCOMPARE(match.pluginVersion, QStringLiteral("6.7.5"));
    QVERIFY(match.mismatchedPlugins.isEmpty());
}

void KWinPluginAbiTest::discoversPluginsFromManifestOrFallback()
{
    QTemporaryDir temp;
    QVERIFY(temp.isValid());

    const QString pluginDir = temp.filePath(QStringLiteral("usr/lib64/qt6/plugins/kwin/effects/plugins"));
    QVERIFY(QDir().mkpath(pluginDir));
    const QString glass = QDir(pluginDir).filePath(QStringLiteral("glass.so"));
    const QString decoration = temp.filePath(QStringLiteral("usr/lib64/qt6/plugins/org.kde.kdecoration3/kos_decoration.so"));
    QVERIFY(QDir().mkpath(QFileInfo(decoration).path()));

    for (const QString& p : { glass, decoration }) {
        QFile f(p);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("stub");
    }

    const QString manifestPath = temp.filePath(QStringLiteral("kwin-system-files.manifest"));
    {
        QFile m(manifestPath);
        QVERIFY(m.open(QIODevice::WriteOnly | QIODevice::Text));
        m.write(glass.toUtf8() + "\n" + decoration.toUtf8() + "\n/nonexistent/effects/plugins/missing.so\n");
    }

    QCOMPARE(discoverInstalledKWinEffectPlugins(manifestPath), QStringList({ glass }));
    QCOMPARE(discoverInstalledKWinEffectPlugins(temp.filePath(QStringLiteral("missing.manifest")), { pluginDir }),
        QStringList({ glass }));
}

QTEST_GUILESS_MAIN(KWinPluginAbiTest)
#include "KWinPluginAbiTest.moc"
