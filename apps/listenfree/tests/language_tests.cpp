#include "SystemLanguage.h"
#include "app/interface_translator.h"
#include "qmlbridge/controllers.h"
#include <QtTest>
class LanguageTest : public QObject {
    Q_OBJECT
private slots:
    void followsSystemDespiteSavedChoice() {
        listenfree::qmlbridge::SettingsController settings;
        const QString expected = Kos::I18n::settingsValue();
        const QString other = expected == "ZhCn" ? "EnUs" : "ZhCn";
        QCOMPARE(settings.value("ui.language", other).toString(), expected);
        settings.setValue("ui.language", other);
        QCOMPARE(settings.value("ui.language").toString(), expected);
        QSignalSpy spy(&settings, &listenfree::qmlbridge::SettingsController::valueChanged);
        QVERIFY(settings.reloadValues({{"ui.language", other}, {"ui.fontFamily", "Test font"}}));
        QCOMPARE(settings.value("ui.language").toString(), expected);
        for (const auto &args : spy) QVERIFY(args[0].toString() != "ui.language");
        QCOMPARE(settings.value("ui.fontFamily").toString(), QString("Test font"));
    }
    void englishCatalog() {
        UiTranslator translator;
        QVERIFY(!translator.isEmpty());
        QCoreApplication::installTranslator(&translator);
        QCOMPARE(QCoreApplication::translate("AppShell", "我的收藏"), QString("My favorites"));
        QCOMPARE(QCoreApplication::translate("ListenFree", "请求超时"), QString("Request timed out"));
        QCOMPARE(QCoreApplication::translate("EqualizerPresets", "原声"), QString("Flat"));
        QCoreApplication::removeTranslator(&translator);
    }
};
QTEST_GUILESS_MAIN(LanguageTest)
#include "language_tests.moc"
