#include "app/shortcut_service.h"
#include "infrastructure/database/database.h"
#include "infrastructure/database/repositories.h"
#include <QApplication>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <windows.h>
using namespace listenfree;
namespace listenfree {
// Send through the real HWND/message queue. RegisterHotKey ownership is tested
// separately; unattended Windows input injection is not a physical-key test.
struct ShortcutServiceTestAccess {
    static bool post(ShortcutService& service, const QString& sequence) {
        const auto native=service.nativeKey(QKeySequence::fromString(sequence,QKeySequence::PortableText));
        const auto registration=service.registered_.value(native.identity());
        return registration.id && PostMessageW(static_cast<HWND>(service.receiver_),WM_HOTKEY,
            registration.id,MAKELPARAM(native.modifiers,native.key));
    }
};
}
namespace {
const QString appPlay="shortcuts.application.playPause", appNext="shortcuts.application.next";
const QString globalPlay="shortcuts.global.playPause", globalNext="shortcuts.global.next";
void clearGlobals(ShortcutService& service) {
    const auto defaults=ShortcutService::defaults();
    for(auto it=defaults.cbegin();it!=defaults.cend();++it)if(it.key().startsWith("shortcuts.global."))QVERIFY(service.setBinding(it.key(),""));
}
}
class ShortcutTests final : public QObject {
    Q_OBJECT
private slots:
    void applicationBackDefaultRemapAndDisable() {
        qmlbridge::SettingsController settings;ShortcutService service(settings);
        const QString key="shortcuts.application.back";
        QCOMPARE(service.binding(key),QString("Esc"));
        QWindow window;window.resize(400,200);window.show();window.requestActivate();QVERIFY(QTest::qWaitForWindowActive(&window));service.setWindow(&window);
        QSignalSpy actions(&service,&ShortcutService::activated);
        QTest::keyClick(&window,Qt::Key_Escape);QTRY_COMPARE(actions.count(),1);QCOMPARE(actions.takeFirst().first().toString(),QString("back"));
        QVERIFY(service.setBinding(key,"Alt+Left"));
        QTest::keyClick(&window,Qt::Key_Escape);QCOMPARE(actions.count(),0);
        QTest::keyClick(&window,Qt::Key_Left,Qt::AltModifier);QTRY_COMPARE(actions.count(),1);QCOMPARE(actions.takeFirst().first().toString(),QString("back"));
        QVERIFY(service.setEnabled("application",false));QTest::keyClick(&window,Qt::Key_Left,Qt::AltModifier);QCOMPARE(actions.count(),0);
        QVERIFY(service.resetGroup("application"));QCOMPARE(service.binding(key),QString("Esc"));
    }
    void atomicPreferenceSwap() {
        QTemporaryDir directory;
        infrastructure::database::Database db;QVERIFY(db.open(directory.filePath("settings.sqlite")));
        infrastructure::database::SettingsRepository repository(db);qmlbridge::SettingsController settings(repository);ShortcutService service(settings);
        const QVariantMap swapped{{appPlay,"Ctrl+Right"},{appNext,"Ctrl+F5"}};
        QVERIFY(db.applySettings(swapped,{},[&]{return settings.reloadValues(swapped);}));
        QCOMPARE(service.binding(appPlay),QString("Ctrl+Right"));QCOMPARE(service.binding(appNext),QString("Ctrl+F5"));
        const QVariantMap invalid{{appPlay,"Ctrl+F5"},{appNext,"Ctrl+F5"}};
        QVERIFY(!db.applySettings(invalid,{},[&]{return settings.reloadValues(invalid);}));
        QVERIFY(settings.reloadValues(swapped));
        QCOMPARE(service.binding(appPlay),QString("Ctrl+Right"));
        QCOMPARE(settings.value(appPlay).toString(),QString("Ctrl+Right"));
    }
    void defaultsAndPersistence() {
        QTemporaryDir directory;
        infrastructure::database::Database db;QVERIFY(db.open(directory.path()+"/settings.sqlite"));QVERIFY(db.migrate());
        infrastructure::database::SettingsRepository repository(db);
        {
            qmlbridge::SettingsController settings(repository);ShortcutService service(settings);
            QCOMPARE(service.binding(appPlay),"Ctrl+F5");QVERIFY(service.enabled("application"));QVERIFY(!service.enabled("global"));
            QVERIFY(service.setBinding(appPlay,"Ctrl+F8"));QVERIFY(service.setBinding(appNext,""));
        }
        qmlbridge::SettingsController settings(repository);ShortcutService service(settings);
        QCOMPARE(service.binding(appPlay),"Ctrl+F8");QCOMPARE(service.binding(appNext),"");
        QVERIFY(service.resetGroup("application"));QCOMPARE(service.binding(appPlay),"Ctrl+F5");QCOMPARE(service.binding(appNext),"Ctrl+Right");
    }
    void reservedAndConflictingBindings() {
        qmlbridge::SettingsController settings;ShortcutService service(settings);
        for(const auto& text:QStringList{"Ctrl","Meta+A","Alt+Tab","Alt+F4","Ctrl+Esc","Ctrl+Shift+Esc","Ctrl+Alt+Delete","F12","A","Shift+A","Ctrl+K, Ctrl+C"}) {
            QVERIFY2(!service.setBinding(globalPlay,text),qPrintable(text));QCOMPARE(service.binding(globalPlay),"Ctrl+Alt+F5");
        }
        QVERIFY(!service.setBinding(appNext,"Ctrl+F5"));QCOMPARE(service.conflictKey(),appPlay);
        QCOMPARE(service.binding(appNext),"Ctrl+Right");
        QVERIFY(service.setBinding(globalPlay,"Ctrl+F5")); // Different scopes may share a binding.
        QVERIFY(service.setBinding(appNext,"Ctrl++"));
        QVERIFY(!service.setBinding(appPlay,"Ctrl+Shift+=")); // Same physical OEM key.
    }
    void recordingConsumesAndCancels() {
        qmlbridge::SettingsController settings;ShortcutService service(settings);
        QWindow window;window.resize(400,200);window.show();window.requestActivate();QVERIFY(QTest::qWaitForWindowActive(&window));service.setWindow(&window);
        QSignalSpy actions(&service,&ShortcutService::activated);
        QTest::keyClick(&window,Qt::Key_F5,Qt::ControlModifier);QTRY_COMPARE(actions.count(),1);actions.clear();
        service.beginCapture(appNext);
        QTest::keyClick(&window,Qt::Key_F5,Qt::ControlModifier);QCOMPARE(actions.count(),0);QCOMPARE(service.recordingKey(),appNext);QCOMPARE(service.conflictKey(),appPlay);
        QTest::keyClick(&window,Qt::Key_F8,Qt::ControlModifier);QCOMPARE(service.binding(appNext),"Ctrl+F8");QVERIFY(service.recordingKey().isEmpty());QCOMPARE(actions.count(),0);
        QTest::keyClick(&window,Qt::Key_F8,Qt::ControlModifier);QTRY_COMPARE(actions.count(),1);QCOMPARE(actions.takeFirst().at(0).toString(),"next");
        service.beginCapture(appNext);QTest::keyClick(&window,Qt::Key_Control);QCOMPARE(service.recordingKey(),appNext);
        QTest::keyClick(&window,Qt::Key_Escape);QVERIFY(service.recordingKey().isEmpty());QCOMPARE(service.binding(appNext),"Ctrl+F8");
        service.beginCapture(appNext);QTest::mouseClick(&window,Qt::LeftButton);QVERIFY(service.recordingKey().isEmpty());
        service.beginCapture(appNext);QEvent deactivate(QEvent::WindowDeactivate);QApplication::sendEvent(&window,&deactivate);QVERIFY(service.recordingKey().isEmpty());
        QVERIFY(service.setEnabled("application",false));actions.clear();QTest::keyClick(&window,Qt::Key_F8,Qt::ControlModifier);QCOMPARE(actions.count(),0);
    }
    void registrationFailureKeepsOldBinding() {
        qmlbridge::SettingsController settings;ShortcutService service(settings);clearGlobals(service);
        QVERIFY(service.setBinding(globalPlay,"Ctrl+Alt+F9"));QVERIFY(service.setEnabled("global",true));
        QVERIFY(RegisterHotKey(nullptr,0x6a11,MOD_CONTROL|MOD_ALT|MOD_NOREPEAT,VK_F10));
        const bool changed=service.setBinding(globalPlay,"Ctrl+Alt+F10");
        UnregisterHotKey(nullptr,0x6a11);
        QVERIFY(!changed);QCOMPARE(service.binding(globalPlay),"Ctrl+Alt+F9");QVERIFY(service.enabled("global"));
        QVERIFY(!RegisterHotKey(nullptr,0x6a12,MOD_CONTROL|MOD_ALT,VK_F9));
        QSignalSpy actions(&service,&ShortcutService::activated);QVERIFY(ShortcutServiceTestAccess::post(service,"Ctrl+Alt+F9"));
        QTRY_COMPARE(actions.count(),1);
        QVERIFY(service.setEnabled("global",false));QVERIFY(RegisterHotKey(nullptr,0x6a12,MOD_CONTROL|MOD_ALT,VK_F9));UnregisterHotKey(nullptr,0x6a12);
    }
    void enableFailureRollsBackWholeGroup() {
        qmlbridge::SettingsController settings;ShortcutService service(settings);clearGlobals(service);
        QVERIFY(service.setBinding(globalPlay,"Ctrl+Alt+F9"));QVERIFY(service.setBinding(globalNext,"Ctrl+Alt+F10"));
        QVERIFY(RegisterHotKey(nullptr,0x6a13,MOD_CONTROL|MOD_ALT,VK_F9));
        const bool enabled=service.setEnabled("global",true);UnregisterHotKey(nullptr,0x6a13);
        QVERIFY(!enabled);QVERIFY(!service.enabled("global"));QVERIFY(!settings.value("shortcuts.global.enabled",false).toBool());
        QVERIFY(RegisterHotKey(nullptr,0x6a14,MOD_CONTROL|MOD_ALT,VK_F10));UnregisterHotKey(nullptr,0x6a14);
    }
    void nativeBackgroundAndScopePriority() {
        qmlbridge::SettingsController settings;ShortcutService service(settings);clearGlobals(service);
        QWindow window;window.resize(400,200);window.show();window.requestActivate();QVERIFY(QTest::qWaitForWindowActive(&window));service.setWindow(&window);
        QVERIFY(service.setBinding(globalPlay,"Ctrl+Alt+F9"));QVERIFY(service.setBinding(appNext,"Ctrl+Alt+F9"));QVERIFY(service.setEnabled("global",true));
        QSignalSpy actions(&service,&ShortcutService::activated);
        QVERIFY(ShortcutServiceTestAccess::post(service,"Ctrl+Alt+F9"));QTRY_COMPARE(actions.count(),1);QTest::qWait(100);QCOMPARE(actions.count(),1);QCOMPARE(actions.takeFirst().at(0).toString(),"next");
        service.beginCapture(appNext);QVERIFY(ShortcutServiceTestAccess::post(service,"Ctrl+Alt+F9"));QTRY_VERIFY(service.recordingKey().isEmpty());QCOMPARE(actions.count(),0);
        window.hide();QTRY_VERIFY(!window.isActive());QVERIFY(ShortcutServiceTestAccess::post(service,"Ctrl+Alt+F9"));QTRY_COMPARE(actions.count(),1);QCOMPARE(actions.takeFirst().at(0).toString(),"playPause");
    }
};
QTEST_MAIN(ShortcutTests)
#include "shortcut_tests.moc"
