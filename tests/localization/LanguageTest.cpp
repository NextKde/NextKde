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
    }
    void systemEnvironment() {
        const bool expected = qEnvironmentVariable("EXPECTED_LANGUAGE") == "zh";
        QCOMPARE(Kos::I18n::isChinese(), expected);
        QCOMPARE(Kos::I18n::locale().language(), expected ? QLocale::Chinese : QLocale::English);
    }
    void catalogs() {
        QTranslator translator;
        QVERIFY(translator.load(":/kos/i18n/kos_apps_zh_CN.qm"));
        QCoreApplication::installTranslator(&translator);
        QCOMPARE(QCoreApplication::translate("Main", "Weather"), QString::fromUtf8("天气"));
        QCOMPARE(QCoreApplication::translate("Main", "%n task(s)", nullptr, 0), QString::fromUtf8("0 个任务"));
        QCOMPARE(QCoreApplication::translate("Main", "%n task(s)", nullptr, 2), QString::fromUtf8("2 个任务"));
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
