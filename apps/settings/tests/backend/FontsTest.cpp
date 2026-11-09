#include "FontSettings.h"

#include <KConfig>
#include <KConfigGroup>
#include <QDBusConnection>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontInfo>
#include <QGuiApplication>
#include <QImage>
#include <QMap>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QTest>
#include <QtQml/qqmlextensionplugin.h>

Q_IMPORT_QML_PLUGIN(Kos_DemoPlugin)

class FontsTest : public QObject {
    Q_OBJECT
    int refreshCount = 0;
public slots:
    void fontRefreshReceived() { ++refreshCount; }
private slots:
    void initTestCase()
    {
        // Listen on CTest's private bus: save must delegate to KDE's real
        // refresh path, not merely make our own UI appear up to date.
        QVERIFY(QDBusConnection::sessionBus().connect(QString(), QStringLiteral("/KDEPlatformTheme"),
            QStringLiteral("org.kde.KDEPlatformTheme"), QStringLiteral("refreshFonts"),
            this, SLOT(fontRefreshReceived())));
        KConfig config(QStringLiteral("kdeglobals"));
        KConfigGroup(&config, "General").writeEntry("NextKdeUnknownFontOption", "preserve-me");
        QVERIFY(config.sync());
    }

    void kdeRoundTrip()
    {
        QQmlEngine engine;
        FontSettings settings(&engine);
        settings.refresh();
        QVERIFY2(settings.available(), qPrintable(settings.error()));
        QVERIFY(settings.fonts());
        QVERIFY(settings.rendering());
        QCOMPARE(settings.subPixelOptions().size(), 5);
        QCOMPARE(settings.hintingOptions().size(), 4);
        QTRY_VERIFY(!settings.needsSave());

        QFont original = settings.fonts()->property("font").value<QFont>();
        QFont chosen = original;
        chosen.setPointSizeF(original.pointSizeF() + 2);
        settings.setFont(QStringLiteral("font"), chosen);
        QTRY_VERIFY(settings.needsSave());
        settings.refresh(); // Navigation/activation must not discard staged edits.
        QCOMPARE(settings.fonts()->property("font").value<QFont>(), chosen);
        settings.reset();
        QCOMPARE(settings.fonts()->property("font").value<QFont>(), original);
        QTRY_VERIFY(!settings.needsSave());

        settings.setFont(QStringLiteral("font"), chosen);
        settings.setRendering(QStringLiteral("antiAliasing"), false);
        settings.setSubPixel(2);
        settings.setHinting(3);
        QTRY_VERIFY(settings.needsSave());
        const int beforeSave = refreshCount;
        QVERIFY2(settings.apply(), qPrintable(settings.error()));
        QTRY_VERIFY(refreshCount > beforeSave);
        settings.reset();
        // KConfig normalizes a named "Regular" style to an empty styleName on
        // reload. Compare the actual font selection, not that serialization hint.
        const QFont restored = settings.fonts()->property("font").value<QFont>();
        QCOMPARE(restored.family(), chosen.family());
        QCOMPARE(restored.pointSizeF(), chosen.pointSizeF());
        QCOMPARE(restored.weight(), chosen.weight());
        QCOMPARE(restored.style(), chosen.style());
        QCOMPARE(settings.rendering()->property("antiAliasing").toBool(), false);
        QCOMPARE(settings.module()->property("subPixelCurrentIndex").toInt(), 2);
        QCOMPARE(settings.module()->property("hintingCurrentIndex").toInt(), 3);
        QTRY_VERIFY(!settings.needsSave());

        QFile persisted(qEnvironmentVariable("XDG_CONFIG_HOME") + QStringLiteral("/kdeglobals"));
        QVERIFY(persisted.open(QIODevice::ReadOnly));
        QVERIFY(persisted.readAll().contains("font="));
        QVERIFY(QFile::exists(qEnvironmentVariable("XDG_CONFIG_HOME") + QStringLiteral("/fontconfig/fonts.conf")));

        const QFont fixed = settings.fonts()->property("fixed").value<QFont>();
        chosen.setPointSize(14);
        settings.adjustAllFonts(chosen, true, false, true);
        QCOMPARE(settings.fonts()->property("smallestReadableFont").value<QFont>().pointSize(), 12);
        if (!QFontInfo(chosen).fixedPitch())
            QCOMPARE(settings.fonts()->property("fixed").value<QFont>().family(), fixed.family());
        QCOMPARE(settings.fonts()->property("fixed").value<QFont>().pointSize(), 14);
        settings.defaults();
        QTRY_VERIFY(settings.needsSave());
        settings.reset();
        QTRY_VERIFY(!settings.needsSave());
    }

