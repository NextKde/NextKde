// Acceptance probe for the Apple Music dynamic artwork pipeline (Phase 2.1,
// setting O-14). Runs the ported fetch chain against the real APIs and prints
// [appleDynamicCover] logs; exit code 0 when a playable HLS variant was
// resolved. Playback load (QMediaPlayer) is exercised with --play.
//
// Usage:
//   listenfree-apple-cover-probe [--play] [--title NAME] [--artist NAME] [--album NAME]

#include "online/apple_dynamic_artwork_provider.h"

#include <QCoreApplication>
#include <QDebug>
#include <QAudioOutput>
#include <QMediaPlayer>
#include <QNetworkProxy>
#include <QTimer>

#include <cstdio>
#include <cstdlib>

namespace {
// Qt may route logs to the Windows debugger instead of stderr; the probe
// requires visible log lines as acceptance evidence, so force stderr output.
void stderrLogger(QtMsgType type, const QMessageLogContext& context, const QString& message) {
    const char* level = type == QtCriticalMsg || type == QtFatalMsg ? "error" : type == QtWarningMsg ? "warn" : "info";
    std::fprintf(stderr, "[%s] %s\n", level, message.toStdString().c_str());
}
} // namespace

int main(int argc, char* argv[]) {
    QCoreApplication app(argc, argv);
    qInstallMessageHandler(stderrLogger);
    // The desktop proxy may be off while music.apple.com is directly
    // reachable; the probe always goes direct.
    QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);

    listenfree::online::AppleDynamicCoverQuery query;
    query.name = QStringLiteral("反方向的钟");
    query.singer = QStringLiteral("周杰伦");
    query.album = QStringLiteral("Jay");
    bool play = false;
    for (int index = 1; index < argc; ++index) {
        const QString argument = QString::fromLocal8Bit(argv[index]);
        const auto value = [&]() -> QString {
            return index + 1 < argc ? QString::fromLocal8Bit(argv[++index]) : QString{};
        };
        if (argument == QStringLiteral("--title")) query.name = value();
        else if (argument == QStringLiteral("--artist")) query.singer = value();
        else if (argument == QStringLiteral("--album")) query.album = value();
        else if (argument == QStringLiteral("--play")) play = true;
    }

    listenfree::online::AppleDynamicArtworkProvider provider;
    provider.fetch(query, [&](std::optional<listenfree::online::AppleDynamicCoverResult> result) {
        if (!result) {
            std::printf("result=not-found\n");
            std::exit(1);
        }
        std::printf("result=ok\n");
        std::printf("album_id=%s\n", result->albumId.toStdString().c_str());
        std::printf("storefront=%s\n", result->storefront.toStdString().c_str());
        std::printf("poster=%s\n", result->posterUrl.toStdString().c_str());
        std::printf("video=%s\n", result->videoUrl.toStdString().c_str());
        std::printf("video_immersive=%s\n", result->videoUrlImmersive.toStdString().c_str());
        std::printf("video_pixel=%s\n", result->videoUrlPixel.toStdString().c_str());
        if (!play) {
            QCoreApplication::exit(0);
            return;
        }
        // Actual load verification: the HLS master/variant must reach
        // LoadedMedia for the acceptance gate.
        auto* player = new QMediaPlayer;
        player->setAudioOutput(new QAudioOutput);
        QObject::connect(player, &QMediaPlayer::mediaStatusChanged, [player](QMediaPlayer::MediaStatus status) {
            std::printf("media_status=%d\n", static_cast<int>(status));
            if (status == QMediaPlayer::LoadedMedia) {
                std::printf("result=loaded\n");
                player->play();
                QTimer::singleShot(1500, [] { QCoreApplication::exit(0); });
            } else if (status == QMediaPlayer::InvalidMedia) {
                std::printf("result=invalid-media\n");
                QCoreApplication::exit(1);
            }
        });
        QObject::connect(player, &QMediaPlayer::errorOccurred, [](QMediaPlayer::Error, const QString& message) {
            std::printf("media_error=%s\n", message.toStdString().c_str());
            QCoreApplication::exit(1);
        });
        player->setSource(QUrl(result->videoUrl));
    });
    QTimer::singleShot(60000, [&] {
        std::printf("result=timeout\n");
        QCoreApplication::exit(1);
    });
    return app.exec();
}
