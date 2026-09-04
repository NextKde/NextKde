#include "ApplicationPreferences.h"

#include <QTemporaryDir>
#include <QSignalSpy>
#include <QtTest>

using Kos::App::ApplicationPreferences;

class ApplicationPreferencesTest final : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        qunsetenv("KOS_APPEARANCE");
        qunsetenv("KOS_MATERIAL");
        qunsetenv("KOS_MATERIAL_OPACITY");
        qunsetenv("KOS_ACCENT");
        qunsetenv("KOS_REDUCE_TRANSPARENCY");
        qunsetenv("KOS_REDUCE_MOTION");
    }

    void defaultsAreReadableAndSolidWithoutCompositor()
    {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        ApplicationPreferences preferences(directory.filePath(QStringLiteral("settings.ini")));

        QCOMPARE(preferences.appearanceMode(), QStringLiteral("system"));
        QCOMPARE(preferences.materialMode(), QStringLiteral("auto"));
        QCOMPARE(preferences.accentName(), QStringLiteral("system"));
        QCOMPARE(preferences.materialOpacity(), 0.86);
        QVERIFY(!preferences.glassActive());
        QCOMPARE(preferences.effectiveMaterialOpacity(), 1.0);
    }

    void valuesPersistAndInvalidEnumsFallBack()
    {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QString path = directory.filePath(QStringLiteral("settings.ini"));
        {
            ApplicationPreferences writer(path);
            writer.setAppearanceMode(QStringLiteral("dark"));
            writer.setMaterialMode(QStringLiteral("glass"));
            writer.setAccentName(QStringLiteral("purple"));
            writer.setReduceMotion(true);
        }
        {
            ApplicationPreferences reader(path);
            QCOMPARE(reader.appearanceMode(), QStringLiteral("dark"));
            QCOMPARE(reader.materialMode(), QStringLiteral("glass"));
            QCOMPARE(reader.accentName(), QStringLiteral("purple"));
            QVERIFY(reader.reduceMotion());

            reader.setAppearanceMode(QStringLiteral("sepia"));
            reader.setMaterialMode(QStringLiteral("mist"));
            reader.setAccentName(QStringLiteral("ultraviolet"));
            QCOMPARE(reader.appearanceMode(), QStringLiteral("system"));
            QCOMPARE(reader.materialMode(), QStringLiteral("auto"));
            QCOMPARE(reader.accentName(), QStringLiteral("system"));
        }
    }

    void opacityIsClampedAndGlassHasSafeFallback()
    {
        QTemporaryDir directory;
        ApplicationPreferences preferences(directory.filePath(QStringLiteral("settings.ini")));
        preferences.setMaterialMode(QStringLiteral("glass"));
        preferences.setMaterialOpacity(0.1);

        QCOMPARE(preferences.materialOpacity(), 0.72);
        QVERIFY(preferences.glassActive());
        QCOMPARE(preferences.effectiveMaterialOpacity(), 0.93);

        preferences.setNativeEffectsAvailable(true, true);
        QCOMPARE(preferences.effectiveMaterialOpacity(), 0.72);

        preferences.setMaterialOpacity(2.0);
        QCOMPARE(preferences.materialOpacity(), 0.98);
        preferences.setReduceTransparency(true);
        QVERIFY(!preferences.glassActive());
        QCOMPARE(preferences.effectiveMaterialOpacity(), 1.0);
    }

    void runningInstancesObserveSharedChanges()
    {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QString path = directory.filePath(QStringLiteral("settings.ini"));
        ApplicationPreferences reader(path);
        ApplicationPreferences writer(path);
        QSignalSpy changed(&reader, &ApplicationPreferences::preferencesChanged);

        writer.setAccentName(QStringLiteral("orange"));
        QTRY_VERIFY_WITH_TIMEOUT(changed.count() > 0, 2500);
        QCOMPARE(reader.accentName(), QStringLiteral("orange"));
    }

    void resetRestoresDefaults()
    {
        QTemporaryDir directory;
        ApplicationPreferences preferences(directory.filePath(QStringLiteral("settings.ini")));
        preferences.setAppearanceMode(QStringLiteral("light"));
        preferences.setMaterialMode(QStringLiteral("glass"));
        preferences.setAccentName(QStringLiteral("green"));
        preferences.setReduceTransparency(true);
        preferences.resetAppearance();

        QCOMPARE(preferences.appearanceMode(), QStringLiteral("system"));
        QCOMPARE(preferences.materialMode(), QStringLiteral("auto"));
        QCOMPARE(preferences.accentName(), QStringLiteral("system"));
        QVERIFY(!preferences.reduceTransparency());
    }
};

QTEST_GUILESS_MAIN(ApplicationPreferencesTest)

#include "ApplicationPreferencesTest.moc"
