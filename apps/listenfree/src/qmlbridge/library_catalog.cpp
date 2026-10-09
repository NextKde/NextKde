#include "library_catalog.h"
#include "online/track_origin.h"
#include "platform/file_paths.h"
#include <QSet>

namespace listenfree::qmlbridge {
namespace {
QString trackKey(const QVariantMap& row) {
    const auto path = row.value("localPath").toString();
    if (!path.isEmpty()) return "local:" + platform::filePathKey(path);
    if (online::isScriptTrack(row)) return online::scriptTrackKey(row);
    return row.value("source").toString() + ":" + row.value("rid", row.value("trackId")).toString();
}
}
LibraryCatalog::LibraryCatalog(TrackListModel* model, QObject* parent)
    : QObject(parent), localModel_(model) {}
void LibraryCatalog::setLocalCatalog(QVariantList songs, QVariantList albums, QVariantList artists) {
    localSongs_ = std::move(songs); localAlbums_ = std::move(albums); localArtists_ = std::move(artists);
    rebuild();
}
void LibraryCatalog::setCollections(QVariantList collections) {
    collections_ = std::move(collections);
    rebuild();
}
void LibraryCatalog::rebuild() {
    songs_ = localSongs_; albums_ = localAlbums_;
    QVariantList liked;
    QSet<QString> albumKeys;
    for (const auto& value : collections_) {
        auto row = value.toMap();
        if (row.value("id").toString() == "liked-tracks") liked = row.value("tracks").toList();
        if (row.value("kind").toString() != "album") continue;
        const auto key = row.value("source").toString() + ":" + row.value("playlistId", row.value("id")).toString();
        if (albumKeys.contains(key)) continue;
        albumKeys.insert(key);
        row["savedOnlineAlbum"] = true;
        albums_.append(row); // Keep provider, playlistId and reference for open().
    }
    hasSavedSongs_ = false;
    if (!liked.isEmpty()) {
        QSet<QString> known;
        for (const auto& value : localSongs_) known.insert(trackKey(value.toMap()));
        for (const auto& value : liked) {
            const auto key = trackKey(value.toMap());
            if (known.contains(key)) continue;
            known.insert(key); songs_.append(value); hasSavedSongs_ = true;
        }
    }
    // With no extra rows, retain the scanner's sparse-update model unchanged.
    combinedModel_.setRows(hasSavedSongs_ ? songs_ : QVariantList{});
    emit changed();
}
}
