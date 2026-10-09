#pragma once
#include "qmlbridge/portable_session.h"
#include "qmlbridge/controllers.h"
#include <QApplication>
#include <QElapsedTimer>
#include <QFile>
#include <QDirIterator>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickWindow>
#include <QTimer>
#include <memory>

// Optional real-input acceptance path in the same executable and QML engine.
// No fixture URL or fake player: normal launch never runs this path.
inline void runPortableAcceptance(QApplication& app, listenfree::qmlbridge::PortableSession& player,
                                  listenfree::qmlbridge::LibraryController& library,
                                  listenfree::qmlbridge::SourceController& sources,
                                  QQuickWindow* window, QObject* shell,
                                  const QString& root, const QString& script, const QString& report,
                                  bool restoreOnly) {
    struct State { int phase{0}; int expectedTracks{0}; QElapsedTimer clock, stage; QVariantMap online, first, last; QJsonObject result; };
    auto state = std::make_shared<State>(); state->clock.start(); state->stage.start();
    QDirIterator inputs(root,{"*.mp3","*.flac","*.wav","*.aac","*.m4a","*.ogg","*.oga","*.opus","*.wma","*.ape","*.wv","*.aiff","*.aif","*.tta","*.mp4"},QDir::Files,QDirIterator::Subdirectories);
    while(inputs.hasNext()){inputs.next();++state->expectedTracks;}
    state->result["expected_audio_files"]=state->expectedTracks;
    auto* timer = new QTimer(&app); timer->setInterval(100);
    const auto finish = [&, report, timer, state](const QString& error) {
        timer->stop();
        state->result["passed"] = error.isEmpty(); state->result["error"] = error;
        state->result["phase"] = state->phase; state->result["elapsed_ms"] = state->clock.elapsed();
        state->result["tracks"] = player.songs().size(); state->result["queue_count"] = player.queueSongs().size();
        state->result["player_state"]=player.state();state->result["position"]=player.position();state->result["current_track"]=player.currentTrackId();
        state->result["output"] = qEnvironmentVariable("LISTENFREE_QMMP_OUTPUT", "wasapi");
        QFile file(report); if (file.open(QIODevice::WriteOnly)) file.write(QJsonDocument(state->result).toJson());
        app.exit(error.isEmpty() ? 0 : 7);
    };
    QObject::connect(timer, &QTimer::timeout, &app, [&, state, timer, finish, root, script, report, restoreOnly, window, shell] {
        if (state->clock.elapsed() > 150000) { finish("acceptance-timeout: " + player.errorMessage() + " / " + sources.lastError()); return; }
        if(!player.errorMessage().isEmpty())state->result["last_playback_error"]=player.errorMessage();
        if(state->phase==21 && !state->result.contains("restore_first_playing_track") && player.state()=="Playing") {
            state->result["restore_first_playing_track"]=player.currentTrackId();state->result["restore_first_position"]=player.position();
        }
        { QFile progress(report+".progress");if(progress.open(QIODevice::WriteOnly))progress.write(QJsonDocument(QJsonObject{{"phase",state->phase},{"state",player.state()},{"position",player.position()},{"track",player.currentTrackId()},{"error",player.errorMessage()}}).toJson()); }
        switch (state->phase) {
        case 0:
            if (!player.ready() || !sources.hostReady()) return;
            if (restoreOnly) {
                if (player.songs().size() != state->expectedTracks || player.queueSongs().size() != 3 || player.currentTrackId() != "kw:450444") { finish("restore-mismatch"); return; }
                if (player.state() == "Playing") { finish("unexpected-autoplay"); return; }
                state->phase = 20; return;
            }
            if (!sources.importLocalFile(script) || !library.addRoot(root)) { finish("input-import-failed"); return; }
            library.scan({root}); state->stage.restart(); state->phase = 1; return;
        case 1:
            if (library.scanning() || player.songs().size() != state->expectedTracks) return;
            state->result["scan_ms"] = state->stage.elapsed();
            if (!library.lastError().isEmpty()) { finish(library.lastError()); return; }
            for (const auto& row : player.songs()) {
                const auto map = row.toMap(); const auto path = map.value("localPath").toString();
                if (state->first.isEmpty() && path.endsWith(".mp3", Qt::CaseInsensitive)) state->first = map;
                if (state->last.isEmpty() && path.endsWith(".flac", Qt::CaseInsensitive)) state->last = map;
            }
            if (state->first.isEmpty() || state->last.isEmpty()) { finish("missing-local-formats"); return; }
            // Local pages deliberately filter only local content. Navigate to
            // the online scope before exercising the real search binding.
            shell->setProperty("currentRoute", "discover");
            if (!QMetaObject::invokeMethod(shell, "runSearch", Q_ARG(QVariant, QVariant("https://www.kuwo.cn/play_detail/450444")))) { finish("qml-search-binding-failed"); return; }
            state->phase = 2; return;
        case 2:
            if (player.busy()) return;
            if (player.searchResults().isEmpty()) { finish("real-search-empty"); return; }
            state->online = player.searchResults().first().toMap();
            if (state->online.value("rid").toString() != "450444") { finish("wrong-online-identity"); return; }
            player.clearQueue();
            if (!QMetaObject::invokeMethod(shell, "playTrack", Q_ARG(QVariant, QVariant(state->first)))) { finish("qml-play-binding-failed"); return; }
            player.enqueueTrack(state->online); player.enqueueTrack(state->last);
            state->phase = 3; return;
        case 3:
            if (player.state() != "Playing" || player.position() < 1500) return;
            state->result["local_played"] = true;
            QMetaObject::invokeMethod(shell, "requestPlayback", Q_ARG(QVariant, QVariant("next")));
            state->phase = 4; return;
        case 4:
            if (player.state() != "Playing" || player.position() < 1500 || player.currentTrackId() != "kw:450444") return;
            state->result["online_duration_ms"] = player.duration();
            if (!player.seekable() || player.duration() < 10000) { finish("online-not-seekable"); return; }
            player.pause(); state->phase = 5; return;
        case 5:
            if (player.state() != "Paused") return;
            player.seek(10000); player.play(); state->phase = 6; return;
        case 6:
            if (player.state() != "Playing" || player.position() < 11200) return;
            state->result["online_seek_ms"] = player.position();
            player.next(); state->phase = 7; return;
        case 7:
            if (player.state() != "Playing" || player.position() < 1500 || player.currentTrack().value("localPath") != state->last.value("localPath")) return;
            shell->setProperty("currentRoute", "library/songs");
            shell->setProperty("globalAlertOpen", false);
            state->stage.restart(); state->phase = 8; return;
        case 8:
            if (state->stage.elapsed() >= 5000 && state->stage.elapsed() < 10000) shell->setProperty("currentRoute", "library/albums");
            if (state->stage.elapsed() >= 10000 && state->stage.elapsed() < 15000) {
                if (!state->result.contains("albums_screenshot")) { window->grabWindow().save(report+".albums.png"); state->result["albums_screenshot"] = true; }
                shell->setProperty("currentRoute", "library/artists");
            }
            if (state->stage.elapsed() >= 15000 && state->stage.elapsed() < 20000) {
                if (!state->result.contains("artists_screenshot")) { window->grabWindow().save(report+".artists.png"); state->result["artists_screenshot"] = true; }
                shell->setProperty("currentRoute", "library/songs");
                shell->setProperty("nowPlayingOpen", true);
                shell->setProperty("morphProgress", 1.0);
            }
            if (state->stage.elapsed() >= 20000 && state->stage.elapsed() < 25000) {
                if (!state->result.contains("playing_screenshot")) { window->grabWindow().save(report+".playing.png"); state->result["playing_screenshot"] = true; }
                shell->setProperty("nowPlayingOpen", false);
                shell->setProperty("morphProgress", 0.0);
            }
            // Whole rendered application + loaded SourceHost, steady playback.
            if (state->stage.elapsed() < 30000) return;
            state->result["screenshot"] = report + ".png";
            if (window->grabWindow().isNull() || !window->grabWindow().save(report+".png")) { finish("screenshot-failed"); return; }
            player.selectQueue(1, false); state->result["qml_playback_chain"] = true;
            finish({}); return;
        case 20:
            if (sources.sources().isEmpty() || !sources.sources().first().toMap().value("hostReady").toBool()) return;
            player.play(); state->phase = 21; return;
        case 21:
            if (player.state() != "Playing" || player.currentTrackId() != "kw:450444" || player.position() < 1500) return;
            player.stop(); state->result["restored_online_reresolved"] = true; finish({}); return;
        }
    });
    timer->start();
}
