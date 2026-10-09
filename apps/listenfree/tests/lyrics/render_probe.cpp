// Offscreen GPU validation following Qt's QQuickRenderControl lifecycle.
// This measures a fixed texture-rendered scene, not display/vsync FPS.
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlDebuggingEnabler>
#include <QQuickItem>
#include <QQuickWindow>
#include <QQuickRenderControl>
#include <QQuickGraphicsConfiguration>
#include <QQuickRenderTarget>
#include <QElapsedTimer>
#include <QAnimationDriver>
#include <QTimer>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <QDir>
#include <rhi/qrhi.h>
#include <memory>
#include <algorithm>
#include "spring_value.h"
#include "lyric_text_metrics.h"
#ifdef Q_OS_WIN
#include <windows.h>
#include <psapi.h>
#endif

// The stepping pattern follows Qt's QQuickRenderControl RHI example:
// https://doc.qt.io/qt-6/qtquick-rendercontrol-rendercontrol-rhi-example.html
// Capture mode advances media/animation time together, independent of PNG I/O.
class CaptureClock : public QAnimationDriver {
    int frame_ = 0;
public:
    void advance() override { ++frame_; advanceAnimation(); }
    qint64 elapsed() const override { return qRound64(frame_*1000./60); }
};

QJsonObject processStats() {
    QJsonObject result;
#ifdef Q_OS_WIN
    PROCESS_MEMORY_COUNTERS_EX m{};
    GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&m), sizeof(m));
    result["privateBytes"] = double(m.PrivateUsage);
    result["workingSetBytes"] = double(m.WorkingSetSize);
    FILETIME created{}, exited{}, kernel{}, user{};
    GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user);
    const auto ticks = [](FILETIME t) { return (quint64(t.dwHighDateTime) << 32) | t.dwLowDateTime; };
    result["cpuMs"] = double(ticks(kernel)+ticks(user))/10000.;
    result["userCpuMs"] = double(ticks(user))/10000.;
    result["kernelCpuMs"] = double(ticks(kernel))/10000.;
    GetThreadTimes(GetCurrentThread(), &created, &exited, &kernel, &user);
    result["guiThreadCpuMs"] = double(ticks(kernel)+ticks(user))/10000.;
    ULONG64 cycles = 0;
    if (QueryThreadCycleTime(GetCurrentThread(), &cycles)) result["guiThreadCycles"] = double(cycles);
    if (QueryProcessCycleTime(GetCurrentProcess(), &cycles)) result["processCycles"] = double(cycles);
    DWORD_PTR processMask = 0, systemMask = 0;
    if (GetProcessAffinityMask(GetCurrentProcess(), &processMask, &systemMask))
        result["affinityMask"] = QString::number(qulonglong(processMask),16);
#endif
    return result;
}

