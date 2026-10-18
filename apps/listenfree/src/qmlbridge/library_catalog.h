#pragma once
#include "qmlbridge/list_models.h"

namespace listenfree::qmlbridge {
// Local songs retain the scanner model. Saved albums remain available separately.
class LibraryCatalog final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList songs READ songs NOTIFY changed)
    Q_PROPERTY(QVariantList albums READ albums NOTIFY changed)
    Q_PROPERTY(QVariantList artists READ artists NOTIFY changed)
    Q_PROPERTY(TrackListModel* tracksModel READ tracksModel NOTIFY changed)
public:
    explicit LibraryCatalog(TrackListModel* localModel, QObject* parent = nullptr);
    void setLocalCatalog(QVariantList songs, QVariantList albums, QVariantList artists);
    void setCollections(QVariantList collections);
    QVariantList songs() const { return songs_; }
    QVariantList albums() const { return albums_; }
    QVariantList artists() const { return localArtists_; }
    TrackListModel* tracksModel() { return localModel_; }
signals:
    void changed();
private:
    TrackListModel* localModel_;
    QVariantList localSongs_, localAlbums_, localArtists_, collections_, songs_, albums_;
    void rebuild();
};
}
