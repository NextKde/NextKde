#include "networkview.h"
#include <QGuiApplication>
#include <QQuickWindow>
#include <QSurfaceFormat>
#include <QMouseEvent>
#include <QTimer>
#include <QImage>
#include <QWheelEvent>
#include <cmath>
#include <iostream>

int main(int argc, char **argv) {
    bool vulkan = false;
    bool scroll = false;
    int many = 0;
    bool churn = false;
    bool reorder = false;
    bool hover = false;
    for (int i = 1; i < argc; ++i) if (QByteArray(argv[i]) == "--vulkan") vulkan = true;
    for (int i = 1; i < argc; ++i) if (QByteArray(argv[i]) == "--scroll") scroll = true;
    for (int i = 1; i < argc; ++i) if (QByteArray(argv[i]) == "--churn") churn = true;
    for (int i = 1; i < argc; ++i) if (QByteArray(argv[i]) == "--reorder") reorder = true;
    for (int i = 1; i < argc; ++i) if (QByteArray(argv[i]) == "--hover") hover = true;
    for (int i = 1; i + 1 < argc; ++i) if (QByteArray(argv[i]) == "--many") many = QByteArray(argv[i + 1]).toInt();
    QQuickWindow::setGraphicsApi(vulkan ? QSGRendererInterface::Vulkan : QSGRendererInterface::OpenGL);
    QSurfaceFormat format;
    format.setVersion(3, 3); format.setProfile(QSurfaceFormat::CoreProfile);
    format.setRenderableType(QSurfaceFormat::OpenGL);
    QSurfaceFormat::setDefaultFormat(format);
    QGuiApplication app(argc, argv);
    QQuickWindow window;
    window.setTitle("NextKde · Forma native network verification");
    window.setFlags(Qt::Window | Qt::FramelessWindowHint);
    window.setColor(QColor("#565656")); window.resize(280, 900);
    NetworkView view(window.contentItem()); view.setSize({280,900});
    view.setDetailsExpanded(true);
    QVariantList down, up, connectivity, applications;
    for (int i = 0; i < 60; ++i) {
        down << (std::max(0.0, std::sin(i * .46)) * 1500000 + 20000);
        up << (i % 11 == 3 ? 2400000 : 20000);
    }
    for (int i = 0; i < 90; ++i) connectivity << true;
    if (many > 0) {
        for (int i = 0; i < many; ++i) {
            QVariantMap row{{"name", QStringLiteral("Process %1").arg(i)}, {"download", 1024.0 * i}, {"upload", 17408.0 * i}};
            QImage image(32, 32, QImage::Format_RGBA8888);
            image.fill(QColor::fromHsv((i * 37) % 360, 180, 220));
            row.insert("iconImage", image);
            applications << row;
        }
    } else {
        for (const auto &name : {"kernel_task", "Stocks", "Time Machine", "Chess", "Dictionary", "Font Book", "Image Capture", "Calculator"})
            applications << QVariantMap{{"name", name}, {"download", 1024}, {"upload", 17408}};
        QImage icon(32, 32, QImage::Format_RGBA8888);
        icon.fill(QColor("#0099ff"));
        auto first = applications[0].toMap(); first.insert("iconImage", icon); applications[0] = first;
    }
    auto makeSnapshot = [&](int tick) {
        return QVariantMap{{"connected", true}, {"connectivity", "full"},
            {"download", 20480.0 + tick * 1024}, {"upload", 20480.0 + tick * 512}, {"totalUpload", 1.05 * std::pow(1024,4) + tick * 4096},
            {"totalDownload", 1.32 * std::pow(1024,4) + tick * 8192}, {"interface", "Wi-Fi (wlan0)"},
            {"network", "Home Wi-Fi (-52)"}, {"macAddress", "a4:83:e7:2b:9c:1d"}, {"localIp", "192.168.1.42"},
            {"downloadHistory", down}, {"uploadHistory", up}, {"connectivityHistory", connectivity}, {"applications", applications}};
    };
    view.setSnapshot(makeSnapshot(0));
    QTimer *churnTimer = nullptr;
    if (churn) {
        auto *timer = new QTimer(&app);
        churnTimer = timer;
        int tick = 1;
        QObject::connect(timer, &QTimer::timeout, &app, [&, tick]() mutable {
            if (reorder && applications.size() > 1) {
                applications.move(0, applications.size() - 1);
                for (int i = 0; i < applications.size(); ++i) {
                    auto row = applications[i].toMap();
                    row.insert("download", 1024.0 * (i + 1) * (tick % 7 + 1));
                    row.insert("upload", 17408.0 * (i + 1));
                    applications[i] = row;
                }
            }
            view.setSnapshot(makeSnapshot(tick++));
        });
        timer->start(100);
    }
    int closes = 0;
    QObject::connect(&view, &NetworkView::closeRequested, &app, [&] { ++closes; });
    window.show();
    QTimer::singleShot(300, &app, [&] {
        QMouseEvent press(QEvent::MouseButtonPress, QPointF(261,21), QPointF(261,21), Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        QMouseEvent release(QEvent::MouseButtonRelease, QPointF(261,21), QPointF(261,21), Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(&view, &press); QCoreApplication::sendEvent(&view, &release);
    });
    QTimer::singleShot(1200, &app, [&] {
        const auto expected = QSize(qRound(280 * window.devicePixelRatio()), qRound(900 * window.devicePixelRatio()));
        if (view.renderedPixelSize() != expected) qFatal("Forma render target is not native DPR");
        if (view.nativeComponentCount() < 100) qFatal("Forma component tree was not constructed");
        if (closes != 1) qFatal("Qt input did not reach original Forma Button");
        const auto image = window.grabWindow();
        // The scene switches glyph/image textures near the first process row.
        // A later batch must preserve the dashboard and both graph halves.
        const qreal scale = qreal(image.width()) / 280;
        int redPixels = 0, bluePixels = 0;
        for (int y = qRound(162 * scale); y < qRound(252 * scale); ++y) {
            for (int x = qRound(8 * scale); x < qRound(272 * scale); ++x) {
                const auto c = image.pixelColor(x, y);
                if (c.red() > c.green() + 40 && c.red() > c.blue() + 40) ++redPixels;
                if (c.blue() > c.red() + 40 && c.blue() > c.green() + 20) ++bluePixels;
            }
        }
        if (redPixels < 100 || bluePixels < 100) qFatal("A later native image batch erased the traffic chart");
        const auto output = qEnvironmentVariable("KOS_FORMA_CAPTURE", "forma-network.png");
        if (image.isNull() || !image.save(output)) qFatal("Cannot capture native network panel");
        std::cout << "PASS " << (vulkan ? "Vulkan" : "OpenGL") << " threaded native Forma components=" << view.nativeComponentCount()
                  << " target=" << expected.width() << "x" << expected.height() << " button=1 screenshot=" << output.toStdString() << std::endl;
    });
    if (scroll) {
        QTimer::singleShot(1500, &app, [&] {
            QWheelEvent wheel({140,750}, {140,750}, {0,-120}, {}, Qt::NoButton, Qt::NoModifier, Qt::ScrollUpdate, false);
            QWheelEvent end({140,750}, {140,750}, {}, {}, Qt::NoButton, Qt::NoModifier, Qt::ScrollEnd, false);
            QCoreApplication::sendEvent(&view, &wheel); QCoreApplication::sendEvent(&view, &end);
        });
        QTimer::singleShot(2000, &app, [&] {
            if (view.scrollOffset() <= 0) qFatal("Qt wheel did not reach the original Forma ScrollView");
            std::cout << "PASS original Forma ScrollView wheel offset=" << view.scrollOffset() << std::endl;
        });
    }
    QTimer idle;
    idle.setInterval(200);
    int previousFrames = -1, quietSamples = 0;
    QObject::connect(&idle, &QTimer::timeout, &app, [&] {
        const int frames = view.renderedFrames();
        quietSamples = frames == previousFrames ? quietSamples + 1 : 0;
        previousFrames = frames;
        if (quietSamples == 3 && !churn) {
            std::cout << "PASS idle frames stopped at " << frames << std::endl; app.quit();
        }
    });
    if (hover) {
        // Pointer movement over inert content must not damage the popup surface;
        // entering a control must still repaint so hover feedback is unchanged.
        QTimer::singleShot(1400, &app, [&, churnTimer] {
            // A snapshot update in the measurement window would legitimately
            // repaint; stop the feed so the assertion measures hover only.
            if (churnTimer) churnTimer->stop();
            const int before = view.renderedFrames();
            for (int i = 0; i < 40; ++i) {
                const QPointF p(120 + i % 3, 420 + i * 6);
                QHoverEvent move(QEvent::HoverMove, p, p, p);
                QCoreApplication::sendEvent(&view, &move);
            }
            QTimer::singleShot(300, &app, [&, before] {
                const int inert = view.renderedFrames() - before;
                if (inert > 2) qFatal("Hover over inert content still repaints the popup");
                const int beforeButton = view.renderedFrames();
                const QPointF p(261, 21);
                QHoverEvent overButton(QEvent::HoverMove, p, p, p);
                QCoreApplication::sendEvent(&view, &overButton);
                QTimer::singleShot(300, &app, [&, beforeButton, inert] {
                    if (view.renderedFrames() <= beforeButton) qFatal("Hover over a control did not repaint");
                    std::cout << "PASS hover gating inert=" << inert
                              << " control=" << view.renderedFrames() - beforeButton << std::endl;
                });
            });
        });
    }
    QTimer::singleShot(hover ? 2600 : scroll ? 5000 : 1400, &idle, [&] { idle.start(); });
    if (churn) QTimer::singleShot(6000, &app, [&] { std::cout << "PASS churn frames=" << view.renderedFrames() << std::endl; app.quit(); });
    else QTimer::singleShot(10000, &app, [] { qFatal("Idle native network panel keeps rendering"); });
    return app.exec();
}
