#include "LockScreenSettings.h"
#include <KConfig>
#include <KConfigGroup>
#include <QDBusConnection>
#include <QDir>
#include <QFile>
#include <QImage>
#include <QLockFile>
#include <QRandomGenerator>
#include <QTemporaryDir>
#include <QtTest>

namespace {
void write(const QString &name, const QByteArray &bytes) {
    QVERIFY(QDir().mkpath(QFileInfo(name).absolutePath()));
    QFile file(name);
    QVERIFY(file.open(QIODevice::WriteOnly));
    QCOMPARE(file.write(bytes), bytes.size());
}
QByteArray read(const QString &name) {
    QFile file(name);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}
void package(const QString &path, const QByteArray &skin = "import QtQuick\nItem {}\n") {
    write(path + "/metadata.json", R"({"KPlugin":{"Id":"org.kos.desktop"},"X-Plasma-APIVersion":"2"})");
    write(path + "/contents/defaults", "[Desktop]\nContainment=org.kde.desktopcontainment\n");
    write(path + "/contents/lockscreen/LockScreen.qml", skin);
    write(path + "/contents/lockscreen/.kos-lockscreen", "KOS lockscreen v1\n");
}
}
class ScreenSaver final : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.ScreenSaver")
public:
    int calls = 0;
public slots:
    void Lock() { ++calls; }
};
class LockScreenTest final : public QObject {
    Q_OBJECT
    QTemporaryDir temp;
    LockScreenSettings::Paths paths;
    QString source, shell;
private slots:
    void init() {
        const QString root = temp.path() + '/' + QString::number(QRandomGenerator::global()->generate64());
        paths = {root + "/config", root + "/data", root + "/data/kos/lockscreen"};
        source = root + "/source";
        shell = paths.data + "/plasma/shells/org.kos.desktop";
        package(source);
        write(paths.config + "/plasmashellrc", "[Shell]\nShellPackage=org.kos.desktop\nKeep=untouched\n");
    }
    void configurationContract() {
        write(paths.config + "/kscreenlockerrc", "[Daemon]\nAutolock=false\nTimeout=91\nUnknownDaemon=keep\n\n[Greeter]\nUnknown=keep\n\n[Greeter][LnF][General]\nOtherSetting=kept\n\n[Other]\nValue=keep\n");
        const auto plasma = read(paths.config + "/plasmashellrc");
        LockScreenSettings settings(paths);
        QVERIFY(settings.state()["showMediaControls"].toBool());
        QVERIFY(!settings.state()["kosShowNotifications"].toBool());
        QImage image(12, 12, QImage::Format_RGB32);
        image.fill(Qt::blue);
        const QString wallpaper = temp.path() + "/wallpaper #1.png";
        QVERIFY(image.save(wallpaper));
        QVERIFY(settings.setWallpaper(QUrl::fromLocalFile(wallpaper).toString()));
        QVERIFY(settings.setShowMediaControls(false));
        QVERIFY(settings.setShowNotifications(true));
        KConfig config(paths.config + "/kscreenlockerrc", KConfig::SimpleConfig);
        auto daemon = KConfigGroup(&config, "Daemon");
        QCOMPARE(daemon.readEntry("Timeout", 0), 91);
        QCOMPARE(daemon.readEntry("UnknownDaemon", QString()), "keep");
        QVERIFY(!daemon.readEntry("Autolock", true));
        auto greeter = KConfigGroup(&config, "Greeter");
        QCOMPARE(greeter.readEntry("WallpaperPlugin", QString()), "org.kde.image");
        QCOMPARE(greeter.readEntry("Unknown", QString()), "keep");
        auto general = greeter.group("Wallpaper").group("org.kde.image").group("General");
        QCOMPARE(general.readEntry("Image", QString()), QUrl::fromLocalFile(wallpaper).toString());
        QCOMPARE(general.readEntry("PreviewImage", QString()), general.readEntry("Image", QString()));
        auto appearance = greeter.group("LnF").group("General");
        QVERIFY(!appearance.readEntry("showMediaControls", true));
        QVERIFY(appearance.readEntry("kosShowNotifications", false));
        QVERIFY(!appearance.hasKey("kosShowNotificationBody"));
        QCOMPARE(appearance.readEntry("OtherSetting", QString()), "kept");
        QCOMPARE(KConfigGroup(&config, "Other").readEntry("Value", QString()), "keep");
        QCOMPARE(read(paths.config + "/plasmashellrc"), plasma);
        const auto before = read(paths.config + "/kscreenlockerrc");
        QVERIFY(!settings.setWallpaper("https://example.com/wallpaper.png"));
        QVERIFY(!settings.setWallpaper(source + "/metadata.json"));
        QCOMPARE(read(paths.config + "/kscreenlockerrc"), before);
    }
    void lifecycleAndUpgrade() {
        LockScreenSettings settings(paths);
        QVERIFY(!settings.state()["available"].toBool());
        QVERIFY(settings.installShellPackage(source));
        QVERIFY(settings.state()["available"].toBool());
        QVERIFY(!settings.state()["installed"].toBool());
        QVERIFY(!QFileInfo::exists(shell + "/contents/lockscreen"));
        const auto plasma = read(paths.config + "/plasmashellrc");
        const auto defaults = read(shell + "/contents/defaults");
        QVERIFY(settings.setTheme("kos"));
        QVERIFY(settings.state()["active"].toBool());
        QVERIFY(settings.state()["installed"].toBool());
        package(source, "// new revision\nimport QtQuick\nItem {}\n");
        QVERIFY(settings.installShellPackage(source));
        QVERIFY(settings.state()["active"].toBool());
        QVERIFY(read(shell + "/contents/lockscreen/LockScreen.qml").startsWith("// new revision"));
        QVERIFY(settings.setTheme("system"));
        QVERIFY(settings.setTheme("system"));
        QVERIFY(!QFileInfo::exists(shell + "/contents/lockscreen"));
        QCOMPARE(read(shell + "/contents/defaults"), defaults);
        QVERIFY(settings.installShellPackage(source));
        QVERIFY(!QFileInfo::exists(shell + "/contents/lockscreen"));
        // Installed resources work after moving/removing the checkout.
        QVERIFY(QDir(source).removeRecursively());
        QVERIFY(settings.setTheme("kos"));
        QCOMPARE(read(paths.config + "/plasmashellrc"), plasma);
        QVERIFY(!QFileInfo::exists(paths.config + "/kscreenlockerrc"));
    }
    void guardsAndFailureRetention() {
        LockScreenSettings settings(paths);
        QVERIFY(settings.installShellPackage(source));
        QVERIFY(settings.setTheme("kos"));
        const auto old = read(shell + "/contents/lockscreen/LockScreen.qml");
        write(paths.config + "/plasmashellrc", "[Shell]\nShellPackage=other.desktop\n");
        QVERIFY(settings.state()["installed"].toBool());
        QVERIFY(!settings.state()["active"].toBool());
        QVERIFY(!settings.setTheme("system"));
        QVERIFY(!settings.setTheme("kos"));
        QCOMPARE(read(shell + "/contents/lockscreen/LockScreen.qml"), old);
        write(paths.config + "/plasmashellrc", "[Shell]\nShellPackage=org.kos.desktop\n");
        QVERIFY(!settings.setTheme("unknown"));
        QLockFile lock(paths.data + "/kos/lockscreen-theme.lock");
        QVERIFY(lock.tryLock());
        QVERIFY(!settings.setTheme("system"));
        QVERIFY(!settings.installShellPackage(source));
        lock.unlock();
        // Broken stable source, unknown replacement and failed staging all keep
        // the original usable entry instead of deleting it before copying.
        QVERIFY(QFile::remove(paths.resources + "/contents/lockscreen/LockScreen.qml"));
        QVERIFY(!settings.setTheme("kos"));
        QCOMPARE(read(shell + "/contents/lockscreen/LockScreen.qml"), old);
        QVERIFY(QFile::remove(shell + "/contents/lockscreen/.kos-lockscreen"));
        QVERIFY(!settings.setTheme("system"));
        QVERIFY(!settings.installShellPackage(source));
        QCOMPARE(read(shell + "/contents/lockscreen/LockScreen.qml"), old);
        write(shell + "/contents/lockscreen/.kos-lockscreen", "KOS lockscreen v1\n");
        QVERIFY(settings.installShellPackage(source));
        QVERIFY(QFile::setPermissions(shell + "/contents", QFileDevice::ReadOwner | QFileDevice::ExeOwner));
        QVERIFY(!settings.setTheme("kos"));
        QCOMPARE(read(shell + "/contents/lockscreen/LockScreen.qml"), old);
        QVERIFY(QFile::setPermissions(shell + "/contents", QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner));
    }
    void symlinkBoundaries() {
        LockScreenSettings settings(paths);
        QVERIFY(settings.installShellPackage(source));
        QVERIFY(settings.setTheme("kos"));
        const QString external = temp.path() + "/external";
        write(external + "/sentinel", "not yours\n");
        QVERIFY(QFile::link(external, paths.resources + "/contents/lockscreen/escape"));
        QVERIFY(!settings.setTheme("kos"));
        QVERIFY(QFile::remove(paths.resources + "/contents/lockscreen/escape"));
        QVERIFY(QDir().rename(shell + "/contents", shell + "/saved-contents"));
        QVERIFY(QFile::link(shell + "/saved-contents", shell + "/contents"));
        QVERIFY(!settings.setTheme("system"));
        QVERIFY(!settings.installShellPackage(source));
        QCOMPARE(read(external + "/sentinel"), "not yours\n");
        QVERIFY(QFile::link(external + "/sentinel", paths.config + "/kscreenlockerrc"));
        QVERIFY(!settings.setShowNotifications(true));
        QCOMPARE(read(external + "/sentinel"), "not yours\n");
    }
    void explicitLockOnly() {
        auto bus = QDBusConnection::sessionBus();
        QVERIFY(bus.isConnected());
        ScreenSaver saver;
        QVERIFY(bus.registerService("org.freedesktop.ScreenSaver"));
        QVERIFY(bus.registerObject("/ScreenSaver", &saver, QDBusConnection::ExportAllSlots));
        LockScreenSettings settings(paths);
        settings.refresh();
        settings.state();
        QVERIFY(settings.setShowMediaControls(false));
        QTest::qWait(20);
        QCOMPARE(saver.calls, 0);
        settings.lockNow();
        QTRY_COMPARE(saver.calls, 1);
        bus.unregisterObject("/ScreenSaver");
        bus.unregisterService("org.freedesktop.ScreenSaver");
    }
};
QTEST_GUILESS_MAIN(LockScreenTest)
#include "backend.moc"
