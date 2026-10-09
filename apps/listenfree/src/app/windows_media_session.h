#pragma once
#include <QObject>
#include <QString>
#include <memory>

class QWindow;
namespace listenfree {
// An OS integration boundary: no playback engine or second audio session.
class WindowsMediaSession final : public QObject {
    Q_OBJECT
public:
    struct State {
        QString title, artist, album, artwork, playback;
        qint64 position{}, duration{};
        bool hasTrack{}, seekable{}, previous{}, next{};
    };
    enum Button { Play, Pause, Stop, Next, Previous };
    Q_ENUM(Button)
    // Call before creating windows. A Start-menu identity lets Windows resolve
    // the display name/icon even when a portable EXE is launched directly.
    static QString registerApplicationIdentity(const QString& appId, const QString& displayName);
    explicit WindowsMediaSession(QWindow* window, QObject* parent = nullptr);
    ~WindowsMediaSession() override;
    bool available() const;
    QString errorString() const;
    void update(const State& state);
signals:
    void buttonRequested(Button button);
    void seekRequested(qint64 milliseconds);
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
}
