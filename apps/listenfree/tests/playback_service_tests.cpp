#include "application/playback_service.h"
#include "qmlbridge/controllers.h"

#include <QtTest>

#include <optional>
#include <utility>
#include <vector>

class FakeAudioPlayer final : public listenfree::application::IAudioPlayer {
public:
    void open(const listenfree::domain::PlaybackItem& item) override {
        opened.push_back(item);
        state_ = listenfree::domain::PlaybackState::Loading;
    }
    void clear() override { state_ = listenfree::domain::PlaybackState::Idle; }
    void play() override { ++playCalls; state_ = listenfree::domain::PlaybackState::Playing; }
    void pause() override { state_ = listenfree::domain::PlaybackState::Paused; }
    void stop() override { state_ = listenfree::domain::PlaybackState::Stopped; }
    void seek(std::chrono::milliseconds value) override { position_ = value; }
    void setVolume(float value) override { volume_ = value; }
    float volume() const noexcept override { return volume_; }
    void setMuted(bool value) override { muted_ = value; }
    bool muted() const noexcept override { return muted_; }
    listenfree::domain::PlaybackState state() const noexcept override { return state_; }
    std::chrono::milliseconds position() const noexcept override { return position_; }
    std::chrono::milliseconds duration() const noexcept override { return duration_; }
    bool seekable() const noexcept override { return true; }
    std::optional<listenfree::domain::PlaybackError> lastError() const override { return {}; }
    std::optional<listenfree::domain::AudioFormatInfo> audioFormat() const override { return {}; }
    void setEvents(listenfree::application::PlaybackEvents value) override { events = std::move(value); }

    void finish() { if (events.onFinished) events.onFinished(); }
    void moveTo(std::chrono::milliseconds value) {
        position_ = value;
        if (events.onPositionChanged) events.onPositionChanged(value);
    }

    listenfree::application::PlaybackEvents events;
    std::vector<listenfree::domain::PlaybackItem> opened;
    int playCalls{0};

private:
    listenfree::domain::PlaybackState state_{listenfree::domain::PlaybackState::Idle};
    std::chrono::milliseconds position_{0};
    std::chrono::milliseconds duration_{2'000};
    float volume_{1.0F};
    bool muted_{false};
};

namespace {

listenfree::domain::PlaybackItem item(std::string id) {
    listenfree::domain::PlaybackItem result;
    result.track.id = listenfree::domain::TrackId(std::move(id));
    result.track.title = result.track.id.value();
    result.track.localPath = result.track.id.value() + ".wav";
    return result;
}

} // namespace

class PlaybackServiceTests final : public QObject {
    Q_OBJECT

private slots:
    void endOfMediaAdvancesSequentialQueue();
    void lyricPositionTracksPlayerPosition();
    void replacingQueueClearsOldPlaybackAndLyrics();
    void replacingLyricsClearsCurrentLineNotification();
    void controllerProjectionAdvancesOnEnd();
    void destructionDisconnectsPlayerCallbacks();
};

void PlaybackServiceTests::endOfMediaAdvancesSequentialQueue() {
    FakeAudioPlayer player;
    listenfree::application::PlaybackService service(player);
    service.setQueue({item("first"), item("second")}, 0);

    QVERIFY(service.playCurrent());
    QCOMPARE(player.opened.size(), std::size_t(1));
    QCOMPARE(player.opened.back().track.id.value(), std::string("first"));
    QCOMPARE(service.queue().currentIndex(), std::size_t(0));

    player.finish();
    QCOMPARE(service.queue().currentIndex(), std::size_t(1));
    QCOMPARE(player.opened.size(), std::size_t(2));
    QCOMPARE(player.opened.back().track.id.value(), std::string("second"));
    QCOMPARE(player.playCalls, 2);

    player.finish();
    QCOMPARE(service.queue().currentIndex(), std::size_t(1));
    QCOMPARE(player.opened.size(), std::size_t(2));
}

void PlaybackServiceTests::lyricPositionTracksPlayerPosition() {
    FakeAudioPlayer player;
    listenfree::application::PlaybackService service(player);
    service.setLyrics({{std::chrono::milliseconds(0), std::chrono::milliseconds(500), "first line"},
                       {std::chrono::milliseconds(500), std::chrono::milliseconds(1'000), "second line"}});

    QCOMPARE(service.currentLyricIndex(), std::optional<std::size_t>(0));
    QCOMPARE(service.currentLyricLine()->text, std::string("first line"));
    player.moveTo(std::chrono::milliseconds(650));
    QCOMPARE(service.currentLyricIndex(), std::optional<std::size_t>(1));
    QCOMPARE(service.currentLyricLine()->text, std::string("second line"));
    player.moveTo(std::chrono::milliseconds(1'500));
    QVERIFY(!service.currentLyricIndex().has_value());
    QVERIFY(!service.currentLyricLine().has_value());
}

void PlaybackServiceTests::replacingQueueClearsOldPlaybackAndLyrics() {
    FakeAudioPlayer player;
    listenfree::application::PlaybackService service(player);
    service.setQueue({item("old")});
    QVERIFY(service.playCurrent());
    service.setLyrics({{std::chrono::milliseconds(0), std::chrono::milliseconds(500), "old lyric"}});
    QVERIFY(!service.lyrics().empty());

    service.setQueue({item("new")});
    QCOMPARE(player.state(), listenfree::domain::PlaybackState::Idle);
    QCOMPARE(service.currentItem()->track.id.value(), std::string("new"));
    QVERIFY(service.lyrics().empty());
    QVERIFY(!service.currentLyricIndex().has_value());
}

void PlaybackServiceTests::replacingLyricsClearsCurrentLineNotification() {
    FakeAudioPlayer player;
    listenfree::application::PlaybackService service(player);
    int currentChanges = 0;
    listenfree::application::PlaybackServiceEvents events;
    events.onCurrentLyricChanged = [&currentChanges] { ++currentChanges; };
    service.setEvents(std::move(events));
    service.setLyrics({{std::chrono::milliseconds(0), std::chrono::milliseconds(500), "visible"}});
    QCOMPARE(service.currentLyricIndex(), std::optional<std::size_t>(0));
    QCOMPARE(currentChanges, 1);

    service.setLyrics({{std::chrono::milliseconds(1'000), std::chrono::milliseconds(1'500),
                        "future"}});
    QVERIFY(!service.currentLyricIndex().has_value());
    QCOMPARE(currentChanges, 2);
}

void PlaybackServiceTests::controllerProjectionAdvancesOnEnd() {
    auto player = std::make_unique<FakeAudioPlayer>();
    auto* playerView = player.get();
    listenfree::qmlbridge::PlayerController controller(std::move(player));
    controller.setQueue({item("first"), item("second")});
    QCOMPARE(controller.queueModel()->currentIndex(), 0);
    QCOMPARE(controller.currentTrackId(), QStringLiteral("first"));
    controller.play();

    playerView->finish();
    QCOMPARE(controller.queueModel()->currentIndex(), 1);
    QCOMPARE(controller.currentTrackId(), QStringLiteral("second"));
    QCOMPARE(playerView->opened.back().track.id.value(), std::string("second"));
}

void PlaybackServiceTests::destructionDisconnectsPlayerCallbacks() {
    FakeAudioPlayer player;
    {
        listenfree::application::PlaybackService service(player);
        QVERIFY(static_cast<bool>(player.events.onFinished));
    }
    QVERIFY(!player.events.onFinished);
    QVERIFY(!player.events.onPositionChanged);
    player.finish();
}

QTEST_GUILESS_MAIN(PlaybackServiceTests)
#include "playback_service_tests.moc"
