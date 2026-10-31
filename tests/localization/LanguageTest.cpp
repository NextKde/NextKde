#include "SystemLanguage.h"
#include <QCoreApplication>
#include <QTranslator>
#include <QtTest>

class LanguageTest : public QObject {
    Q_OBJECT
private slots:
    void primaryLanguage() {
        for (const auto &lang : {"zh", "zh-CN", "zh-Hant-TW", "zh_HK", "ZH-SG"})
            QVERIFY(Kos::I18n::isChinese({QString::fromLatin1(lang), "en-US"}));
        for (const auto &lang : {"en-US", "fr-FR", "ja-JP", "C", "", "zho"})
            QVERIFY(!Kos::I18n::isChinese({QString::fromLatin1(lang), "zh-CN"}));
        QVERIFY(!Kos::I18n::isChinese({}));
        for (const auto &lang : {"pt", "pt-BR", "pt_PT", "PT-br"})
            QVERIFY(Kos::I18n::isPortuguese({QString::fromLatin1(lang), "en-US"}));
        for (const auto &lang : {"en-US", "es-ES", "zh-CN", "C", "", "por"})
            QVERIFY(!Kos::I18n::isPortuguese({QString::fromLatin1(lang), "pt-BR"}));
        QVERIFY(!Kos::I18n::isPortuguese({}));
        QCOMPARE(Kos::I18n::settingsValue({"pt-BR"}), QString("EnUs"));
        QCOMPARE(Kos::I18n::settingsValue({"pt-PT"}), QString("EnUs"));
        QCOMPARE(Kos::I18n::settingsValue({"zh-CN"}), QString("ZhCn"));
    }
    void systemEnvironment() {
        const QString expected = qEnvironmentVariable("EXPECTED_LANGUAGE");
        QCOMPARE(Kos::I18n::isChinese(), expected == "zh");
        QCOMPARE(Kos::I18n::isPortuguese(), expected == "pt");
        QCOMPARE(Kos::I18n::locale().language(), expected == "zh" ? QLocale::Chinese
            : expected == "pt" ? QLocale::Portuguese : QLocale::English);
    }
    void catalogs() {
        QTranslator translator;
        QVERIFY(translator.load(":/kos/i18n/kos_apps_zh_CN.qm"));
        QCoreApplication::installTranslator(&translator);
        QCOMPARE(QCoreApplication::translate("Main", "Weather"), QString::fromUtf8("天气"));
        QCOMPARE(QCoreApplication::translate("Main", "%n task(s)", nullptr, 0), QString::fromUtf8("0 个任务"));
        QCOMPARE(QCoreApplication::translate("Main", "%n task(s)", nullptr, 2), QString::fromUtf8("2 个任务"));
        QCoreApplication::removeTranslator(&translator);
        QVERIFY(translator.load(":/kos/i18n/kos_apps_pt_BR.qm"));
        QCoreApplication::installTranslator(&translator);
        QCOMPARE(QCoreApplication::translate("Main", "Weather"), QString::fromUtf8("Clima"));
        QCOMPARE(QCoreApplication::translate("Main", "%n task(s)", nullptr, 1), QString("1 tarefa"));
        QCOMPARE(QCoreApplication::translate("Main", "%n task(s)", nullptr, 2), QString("2 tarefas"));
        QCoreApplication::removeTranslator(&translator);
        QVERIFY(translator.load(":/kos/i18n/kos_apps_en_US.qm"));
        QCoreApplication::installTranslator(&translator);
        QCOMPARE(QCoreApplication::translate("Main", "%n task(s)", nullptr, 1), QString("1 task"));
        QCOMPARE(QCoreApplication::translate("Main", "%n task(s)", nullptr, 2), QString("2 tasks"));
        QCoreApplication::removeTranslator(&translator);
    }
};
QTEST_GUILESS_MAIN(LanguageTest)
#include "LanguageTest.moc"
