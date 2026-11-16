// Asset production: export the same QML used by the desktop to PNG.
// This executable is never used by the settings or preview grids.
#include <QGuiApplication>
#include <QImage>
#include <QQuickView>
#include <QTimer>
#include <QUrl>
#include <QVariant>
#include <cstdio>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc != 4) {
        std::fprintf(stderr, "Usage: export-theme-thumbnails SCENE.qml THEME OUTPUT.png\n");
        return 2;
    }
    QQuickView view;
    view.setTitle(QStringLiteral("Wallpaper thumbnail export: ") + QString::fromLocal8Bit(argv[2]));
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.resize(960, 540);
    view.setInitialProperties({{"themeId", QString::fromLocal8Bit(argv[2])},
                               {"phase", 6.0}, {"economical", false}});
    view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if (view.status() != QQuickView::Ready)
        return 3;
    view.show();
    // Allow the initial background and recursive particle textures to settle.
    QTimer::singleShot(1500, &app, [&] {
        if (!view.isSceneGraphInitialized()) {
            std::fprintf(stderr, "No scene graph: export needs a GPU-backed Qt window.\n");
            app.exit(4);
            return;
        }
        const QImage frame = view.grabWindow();
        const QImage thumbnail = frame.scaled(960, 540, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        app.exit(!thumbnail.isNull() && thumbnail.save(QString::fromLocal8Bit(argv[3])) ? 0 : 4);
    });
    QTimer::singleShot(15000, &app, [&] { app.exit(5); });
    return app.exec();
}