    void allRolesAndRenderingRoundTrip()
    {
        QQmlEngine engine;
        FontSettings settings(&engine);
        settings.refresh();
        QVERIFY2(settings.available(), qPrintable(settings.error()));
        const QStringList roles{QStringLiteral("font"), QStringLiteral("fixed"),
            QStringLiteral("smallestReadableFont"), QStringLiteral("toolBarFont"),
            QStringLiteral("menuFont"), QStringLiteral("activeFont")};
        QMap<QString, QFont> chosen;
        for (const auto &role : roles) {
            QVERIFY(settings.fontEditable(role));
            auto font = settings.fonts()->property(role.toUtf8().constData()).value<QFont>();
            font.setPointSizeF(font.pointSizeF() + 1);
            chosen.insert(role, font);
            settings.setFont(role, font);
        }
        settings.setRendering(QStringLiteral("antiAliasing"), true);
        settings.setRendering(QStringLiteral("exclude"), true);
        settings.setRendering(QStringLiteral("excludeFrom"), 9);
        settings.setRendering(QStringLiteral("excludeTo"), 17);
        const bool x11 = QGuiApplication::platformName() == QLatin1String("xcb");
        QCOMPARE(settings.renderingEditable(QStringLiteral("dpi")), x11);
        const int initialDpi = settings.rendering()->property("dpi").toInt();
        settings.setRendering(QStringLiteral("dpi"), 120);
        QCOMPARE(settings.rendering()->property("dpi").toInt(), x11 ? 120 : initialDpi);
        QVERIFY2(settings.apply(), qPrintable(settings.error()));
        settings.reset();
        for (const auto &role : roles) {
            const auto font = settings.fonts()->property(role.toUtf8().constData()).value<QFont>();
            QCOMPARE(font.family(), chosen[role].family());
            QCOMPARE(font.pointSizeF(), chosen[role].pointSizeF());
            QCOMPARE(font.weight(), chosen[role].weight());
            QCOMPARE(font.style(), chosen[role].style());
        }
        QCOMPARE(settings.rendering()->property("antiAliasing").toBool(), true);
        QCOMPARE(settings.rendering()->property("exclude").toBool(), true);
        QCOMPARE(settings.rendering()->property("excludeFrom").toInt(), 9);
        QCOMPARE(settings.rendering()->property("excludeTo").toInt(), 17);
        QCOMPARE(settings.rendering()->property("dpi").toInt(), x11 ? 120 : initialDpi);
        KConfig persisted(QStringLiteral("kdeglobals"));
        QCOMPARE(KConfigGroup(&persisted, "General").readEntry("NextKdeUnknownFontOption", QString()),
            QStringLiteral("preserve-me"));
        if (x11) {
            settings.setRendering(QStringLiteral("dpi"), 0);
            QVERIFY2(settings.apply(), qPrintable(settings.error()));
            settings.reset();
            QCOMPARE(settings.rendering()->property("dpi").toInt(), 0);
        }
        QTRY_VERIFY(!settings.needsSave());
    }

    void nativePage()
    {
        QQmlEngine engine;
        FontSettings settings(&engine);
        settings.refresh();
        QVERIFY2(settings.available(), qPrintable(settings.error()));
        // Load the production form against the actual plugin properties, not a
        // mock: private KCM property/type changes must fail before shipping.
        QStringList warnings;
        QObject warningScope;
        connect(&engine, &QQmlEngine::warnings, &warningScope, [&warnings](const QList<QQmlError> &errors) {
            for (const auto &error : errors) warnings.append(error.toString());
        });
        QQmlComponent component(&engine, QUrl::fromLocalFile(QStringLiteral(FONT_SETTINGS_PAGE)));
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        const QVariantMap colors{{"primaryText", "#1c1c1e"}, {"secondaryText", "#6d6d72"},
            {"card", "#ffffff"}, {"accent", "#0a84ff"}, {"dark", false}};
        QQuickWindow window;
        window.setColor(QColor("#eff0f1"));
        window.resize(550, 1500);
        auto page = qobject_cast<QQuickItem *>(component.createWithInitialProperties(
            {{"colors", colors}, {"backend", QVariant::fromValue(&settings)}}));
        QVERIFY2(page, qPrintable(component.errorString()));
        page->setParent(&window);
        page->setParentItem(window.contentItem());
        page->setX(15);
        page->setY(15);
        page->setWidth(520);
        QTRY_VERIFY(page->property("ready").toBool());
        window.show();
        window.requestActivate();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        QTRY_VERIFY(window.isActive());
        // Application activation refreshes the form. Stage the edit afterwards,
        // as a real interaction does, rather than racing that initial reload.
        settings.setRendering(QStringLiteral("antiAliasing"), true);
        QTRY_VERIFY(page->property("antiAliasing").toBool());
        auto preview = page->findChild<QQuickItem *>(QStringLiteral("font-rendering-preview"));
        QVERIFY(preview);
        QTRY_COMPARE(preview->property("status").toInt(), 1); // Image.Ready
        QTRY_VERIFY(preview->width() > 10 && preview->height() > 5);
        // Wait for the form's layout polish and toggle transition before the
        // screenshot; Image.Ready can precede the first painted preview frame.
        QTest::qWait(400);
        const auto screenshot = qEnvironmentVariable("KOS_FONT_SCREENSHOT");
        if (!screenshot.isEmpty()) {
            QDir().mkpath(QFileInfo(screenshot).absolutePath());
            QVERIFY(window.grabWindow().save(screenshot));
        }
        QVERIFY2(warnings.isEmpty(), qPrintable(warnings.join('\n')));
    }
};

int main(int argc, char **argv)
{
    // The real KDE module writes several files and exports settings. Isolate all
    // user roots before constructing Qt/KConfig, and use CTest's private D-Bus.
    QTemporaryDir home;
    if (!home.isValid()) return 1;
    qputenv("HOME", home.path().toUtf8());
    for (const auto &entry : {"XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR"}) {
        const QString path = home.path() + QLatin1Char('/') + QString::fromLatin1(entry);
        QDir().mkpath(path);
        QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        qputenv(entry, path.toUtf8());
    }
    qputenv("QT_QPA_PLATFORM", qgetenv("KOS_FONT_TEST_PLATFORM").isEmpty()
        ? QByteArray("offscreen") : qgetenv("KOS_FONT_TEST_PLATFORM"));
    qputenv("QT_QUICK_BACKEND", "software");
    qputenv("KDE_FULL_SESSION", "true");
    // CTest provides a private Xvfb: KDE's font preview uses Xft even when Qt
    // itself renders offscreen. Keep DISPLAY for that provider and xrdb export.
    qunsetenv("WAYLAND_DISPLAY");
    QGuiApplication app(argc, argv);
    FontsTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "FontsTest.moc"
