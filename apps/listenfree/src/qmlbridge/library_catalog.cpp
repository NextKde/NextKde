#include "library_catalog.h"
#include "online/track_origin.h"
#include "platform/file_paths.h"
#include <QSet>

namespace listenfree::qmlbridge {
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
    QSet<QString> albumKeys;
    for (const auto& value : collections_) {
        auto row = value.toMap();
        if (row.value("kind").toString() != "album") continue;
        const auto key = row.value("source").toString() + ":" + row.value("playlistId", row.value("id")).toString();
        if (albumKeys.contains(key)) continue;
        albumKeys.insert(key);
        row["savedOnlineAlbum"] = true;
        albums_.append(row); // Keep provider, playlistId and reference for open().
    }
    emit changed();
}
}
