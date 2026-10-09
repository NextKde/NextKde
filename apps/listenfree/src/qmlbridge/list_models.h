#pragma once

#include "domain/domain.h"

#include <QAbstractListModel>
#include <QSortFilterProxyModel>
#include <QVector>
#include <vector>

namespace listenfree::qmlbridge {

class TrackListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    enum Role {
        TrackIdRole = Qt::UserRole + 1,
        TitleRole,
        ArtistRole,
        AlbumRole,
        DurationRole,
        LocalPathRole,
        ArtworkRole
    };
    explicit TrackListModel(QObject* parent = nullptr);
    void setTracks(std::vector<domain::Track> tracks);
    // Share the portable catalog/queue maps instead of duplicating every string
    // into a second domain::Track collection solely for QML presentation.
    void setRows(QVariantList rows);
    // The caller has verified the complete trackId sequence on a worker.
    // Keep persistent indexes when only a bounded set of row maps changed.
    bool replaceRowsSameOrder(QVariantList rows, const QVector<int>& changedRows);
    // Incremental row-storage update for tail additions. A fresh empty model
    // enters row storage on its first append; a populated track-storage model
    // cannot be appended to through this API.
    bool appendRow(QVariantMap row);
    bool removeRow(int row);
    // The destination is the row's final index, matching QList::move and
    // Qmmp's single-track move semantics.
    bool moveRow(int from, int to);
    int rowCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
    Q_INVOKABLE QVariantMap get(int row) const;
    // Retain every catalog field (including playback metadata) when a proxy
    // projects a source row. QVariantMap and QVariantList are shared on copy.
    Q_INVOKABLE [[nodiscard]] QVariantMap rowMap(int row) const;
    // A read-only, implicitly shared snapshot for actions that consume a full
    // visible list. Avoid one QML-to-C++ call (and role conversion) per row.
    Q_INVOKABLE QVariantList snapshotRows() const;
signals:
    void countChanged();
private:
    std::vector<domain::Track> tracks_;
    QVariantList rows_;
    bool rowStorage_ = false;
};

class FilteredTrackModel : public QSortFilterProxyModel {
    Q_OBJECT
    Q_PROPERTY(TrackListModel* sourceTracks READ sourceTracks WRITE setSourceTracks NOTIFY sourceTracksChanged)
    Q_PROPERTY(QString filterText READ filterText WRITE setFilterText NOTIFY filterTextChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    explicit FilteredTrackModel(QObject* parent = nullptr);
    [[nodiscard]] TrackListModel* sourceTracks() const;
    void setSourceTracks(TrackListModel* source);
    [[nodiscard]] QString filterText() const { return filterText_; }
    void setFilterText(const QString& text);
    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE QVariantList snapshotRows() const;
signals:
    void sourceTracksChanged();
    void filterTextChanged();
    void countChanged();
protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex& sourceParent) const override;
private:
    QString filterText_;
    QString normalizedFilter_;
};

class QueueModel final : public TrackListModel {
    Q_OBJECT
    Q_PROPERTY(int currentIndex READ currentIndex NOTIFY currentIndexChanged)
public:
    using TrackListModel::TrackListModel;
    [[nodiscard]] int currentIndex() const noexcept { return currentIndex_; }
    void setCurrentIndex(int index);
signals:
    void currentIndexChanged();
private:
    int currentIndex_{-1};
};

class PlaylistListModel final : public QAbstractListModel {
    Q_OBJECT
public:
    enum Role { PlaylistIdRole = Qt::UserRole + 1, TitleRole, EntryCountRole };
    explicit PlaylistListModel(QObject* parent = nullptr);
    void setPlaylists(std::vector<domain::Playlist> playlists);
    int rowCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
private:
    std::vector<domain::Playlist> playlists_;
};

} // namespace listenfree::qmlbridge