int main(int argc, char** argv) {
    if (qEnvironmentVariableIsSet("LISTENFREE_LYRIC_QML_PROFILE")) QQmlDebuggingEnabler::enableDebugging(false);
    QGuiApplication app(argc, argv);
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);
    qmlRegisterType<listenfree::qmlbridge::SpringValue>("ListenFree.Native",1,0,"SpringValue");
    qmlRegisterType<listenfree::qmlbridge::LyricTextMetrics>("ListenFree.Native",1,0,"LyricTextMetrics");
    QQuickRenderControl control;
    QQuickWindow window(&control);
    QQuickGraphicsConfiguration graphics;
    graphics.setTimestamps(true);
    window.setGraphicsConfiguration(graphics);
    window.setGeometry(0,0,960,760);
    if (!control.initialize()) return 2;
    auto* rhi = control.rhi();
    const bool captureMotion = app.arguments().contains("--capture-motion");
    const bool wordReference = app.arguments().contains("--word-reference");
    std::unique_ptr<CaptureClock> captureClock;
    if (captureMotion) { captureClock = std::make_unique<CaptureClock>(); captureClock->install(); }
    std::unique_ptr<QRhiTexture> texture(rhi->newTexture(QRhiTexture::RGBA8, {960,760}, 1,
        QRhiTexture::RenderTarget | QRhiTexture::UsedAsTransferSource));
    if (!texture->create()) return 3;
    std::unique_ptr<QRhiTextureRenderTarget> target(rhi->newTextureRenderTarget({texture.get()}));
    std::unique_ptr<QRhiRenderPassDescriptor> pass(target->newCompatibleRenderPassDescriptor());
    target->setRenderPassDescriptor(pass.get());
    if (!target->create()) return 4;
    window.setRenderTarget(QQuickRenderTarget::fromRhiRenderTarget(target.get()));
    QQmlEngine engine;
    QQmlComponent component(&engine, QUrl::fromLocalFile(QDir::current().absoluteFilePath("scene.qml")));
    std::unique_ptr<QObject> object(component.create());
    auto* scene = qobject_cast<QQuickItem*>(object.get());
    if (!scene) { qWarning() << component.errors(); return 5; }
    scene->setParentItem(window.contentItem());
    auto* panel = scene->findChild<QQuickItem*>("probeLyrics");
    if (!panel) return 6;
    if (captureMotion) {
        if (!QDir().mkpath("motion")) return 7;
        QMetaObject::invokeMethod(scene,wordReference ? "prepareWordReferenceCapture" : "prepareMotionCapture");
    }
    QJsonArray samples;
    QJsonArray motionStates;
    int frames = 0, phase = 0, capturePhase = 0;
    qint64 lastMedia = -100;
    QElapsedTimer clock;
    clock.start();
    QVector<double> renderTimes;
    QVector<double> gpuTimes;
    auto sample = [&](const char* name) {
        auto row = processStats();
        row["phase"] = name;
        row["wallMs"] = double(clock.elapsed());
        row["renderedFrames"] = frames;
        const auto usage = rhi->statistics().totalUsageBytes;
        row["rhiUsageBytes"] = usage ? QJsonValue(double(usage)) : QJsonValue(QJsonValue::Null);
        QVariant counts;
        QMetaObject::invokeMethod(scene, "effectCounts", Q_RETURN_ARG(QVariant, counts));
        row["effects"] = QJsonDocument::fromJson(counts.toString().toUtf8()).object();
        samples.append(row);
    };
    auto render = [&](const QString& file = {}) {
        QElapsedTimer work;
        work.start();
        control.polishItems();
        control.beginFrame();
        control.sync();
        control.render();
        QRhiReadbackResult readback;
        if (!file.isEmpty()) {
            auto* updates = rhi->nextResourceUpdateBatch();
            updates->readBackTexture(QRhiReadbackDescription(texture.get()), &readback);
            control.commandBuffer()->resourceUpdate(updates);
        }
        auto* commands = control.commandBuffer();
        control.endFrame();
        ++frames;
        if (phase == 3) {
            renderTimes.append(double(work.nsecsElapsed())/1e6);
            // Qt's offscreen endFrame already completes the submission. Read
            // its timestamp afterward; this adds no explicit GPU wait.
            const double gpuSeconds = commands->lastCompletedGpuTime();
            if (gpuSeconds > 0) gpuTimes.append(gpuSeconds*1000.);
        }
        if (!file.isEmpty()) {
            rhi->finish();
            QImage pixels(reinterpret_cast<const uchar*>(readback.data.constData()),
                readback.pixelSize.width(), readback.pixelSize.height(), QImage::Format_RGBA8888);
            if (pixels.isNull() || !pixels.save(file,"PNG",captureMotion ? 80 : -1)) qFatal("GPU readback failed");
            int brightPixels = 0;
            for (int y=0; y<pixels.height(); y+=4)
                for (int x=0; x<pixels.width(); x+=4)
                    if (qGray(pixels.pixel(x,y))>150) ++brightPixels;
            if (brightPixels<6) qFatal("GPU readback contains no visible lyrics");
        }
    };
    QTimer timer;
    timer.setInterval(captureMotion ? 0 : 16);
    timer.setTimerType(Qt::PreciseTimer);
    QObject::connect(&timer, &QTimer::timeout, &app, [&] {
        if (captureMotion) {
            // One second of unrecorded settling, then nine seconds at 60 samples/s.
            const int captureFrame=frames-60;
            if (captureFrame>=540) {
                const QJsonObject report{{"mode","Deterministic GPU motion capture; not measured display FPS"},
                    {"fps",60},{"frames",540},{"width",960},{"height",760},
                    {"fixture",wordReference ? "word-reference" : "motion"},
                    {"device",QString::fromUtf8(rhi->driverInfo().deviceName)}};
                QFile out("motion.json");
                if (!out.open(QIODevice::WriteOnly)) qFatal("Cannot write capture report");
                out.write(QJsonDocument(report).toJson());
                QFile states("motion-state.json");
                if (!states.open(QIODevice::WriteOnly)) qFatal("Cannot write frame diagnostics");
                states.write(QJsonDocument(motionStates).toJson(QJsonDocument::Compact));
                timer.stop(); app.quit(); return;
            }
            const double position=80000+qRound64(std::max(0,captureFrame)*1000./60);
            panel->setProperty("positionMs",position);
            panel->setProperty("currentLineIndex",int(position/4000));
            captureClock->advance();
            panel->setProperty("renderPositionMs",position);
            render(captureFrame<0 ? QString{} : QString("motion/frame-%1.png").arg(captureFrame,5,10,QChar('0')));
            if (captureFrame>=0) {
                QVariant state;
                QMetaObject::invokeMethod(scene,"captureState",Q_RETURN_ARG(QVariant,state));
                motionStates.append(QJsonDocument::fromJson(state.toString().toUtf8()).object());
            }
            return;
        }
        const auto t = clock.elapsed();
        if (t>=1200 && phase==0) { render("lyrics-still.png"); sample("paused"); phase=1; }
        if (t>=1400 && capturePhase==0) { panel->setProperty("positionMs",80500.); capturePhase=1; }
        if (t>=1600 && capturePhase==1) { render("short-word.png"); panel->setProperty("positionMs",83400.); capturePhase=2; }
        if (t>=1800 && capturePhase==2) { render("long-word.png"); capturePhase=3; }
        if (t>=2000 && phase==1) { panel->setProperty("playing",true); phase=2; }
        if (phase>=2 && phase<=3 && t-lastMedia>=100) {
            const qint64 position = 80000+t-2000;
            panel->setProperty("positionMs",double(position));
            panel->setProperty("currentLineIndex",int(position/4000));
            lastMedia=t;
        }
        if (t>=5000 && phase==2) { sample("playing-start"); phase=3; }
        if (t>=17000 && phase==3) {
            sample("playing-end"); phase=4;
            panel->setProperty("playing",false);
            panel->setProperty("animationActive",false);
            panel->setVisible(false);
        }
        if (t>=18000 && phase==4) { sample("hidden"); panel->setVisible(true); panel->setProperty("animationActive",true); phase=5; }
        if (t>=19000 && phase==5) {
            sample("returned");
            std::sort(renderTimes.begin(), renderTimes.end());
            std::sort(gpuTimes.begin(), gpuTimes.end());
            QJsonObject report{{"mode","QQuickRenderControl / Direct3D11 / 960x760 / 16ms pump"},
                {"platform",QGuiApplication::platformName()}, {"samples",samples},
                {"device",QString::fromUtf8(rhi->driverInfo().deviceName)},
                {"renderP50Ms",renderTimes[renderTimes.size()/2]}, {"renderP95Ms",renderTimes[renderTimes.size()*95/100]},
                {"gpuTimestampSupported",rhi->isFeatureSupported(QRhi::Timestamps)},
                {"gpuSamples",gpuTimes.size()},
                {"gpuP50Ms",gpuTimes.isEmpty() ? QJsonValue(QJsonValue::Null) : QJsonValue(gpuTimes[gpuTimes.size()/2])},
                {"gpuP95Ms",gpuTimes.isEmpty() ? QJsonValue(QJsonValue::Null) : QJsonValue(gpuTimes[gpuTimes.size()*95/100])}};
            QFile out("result.json");
            if (!out.open(QIODevice::WriteOnly)) qFatal("Cannot write benchmark result");
            out.write(QJsonDocument(report).toJson());
            timer.stop(); app.quit(); return;
        }
        render();
    });
    timer.start();
    const int code=app.exec();
    scene->setParentItem(nullptr);
    object.reset();
    rhi->finish();
    window.setRenderTarget({});
    target.reset(); pass.reset(); texture.reset();
    control.invalidate();
    return code;
}
