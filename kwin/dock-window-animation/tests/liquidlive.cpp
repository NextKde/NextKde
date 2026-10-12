#include <QApplication>
#include <QWidget>
#include <QPainter>
#include <QIcon>
#include <QTimer>
#include <QElapsedTimer>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusUnixFileDescriptor>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QTemporaryFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDir>
#include <QFile>

class TestWindow : public QWidget {
    void paintEvent(QPaintEvent *) override {
        QPainter painter(this);
        painter.fillRect(rect(), QColor("#f7f2e9"));
        painter.fillRect(QRect(0, 0, width(), 90), QColor("#286f9d"));
        painter.setPen(Qt::white);
        QFont heading = font(); heading.setPixelSize(28); painter.setFont(heading);
        painter.drawText(QRect(30, 15, width()-60, 60), Qt::AlignVCenter, "KOS · Liquid animation live test");
        painter.setPen(QColor("#315464"));
        painter.drawText(QRect(45, 125, width()-90, 70), Qt::AlignVCenter, "Window → cached Dock icon");
        for (int i = 0; i < 5; ++i) painter.fillRect(QRect(45, 230+i*33, width()-90-i*50, 10), QColor("#ccdbdf"));
    }
};

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    const bool realDock = app.arguments().contains("--real-dock");
    QGuiApplication::setDesktopFileName(realDock ? "org.kde.dolphin" : "kos-liquid-test");
    const QString directory = qEnvironmentVariable("KOS_LIVE_OUTPUT");
    if (directory.isEmpty()) qFatal("KOS_LIVE_OUTPUT required");
    QDir().mkpath(directory);
    QIcon::setThemeName("breeze");
    TestWindow window;
    if (app.arguments().contains("--csd")) window.setWindowFlag(Qt::FramelessWindowHint);
    window.setWindowTitle("KOS liquid integration test");
    window.setWindowIcon(QIcon::fromTheme("org.kde.dolphin"));
    window.resize(820, 510); window.move(170, 75); window.show();
    QDBusInterface animation("org.kde.KWin", "/KOSDockWindowAnimation", "org.kos.KWin.DockWindowAnimation");
    QDBusInterface shots("org.kde.KWin", "/org/kde/KWin/ScreenShot2", "org.kde.KWin.ScreenShot2");
    int commandId = 0;
    auto setMinimized = [&](bool minimized) {
        const QString name = QString("kos-liquid-command-%1").arg(++commandId);
        const QString path = directory + "/" + name + ".js";
        QFile script(path);
        if (!script.open(QIODevice::WriteOnly)) qFatal("Cannot create window command");
        script.write(QString("const w=workspace.windowList().find(w=>w.caption==='KOS liquid integration test'); if(w) w.minimized=%1;")
            .arg(minimized ? "true" : "false").toUtf8());
        script.close();
        QDBusInterface scripting("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting");
        const auto loaded = scripting.call("loadScript", path, name);
        if (loaded.type() == QDBusMessage::ErrorMessage) qFatal("Cannot load window command");
        QDBusInterface instance("org.kde.KWin", "/Scripting/Script" + loaded.arguments().value(0).toString(), "org.kde.kwin.Script");
        const auto ran = instance.call("run");
        if (ran.type() == QDBusMessage::ErrorMessage) qFatal("Cannot run window command: %s", qPrintable(ran.errorMessage()));
    };
    QColor desktopSample;
    auto capture = [&](const QString &name) {
        if (qEnvironmentVariableIsSet("KOS_LIVE_NO_CAPTURE")) return;
        QTemporaryFile raw;
        if (!raw.open()) qFatal("Cannot create screenshot buffer");
        QVariantMap options{{"hide-caller-windows", false}, {"include-cursor", false}};
        const auto call = shots.asyncCall("CaptureArea", 0, 0, uint(1200), uint(800), options,
            QVariant::fromValue(QDBusUnixFileDescriptor(raw.handle())));
        QDBusPendingCallWatcher watcher(call);
        QEventLoop loop;
        QObject::connect(&watcher, &QDBusPendingCallWatcher::finished, &loop, &QEventLoop::quit);
        QTimer::singleShot(5000, &loop, &QEventLoop::quit);
        loop.exec();
        QDBusPendingReply<QVariantMap> reply = watcher;
        if (!reply.isFinished() || reply.isError()) qFatal("Screenshot failed: %s", qPrintable(reply.error().message()));
        const auto metadata = reply.value();
        const int width = metadata["width"].toInt(), height = metadata["height"].toInt();
        const int stride = metadata["stride"].toInt();
        // Screenshot metadata can arrive before the asynchronous FD writer
        // finishes. Wait for the raw buffer rather than consuming a partial frame.
        QElapsedTimer writer; writer.start();
        while (raw.size() < stride*height && writer.elapsed() < 3000) {
            QEventLoop wait; QTimer::singleShot(5, &wait, &QEventLoop::quit); wait.exec();
        }
        raw.seek(0); const QByteArray bytes = raw.readAll();
        if (bytes.size() < stride*height) qFatal("Incomplete screenshot: %lld of %d", qlonglong(bytes.size()), stride*height);
        QImage image(reinterpret_cast<const uchar *>(bytes.constData()), width, height, stride,
            QImage::Format(metadata["format"].toInt()));
        // A static calendar background lies outside the test window and its
        // flight envelope. Icon crossfade must not cull that desktop surface.
        if (realDock) {
            const QColor sample = image.pixelColor(50, 200);
            if (name == "start") desktopSample = sample;
            else if (name.startsWith("min-") && sample != desktopSample)
                qFatal("Icon handoff incorrectly occluded the desktop background");
        }
        if (!image.save(directory + "/" + name + ".png")) qFatal("Cannot save screenshot");
    };
    QTimer::singleShot(realDock ? 3500 : 900, &app, [&] {
        const auto before = animation.call("status");
        if (before.type() == QDBusMessage::ErrorMessage) qFatal("Animation effect not loaded");
        const QString payload = QString::fromUtf8(QJsonDocument(QJsonObject{{"targets", QJsonArray{
            QJsonObject{{"appId", "kos-liquid-test"}, {"x", 572}, {"y", 710}, {"width", 56}, {"height", 56},
                {"iconSource", "image://icon/org.kde.dolphin"}}}}}).toJson(QJsonDocument::Compact));
        if (!realDock) animation.call("updateTargets", payload);
        capture("start");
        setMinimized(true);
        QElapsedTimer timer; timer.start();
        for (int i=0; i<28; ++i) {
            QEventLoop wait; QTimer::singleShot(24, &wait, &QEventLoop::quit); wait.exec();
            capture(QString("min-%1-%2ms").arg(i, 2, 10, QLatin1Char('0')).arg(timer.elapsed()));
        }
        setMinimized(false);
        for (int i=0; i<22; ++i) {
            QEventLoop wait; QTimer::singleShot(24, &wait, &QEventLoop::quit); wait.exec();
            capture(QString("restore-%1").arg(i, 2, 10, QLatin1Char('0')));
        }
        // Reverse after the artwork takes over, exercising retained window
        // snapshots as well as the icon texture, then settle.
        setMinimized(true);
        QEventLoop wait; QTimer::singleShot(std::max(140, QJsonDocument::fromJson(before.arguments().value(0).toString().toUtf8()).object()["minimizeDuration"].toInt() * 3 / 4), &wait, &QEventLoop::quit); wait.exec();
        setMinimized(false);
        QEventLoop settle; QTimer::singleShot(1600, &settle, &QEventLoop::quit); settle.exec();
        capture("reversed");
        const auto after = animation.call("status");
        const auto status = QJsonDocument::fromJson(after.arguments().value(0).toString().toUtf8()).object();
        qInfo().noquote() << QJsonDocument(status).toJson(QJsonDocument::Compact);
        // Three independent transitions upload once each; reversing the third
        // must reuse its texture rather than performing a fourth upload.
        if (status["iconUploads"].toInt() != 3 || status["iconOnlyDraws"].toInt() < 1
            || status["liquidWindowDraws"].toInt() < 1 || status["animatingWindows"].toInt() != 0)
            qFatal("Liquid transition/cached-icon/reversal checks failed");
        // Destroy a source mid-flight, exercising visible refs, cached artwork
        // and appearance scene teardown while other KWin effects are active.
        setMinimized(true);
        QEventLoop flight; QTimer::singleShot(40, &flight, &QEventLoop::quit); flight.exec();
        window.close();
        QEventLoop closed; QTimer::singleShot(1400, &closed, &QEventLoop::quit); closed.exec();
        const auto finalStatus = animation.call("status");
        const auto finalObject = QJsonDocument::fromJson(finalStatus.arguments().value(0).toString().toUtf8()).object();
        if (finalStatus.type() == QDBusMessage::ErrorMessage || finalObject["animatingWindows"].toInt() != 0)
            qFatal("Destroying an animated source left a running animation");
        app.quit();
    });
    return app.exec();
}
