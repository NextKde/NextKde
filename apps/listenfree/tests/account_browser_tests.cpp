#include "app/account_browser.h"
#include "qmlbridge/account_service.h"
#include <QApplication>
#include <QFile>
#include <QMessageBox>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

class AccountBrowserTests : public QObject {
    Q_OBJECT
    QTemporaryDir directory_;
    QByteArray path_;
    QString helper() const { return directory_.filePath("listenfree-web-login"); }
    void script(const QByteArray& body) {
        QFile file(helper());
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("#!/bin/sh\n" + body);
        file.close();
        QVERIFY(file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    }
private slots:
    void init() {
        QVERIFY(directory_.isValid());
        path_ = qgetenv("PATH");
        qputenv("PATH", directory_.path().toUtf8());
        qputenv("LISTENFREE_LOGIN_TEST_ARGS", directory_.filePath("arguments").toUtf8());
        qApp->setProperty("listenfreeDataDir", directory_.path());
        QFile::remove(helper());
        QFile::remove(directory_.filePath("arguments"));
    }
    void cleanup() { qputenv("PATH", path_); qunsetenv("LISTENFREE_LOGIN_TEST_ARGS"); }
    void missingComponentIsOptionalAndInvalidProviderDoesNothing() {
        listenfree::qmlbridge::AccountService accounts(directory_.path());
        listenfree::AccountBrowser browser(accounts);
        browser.open("invalid");
        QVERIFY(QApplication::topLevelWidgets().isEmpty());
        browser.open("netease");
        browser.open("netease");
        int count = 0;
        for (auto* widget : QApplication::topLevelWidgets()) {
            if (widget->objectName() != "webLoginInstallDialog") continue;
            ++count;
            auto* dialog = qobject_cast<QMessageBox*>(widget);
            QVERIFY(dialog);
            QVERIFY(dialog->text().contains("listenfree-web-login"));
            QVERIFY(dialog->text().contains("Cookie"));
        }
        QCOMPARE(count, 1);
        QVERIFY(accounts.accounts().isEmpty());
    }
    void helperReceivesOnlyProviderAndProfileAndCanBeCancelled() {
        script("printf '%s\\n' \"$@\" > \"$LISTENFREE_LOGIN_TEST_ARGS\"\n/bin/sleep 0.2\nexit 1\n");
        listenfree::qmlbridge::AccountService accounts(directory_.path());
        listenfree::AccountBrowser browser(accounts);
        QSignalSpy notices(&browser, &listenfree::AccountBrowser::notice);
        browser.open("netease");
        browser.open("qqmusic");
        QCOMPARE(notices.size(), 1); // Duplicate requests do not start another process.
        QTRY_VERIFY(QFile::exists(directory_.filePath("arguments")));
        QFile file(directory_.filePath("arguments"));
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), QByteArray("--provider\nnetease\n--profile\n") + directory_.path().toUtf8() + '\n');
        QTest::qWait(350);
        QCOMPARE(notices.size(), 1); // Cancellation is not an error.
        QVERIFY(accounts.accounts().isEmpty());
    }
    void helperFailureDoesNotTerminatePlayer_data() {
        QTest::addColumn<QByteArray>("body");
        QTest::newRow("failure") << QByteArray("exit 2\n");
        QTest::newRow("crash") << QByteArray("kill -KILL $$\n");
    }
    void helperFailureDoesNotTerminatePlayer() {
        QFETCH(QByteArray, body);
        script(body);
        listenfree::qmlbridge::AccountService accounts(directory_.path());
        listenfree::AccountBrowser browser(accounts);
        QSignalSpy notices(&browser, &listenfree::AccountBrowser::notice);
        browser.open("netease");
        QTRY_COMPARE(notices.size(), 1);
        QVERIFY(accounts.accounts().isEmpty());
    }
};
QTEST_MAIN(AccountBrowserTests)
#include "account_browser_tests.moc"
