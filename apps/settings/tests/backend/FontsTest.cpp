#include "FontSettings.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontInfo>
#include <QGuiApplication>
#include <QImage>
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
private slots:
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
        QVERIFY2(settings.apply(), qPrintable(settings.error()));
        settings.reset();
        QCOMPARE(settings.fonts()->property("font").value<QFont>(), chosen);
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

        // Load the production form against the actual plugin properties, not a
        // mock: private KCM property/type changes must fail before shipping.
        QStringList warnings;
        connect(&engine, &QQmlEngine::warnings, this, [&warnings](const QList<QQmlError> &errors) {
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
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        QTest::qWait(250);
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
    qputenv("QT_QPA_PLATFORM", "offscreen");
    qputenv("QT_QUICK_BACKEND", "software");
    qunsetenv("DISPLAY");
    qunsetenv("WAYLAND_DISPLAY");
    QGuiApplication app(argc, argv);
    FontsTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "FontsTest.moc"
