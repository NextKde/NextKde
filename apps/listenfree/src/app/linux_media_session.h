#pragma once
#include <QObject>
#include <QVariantMap>
#include <QTimer>
#include <QTemporaryDir>
#include <QElapsedTimer>
#include <QDBusObjectPath>

class QWindow;
namespace listenfree {
namespace qmlbridge { class PortableSession; class SettingsController; }
class LinuxMediaSession final : public QObject {
    Q_OBJECT
public:
    LinuxMediaSession(qmlbridge::PortableSession& player, qmlbridge::SettingsController& settings,
                      QWindow* window, QObject* parent = nullptr);
    ~LinuxMediaSession() override;
    qmlbridge::PortableSession& player() const { return player_; }
    bool registered() const { return registered_; }
    QVariantMap metadata() const;
    QString playbackStatus() const;
    QString loopStatus() const;
    QDBusObjectPath trackPath() const;
    void seek(qint64 microseconds);
    void raise();
    void refresh();
signals:
    void seeked(qlonglong position);
private:
    qmlbridge::PortableSession& player_;
    qmlbridge::SettingsController& settings_;
    QWindow* window_;
    QString service_, artworkSource_, artworkUrl_;
    QTemporaryDir artworkDirectory_;
    QTimer flush_;
    QElapsedTimer elapsed_;
    qint64 lastPosition_ = 0;
    bool registered_ = false;
    QVariantMap published_;
    QVariantList lyrics_;
    void updateRegistration();
    void updateArtwork();
    void publish();
};
}
