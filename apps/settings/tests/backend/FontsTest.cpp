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

static QQuickItem *visualItem(QQuickItem *root, const QString &name)
{
    if (root->objectName() == name) return root;
    for (auto *child : root->childItems())
        if (auto *found = visualItem(child, name)) return found;
    return nullptr;
}

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
        if (qEnvironmentVariableIsSet("KOS_EXPECT_FONT_DPI"))
            QCOMPARE(settings.dpiAvailable(), qEnvironmentVariableIntValue("KOS_EXPECT_FONT_DPI") == 1);
        const bool canSetDpi = x11 && settings.dpiAvailable();
        QCOMPARE(settings.renderingEditable(QStringLiteral("dpi")), canSetDpi);
        const int initialDpi = settings.rendering()->property("dpi").toInt();
        settings.setRendering(QStringLiteral("dpi"), 120);
        QCOMPARE(settings.rendering()->property("dpi").isValid(), settings.dpiAvailable());
        QCOMPARE(settings.rendering()->property("dpi").toInt(), canSetDpi ? 120 : initialDpi);
        QTRY_VERIFY(settings.needsSave());
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
        QCOMPARE(settings.rendering()->property("dpi").toInt(), canSetDpi ? 120 : initialDpi);
        KConfig persisted(QStringLiteral("kdeglobals"));
        // Read independent KConfig data as well as the live KCM model. A model
        // round trip alone could pass while changes have not reached disk.
        persisted.reparseConfiguration();
        for (const auto &role : roles) {
            const auto group = role == QLatin1String("activeFont") ? "WM" : "General";
            const auto font = KConfigGroup(&persisted, group).readEntry(role, QFont());
            QCOMPARE(font.family(), chosen[role].family());
            QCOMPARE(font.pointSizeF(), chosen[role].pointSizeF());
            QCOMPARE(font.weight(), chosen[role].weight());
            QCOMPARE(font.style(), chosen[role].style());
        }
        QCOMPARE(KConfigGroup(&persisted, "General").readEntry("NextKdeUnknownFontOption", QString()),
            QStringLiteral("preserve-me"));
        if (canSetDpi) {
            settings.setRendering(QStringLiteral("dpi"), 0);
            QTRY_VERIFY(settings.needsSave());
            QVERIFY2(settings.apply(), qPrintable(settings.error()));
            settings.reset();
            QCOMPARE(settings.rendering()->property("dpi").toInt(), 0);
        }
        QTRY_VERIFY(!settings.needsSave());
    }

    void debouncedSave()
    {
        QQmlEngine engine;
        FontSettings settings(&engine);
        settings.refresh();
        QVERIFY2(settings.available(), qPrintable(settings.error()));
        auto font = settings.fonts()->property("font").value<QFont>();
        const int beforeSave = refreshCount;
        font.setPointSizeF(font.pointSizeF() + 1);
        settings.setFont(QStringLiteral("font"), font);
        QTest::qWait(80);
        QCOMPARE(refreshCount, beforeSave);
        font.setPointSizeF(font.pointSizeF() + 1);
        settings.setFont(QStringLiteral("font"), font);
        settings.refresh(); // Page activation must not reload over pending edits.
        QCOMPARE(settings.fonts()->property("font").value<QFont>(), font);
        QTRY_COMPARE_WITH_TIMEOUT(refreshCount, beforeSave + 1, 3000);
        QTRY_VERIFY(!settings.needsSave());
        QTest::qWait(450);
        QCOMPARE(refreshCount, beforeSave + 1); // One KDE refresh for the burst.
        KConfig persisted(QStringLiteral("kdeglobals"));
        QCOMPARE(KConfigGroup(&persisted, "General").readEntry("font", QFont()).pointSizeF(), font.pointSizeF());
    }

    void flushPendingEditOnExit()
    {
        QQmlEngine engine;
        QFont chosen;
        {
            FontSettings settings(&engine);
            settings.refresh();
            QVERIFY2(settings.available(), qPrintable(settings.error()));
            // KDE registers its settings on the next event-loop turn; a real
            // user reaches the controls only after the first frame is shown.
            QTest::qWait(1);
            chosen = settings.fonts()->property("menuFont").value<QFont>();
            chosen.setPointSizeF(chosen.pointSizeF() + 1);
            settings.setFont(QStringLiteral("menuFont"), chosen);
            // No wait after the edit: exiting during debounce must still persist.
        }
        KConfig persisted(QStringLiteral("kdeglobals"));
        QCOMPARE(KConfigGroup(&persisted, "General").readEntry("menuFont", QFont()).pointSizeF(), chosen.pointSizeF());
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
        auto dpiRow = page->findChild<QQuickItem *>(QStringLiteral("font-dpi-row"));
        QVERIFY(dpiRow);
        QCOMPARE(dpiRow->isVisible(), settings.dpiAvailable() && QGuiApplication::platformName() == QLatin1String("xcb"));
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
        QVERIFY(preview->isVisible());
        const QRectF previewBounds = preview->mapRectToItem(page, preview->boundingRect());
        QVERIFY(previewBounds.left() >= 0 && previewBounds.right() <= page->width());
        const auto screenshot = qEnvironmentVariable("KOS_FONT_SCREENSHOT");
        if (!screenshot.isEmpty()) {
            QDir().mkpath(QFileInfo(screenshot).absolutePath());
            QVERIFY(window.grabWindow().save(screenshot));
        }
        // The compact value row itself is the font picker affordance.
        auto fontRow = visualItem(page, QStringLiteral("choose-font-font"));
        auto picker = page->findChild<QObject *>(QStringLiteral("font-picker"));
        QVERIFY(fontRow);
        QVERIFY(picker);
        QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier,
            fontRow->mapToScene(fontRow->boundingRect().center()).toPoint());
        QTRY_VERIFY(picker->property("visible").toBool());
        QVERIFY(QMetaObject::invokeMethod(picker, "reject"));
        QTRY_VERIFY(!picker->property("visible").toBool());
        const auto previewSource = preview->property("source");
        window.hide();
        QTRY_VERIFY(!window.isActive());
        QCOMPARE(preview->property("source"), previewSource);
        QCOMPARE(preview->property("status").toInt(), 1);
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
