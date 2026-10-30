#include "PlatformServer.h"
#include "PlatformProcess.h"
#include "../windowanimation/NativeGenie.h"

#include <QByteArray>
#include <QDBusInterface>
#include <QList>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QStringList>
#include <functional>

namespace KosPlatform {
using namespace Detail;

void PlatformServer::applySystemTheme(QLocalSocket *socket,
                                      const QJsonObject &request, bool dark)
{
    const QString colorScheme = dark ? QStringLiteral("BreezeDark")
                                     : QStringLiteral("BreezeLight");
    const QString lookAndFeel = dark ? QStringLiteral("org.kde.breezedark.desktop")
                                     : QStringLiteral("org.kde.breeze.desktop");
    const QString applyColorScheme = QStandardPaths::findExecutable(
        QStringLiteral("plasma-apply-colorscheme"));
    const QString applyLookAndFeel = QStandardPaths::findExecutable(
        QStringLiteral("plasma-apply-lookandfeel"));

    QString program;
    QStringList arguments;
    QString method;
    if (!applyColorScheme.isEmpty()) {
        // A light/dark toggle only needs to change the palette. Applying a
        // complete Look-and-Feel package also replaces icons, cursors and
        // workspace defaults while Quickshell is rendering them, which can
        // tear down the Shell's platform connection mid-request.
        program = applyColorScheme;
        arguments = {colorScheme};
        method = QStringLiteral("colorScheme");
    } else if (!applyLookAndFeel.isEmpty()) {
        program = applyLookAndFeel;
        arguments = {QStringLiteral("--apply"), lookAndFeel};
        method = QStringLiteral("lookAndFeel");
    } else {
        respond(socket, request, false, {}, QStringLiteral("theme-apply-failed"),
                QStringLiteral("未找到可用的 KDE 明暗主题"), true);
        return;
    }

    runCommand(socket, request, program, arguments,
               [dark, colorScheme, lookAndFeel, method](const QByteArray &, int) {
        return QJsonObject{{QStringLiteral("dark"), dark},
                           {QStringLiteral("colorScheme"), colorScheme},
                           {QStringLiteral("lookAndFeel"), lookAndFeel},
                           {QStringLiteral("method"), method}};
    }, 30000);
}

bool PlatformServer::handleThemeOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    if (op == QStringLiteral("theme.reconfigure")) {
        QDBusInterface kwin(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
                            QStringLiteral("org.kde.KWin"));
        // Fire-and-forget: the reply is unused, so never block the loop.
        if (kwin.isValid())
            kwin.asyncCall(QStringLiteral("reconfigure"));
        respond(socket, request, true, QJsonObject{{QStringLiteral("reconfigured"), true}});
        return true;
    }
    if (op == QStringLiteral("theme.apply-system")) {
        const bool dark = payload.value(QStringLiteral("dark")).toBool();
        applySystemTheme(socket, request, dark);
        return true;
    }
    if (op == QStringLiteral("theme.sync-glass")) {
        const int contentBlur = qBound(1,
            payload.value(QStringLiteral("contentBlurLevel")).toInt(), 15);
        const int refraction = qBound(0,
            payload.value(QStringLiteral("refractionLevel")).toInt(), 20);
        const double refractionEdgeSize = qBound(0.0,
            payload.value(QStringLiteral("refractionEdgeSize")).toDouble(1.8), 50.0);
        const double refractionNormalPow = qBound(0.1,
            payload.value(QStringLiteral("refractionNormalPow")).toDouble(4.0), 10.0);
        const double refractionRGBFringing = qBound(0.0,
            payload.value(QStringLiteral("refractionRGBFringing")).toDouble(5.4), 20.0);
        const double refractionOffsetStrength = qBound(0.0,
            payload.value(QStringLiteral("refractionOffsetStrength")).toDouble(8.0), 20.0);
        const double materialSoftness = qBound(0.0,
            payload.value(QStringLiteral("materialSoftness")).toDouble(), 1.0);
        const double materialReflection = qBound(0.0,
            payload.value(QStringLiteral("materialReflectionStrength")).toDouble(), 1.0);
        const double cornerExponent = qBound(2.0,
            payload.value(QStringLiteral("cornerExponent")).toDouble(3.0), 8.0);
        const QString kwriteconfig = QStandardPaths::findExecutable(
            QStringLiteral("kwriteconfig6"));
        if (kwriteconfig.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("theme-unavailable"),
                    QStringLiteral("KDE 主题配置工具不可用"), false);
            return true;
        }
        const QList<QStringList> writes{
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("BlurStrength"), QString::number(contentBlur)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("RefractionStrength"), QString::number(refraction)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("RefractionEdgeSize"), QString::number(refractionEdgeSize, 'f', 3)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("RefractionNormalPow"), QString::number(refractionNormalPow, 'f', 3)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("RefractionRGBFringing"), QString::number(refractionRGBFringing, 'f', 3)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("RefractionOffsetStrength"), QString::number(refractionOffsetStrength, 'f', 3)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("MaterialSoftness"), QString::number(materialSoftness, 'f', 3)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("MaterialReflectionStrength"), QString::number(materialReflection, 'f', 3)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("CornerExponent"), QString::number(cornerExponent, 'f', 2)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blur"), QStringLiteral("--key"),
             QStringLiteral("BlurStrength"), QString::number(contentBlur)}};
        // QProcess::execute is waitForFinished(-1): a wedged kwriteconfig
        // would freeze the whole event loop. Run the writes as a watchdog-
        // armed async chain instead.
        const QPointer<QLocalSocket> guardedSocket(socket);
        auto pending = std::make_shared<QList<QStringList>>(writes.begin(), writes.end());
        auto step = std::make_shared<std::function<void()>>();
        // Weak capture: a strong step reference inside its own closure would
        // pin the whole chain alive forever.
        *step = [this, guardedSocket, request, kwriteconfig, pending,
                 weakStep = std::weak_ptr<std::function<void()>>(step)]() {
            const auto step = weakStep.lock();
            if (!step)
                return;
            if (pending->isEmpty()) {
                QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
                                       QStringLiteral("org.kde.kwin.Effects"));
                if (effects.isValid()) {
                    // Fire-and-forget reload notifications; replies unused.
                    effects.asyncCall(QStringLiteral("reconfigureEffect"), QStringLiteral("glass"));
                    effects.asyncCall(QStringLiteral("reconfigureEffect"), QStringLiteral("blur"));
                }
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("configured"), true},
                                    {QStringLiteral("kwinAvailable"), effects.isValid()}});
                return;
            }
            const QStringList arguments = pending->takeFirst();
            auto *process = new QProcess(this);
            process->setProgram(kwriteconfig);
            process->setArguments(arguments);
            armProcessWatchdog(process, 10000);
            connect(process, &QProcess::errorOccurred, this,
                    [this, guardedSocket, request, process](QProcess::ProcessError) {
                QObject::disconnect(process, &QProcess::finished, this, nullptr);
                respond(guardedSocket.data(), request, false, {},
                        QStringLiteral("theme-write-failed"),
                        QStringLiteral("无法保存玻璃特效配置"), true);
                process->deleteLater();
            });
            connect(process, &QProcess::finished, this,
                    [this, guardedSocket, request, process, step](int exitCode,
                                                                 QProcess::ExitStatus) {
                process->deleteLater();
                if (exitCode != 0) {
                    respond(guardedSocket.data(), request, false, {},
                            QStringLiteral("theme-write-failed"),
                            QStringLiteral("无法保存玻璃特效配置"), true);
                    return;
                }
                (*step)();
            });
            process->start();
        };
        (*step)();
        return true;
    }
    if (op == QStringLiteral("theme.sync-dock-animation")) {
        const QString style = payload.value(QStringLiteral("style")).toString();
        if (style != QStringLiteral("scale") && style != QStringLiteral("genie")) {
            respond(socket, request, false, {}, QStringLiteral("invalid-style"),
                    QStringLiteral("窗口动画样式无效"), false);
            return true;
        }
        const auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
        config->reparseConfiguration();
        KConfigGroup animation(config, QStringLiteral("Effect-kos_dock_window_animation"));
        // The legacy appearance preference must not overwrite the separate
        // window animation page's explicit selection on every Shell startup.
        animation.writeEntry("AnimationStyle", style);
        QString error;
        const bool saved = config->sync() && KOS::WindowAnimation::migrate(error);
        respond(socket, request, saved, QJsonObject{{QStringLiteral("configured"), saved}},
                saved ? QString() : QStringLiteral("theme-write-failed"), error, !saved);
        return true;
    }
    if (op == QStringLiteral("theme.toggle")) {
        const QString configPath = QStandardPaths::writableLocation(
            QStandardPaths::GenericConfigLocation) + QStringLiteral("/kdeglobals");
        QSettings settings(configPath, QSettings::IniFormat);
        QString scheme = settings.value(
            QStringLiteral("ColorScheme")).toString();
        if (scheme.isEmpty()) {
            scheme = settings.value(
                QStringLiteral("General/ColorScheme")).toString();
        }
        bool currentlyDark = scheme.contains(
            QStringLiteral("dark"), Qt::CaseInsensitive);
        if (!currentlyDark && scheme.isEmpty()) {
            const QStringList background = settings.value(
                QStringLiteral("Colors:Window/BackgroundNormal")).toStringList();
            if (background.size() >= 3) {
                const int red = background[0].toInt();
                const int green = background[1].toInt();
                const int blue = background[2].toInt();
                currentlyDark = (red * 299 + green * 587 + blue * 114) / 1000 < 128;
            }
        }
        applySystemTheme(socket, request, !currentlyDark);
        return true;
    }
    return false;
}

} // namespace KosPlatform
