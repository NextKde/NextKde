#include "PlatformServer.h"
#include "../kwin/KWinBridge.h"

#include <QFile>
#include <QGuiApplication>
#include <QLoggingCategory>
#include <QTextStream>
#include <QTimer>

using namespace KosPlatform;

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    // KIO launch jobs may briefly create GUI-side startup-notification state.
    // This process is a session daemon, so its lifetime must never follow the
    // last-window lifecycle inherited from QGuiApplication.
    app.setQuitOnLastWindowClosed(false);
    QCoreApplication::setQuitLockEnabled(false);
    // The desktop file basename is the KGlobalAccel component identity: all
    // shell shortcuts register under this ONE component in the Shortcuts KCM.
    app.setApplicationName(QStringLiteral("kos-platform"));
    app.setDesktopFileName(QStringLiteral("org.kos.Platform"));

    const QStringList arguments = app.arguments();
    if (arguments.size() > 1 && arguments.at(1) != QStringLiteral("daemon")) {
        QTextStream(stderr) << "Usage: kos-platform daemon\n";
        return 2;
    }

    // ── 二进制被替换自检（v91）──
    // 部署流程替换二进制但本进程没有随之重启时，/proc/self/exe 指向
    // "(deleted)" 文件。KWin 的截图沙箱按 exe 路径匹配对应 .desktop 的
    // X-KDE-DBUS-Restricted-Interfaces 授权——该状态下所有窗口缩略图请求
    // 都会被拒（"The process is not authorized to take a screenshot"，
    // v91 实机实例：13 分钟内 97 次截图全部失败，台前侧栏卡片没有任何
    // 预览）。周期自检，发现被替换即非零退出——systemd（Restart=on-failure）
    // 拉起当前构建，授权随之恢复。
    auto *binaryWatch = new QTimer(&app);
    QObject::connect(binaryWatch, &QTimer::timeout, [] {
        const QString exe = QFile::symLinkTarget(QStringLiteral("/proc/self/exe"));
        if (exe.isEmpty() || !exe.contains(QLatin1String(" (deleted)")))
            return;
        QTextStream(stderr) << "kos-platform: binary was replaced under this"
                               " process (" << exe << ") — exiting so systemd"
                               " restarts the current build" << Qt::endl;
        QCoreApplication::exit(1);
    });
    binaryWatch->start(60000);

    PlatformServer server;
    if (!server.listen())
        return 1;

    startKWinBridge([&server](const QJsonObject &event) {
        server.broadcastKWinEvent(event);
    });

    QTextStream(stdout) << "READY " << server.socketPath() << Qt::endl;
    return app.exec();
}
