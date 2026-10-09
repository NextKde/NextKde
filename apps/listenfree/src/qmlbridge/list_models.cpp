#include "qmlbridge/list_models.h"

#include <QString>
#include <QLocale>
#include <QUrl>
#include <QFileInfo>
#include <QDateTime>

namespace listenfree::qmlbridge {

TrackListModel::TrackListModel(QObject* parent) : QAbstractListModel(parent) {}

void TrackListModel::setTracks(std::vector<domain::Track> tracks) {
    beginResetModel();
    rows_.clear();
    rowStorage_ = false;
    tracks_ = std::move(tracks);
    endResetModel();
    emit countChanged();
}

void TrackListModel::setRows(QVariantList rows) {
    beginResetModel();
    std::vector<domain::Track>().swap(tracks_);
    rowStorage_ = true;
    rows_ = std::move(rows);
    endResetModel();
    emit countChanged();
}

bool TrackListModel::replaceRowsSameOrder(QVariantList rows, const QVector<int>& changedRows) {
    if (!rowStorage_ || rows_.size() != rows.size()) return false;
    int previous = -1;
    for (const int row : changedRows) {
        if (row <= previous || row >= rows.size()) return false;
        previous = row;
    }
    rows_ = std::move(rows);
    // An empty roles list means every role changed. Group adjacent rows so a
    // tag editor updating several tracks does not emit one signal per track.
    for (qsizetype i = 0; i < changedRows.size();) {
        const int first = changedRows.at(i);
        int last = first;
        while (++i < changedRows.size() && changedRows.at(i) == last + 1) last = changedRows.at(i);
        emit dataChanged(index(first, 0), index(last, 0));
    }
    return true;
}

bool TrackListModel::appendRow(QVariantMap row) {
    if (!rowStorage_) {
        if (!tracks_.empty()) return false;
        rowStorage_ = true;
    }
    const int nextRow = static_cast<int>(rows_.size());
    beginInsertRows({}, nextRow, nextRow);
    rows_.append(std::move(row));
    endInsertRows();
    emit countChanged();
    return true;
}

bool TrackListModel::removeRow(int row) {
    if (!rowStorage_ || row < 0 || row >= rows_.size()) return false;
    beginRemoveRows({}, row, row);
    rows_.removeAt(row);
    endRemoveRows();
    emit countChanged();
    return true;
}

bool TrackListModel::moveRow(int from, int to) {
    if (!rowStorage_ || from < 0 || to < 0 || from >= rows_.size() || to >= rows_.size()) return false;
    if (from == to) return true;
    const int destinationChild = to > from ? to + 1 : to;
    if (!beginMoveRows({}, from, from, {}, destinationChild)) return false;
    rows_.move(from, to);
    endMoveRows();
    return true;
}

QVariantMap TrackListModel::get(int row) const {
    if (row < 0 || row >= rowCount()) return {};
    QVariantMap result;
    const auto roles=roleNames();
    for(auto it=roles.cbegin();it!=roles.cend();++it)result.insert(QString::fromUtf8(it.value()),data(index(row,0),it.key()));
    return result;
}

QVariantMap TrackListModel::rowMap(int row) const {
    if (row < 0 || row >= rowCount()) return {};
    return rowStorage_ ? rows_.at(row).toMap() : get(row);
}

QVariantList TrackListModel::snapshotRows() const {
    if (rowStorage_) return rows_;
    QVariantList result;
    result.reserve(static_cast<qsizetype>(tracks_.size()));
    for (int row = 0; row < rowCount(); ++row) result.append(get(row));
    return result;
}

int TrackListModel::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : static_cast<int>(rowStorage_ ? rows_.size() : tracks_.size());
}

QVariant TrackListModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount()) return {};
    if (rowStorage_) {
        const auto row = rows_.at(index.row()).toMap();
        switch (role) {
        case Qt::DisplayRole: case TitleRole: return row.value("title").toString();
        case TrackIdRole: return row.value("trackId").toString();
        case ArtistRole: return row.value("artist").toString();
        case AlbumRole: return row.value("album").toString();
        case DurationRole: return row.value("durationMs", row.value("duration")).toLongLong();
        case LocalPathRole: return row.value("localPath").toString();
        case ArtworkRole: return row.value("artwork").toString();
        default: return {};
        }
    }
    const auto& track = tracks_[static_cast<std::size_t>(index.row())];
    switch (role) {
    case Qt::DisplayRole:
    case TitleRole: return QString::fromStdString(track.title);
    case TrackIdRole: return QString::fromStdString(track.id.value());
    case ArtistRole: return track.artists.empty() ? QString{} : QString::fromStdString(track.artists.front().name);
    case AlbumRole: return track.album ? QString::fromStdString(track.album->title) : QString{};
    case DurationRole: return static_cast<qint64>(track.duration.count());
    case LocalPathRole: return track.localPath ? QString::fromStdString(*track.localPath) : QString{};
    case ArtworkRole:
        if (track.localPath) {
            const auto path=QString::fromStdString(*track.localPath);const QFileInfo info(path);
            return "image://covers/" + QString::fromLatin1(QUrl::toPercentEncoding(path)) + "?v="
                + QString::number(info.lastModified().toMSecsSinceEpoch()) + "-" + QString::number(info.size());
        }
        return track.album && track.album->artworkUrl ? QString::fromStdString(*track.album->artworkUrl) : QString{};
    default: return {};
    }
}

QHash<int, QByteArray> TrackListModel::roleNames() const {
    return {{TrackIdRole, "trackId"}, {TitleRole, "title"}, {ArtistRole, "artist"},
            {AlbumRole, "album"}, {DurationRole, "duration"}, {LocalPathRole, "localPath"},
            {ArtworkRole, "artwork"}};
}

FilteredTrackModel::FilteredTrackModel(QObject* parent) : QSortFilterProxyModel(parent) {
    // Filtering changes the proxy's row count through inserts/removals or a
    // reset. Moves and data changes that retain membership need no count emit.
    connect(this, &QAbstractItemModel::rowsInserted, this, &FilteredTrackModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &FilteredTrackModel::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &FilteredTrackModel::countChanged);
}

TrackListModel* FilteredTrackModel::sourceTracks() const {
    return qobject_cast<TrackListModel*>(sourceModel());
}

void FilteredTrackModel::setSourceTracks(TrackListModel* source) {
    if (source == sourceTracks()) return;
    setSourceModel(source);
    emit sourceTracksChanged();
}

void FilteredTrackModel::setFilterText(const QString& text) {
    if (text == filterText_) return;
    const QString nextFilter = QLocale().toLower(text.trimmed());
    const bool refilter = nextFilter != normalizedFilter_;
    filterText_ = text;
    if (refilter) {
        beginFilterChange();
        normalizedFilter_ = nextFilter;
        endFilterChange(Direction::Rows);
    }
    emit filterTextChanged();
}

bool FilteredTrackModel::filterAcceptsRow(int sourceRow, const QModelIndex& sourceParent) const {
    if (normalizedFilter_.isEmpty()) return true;
    const auto* source = sourceTracks();
    if (!source || sourceParent.isValid()) return false;
    const auto sourceIndex = source->index(sourceRow, 0, sourceParent);
    const QLocale locale;
    for (const int role : {TrackListModel::TitleRole, TrackListModel::ArtistRole, TrackListModel::AlbumRole}) {
        if (locale.toLower(source->data(sourceIndex, role).toString()).contains(normalizedFilter_)) return true;
    }
    return false;
}

QVariantMap FilteredTrackModel::get(int row) const {
    const auto* source = sourceTracks();
    if (!source || row < 0 || row >= rowCount()) return {};
    const auto sourceIndex = mapToSource(index(row, 0));
    return sourceIndex.isValid() ? source->rowMap(sourceIndex.row()) : QVariantMap{};
}

QVariantList FilteredTrackModel::snapshotRows() const {
    QVariantList result;
    const auto* source = sourceTracks();
    if (!source) return result;
    result.reserve(rowCount());
    for (int row = 0; row < rowCount(); ++row) {
        const auto sourceIndex = mapToSource(index(row, 0));
        if (sourceIndex.isValid()) result.append(source->rowMap(sourceIndex.row()));
    }
    return result;
}

void QueueModel::setCurrentIndex(int index) {
    const int bounded = index >= 0 && index < rowCount() ? index : -1;
    if (currentIndex_ == bounded) return;
    currentIndex_ = bounded;
    emit currentIndexChanged();
}

PlaylistListModel::PlaylistListModel(QObject* parent) : QAbstractListModel(parent) {}

void PlaylistListModel::setPlaylists(std::vector<domain::Playlist> playlists) {
    beginResetModel();
    playlists_ = std::move(playlists);
    endResetModel();
}

int PlaylistListModel::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : static_cast<int>(playlists_.size());
}

QVariant PlaylistListModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount()) return {};
    const auto& playlist = playlists_[static_cast<std::size_t>(index.row())];
    switch (role) {
    case Qt::DisplayRole:
    case TitleRole: return QString::fromStdString(playlist.title);
    case PlaylistIdRole: return QString::fromStdString(playlist.id.value());
    case EntryCountRole: return static_cast<qint64>(playlist.entries.size());
    default: return {};
    }
}

QHash<int, QByteArray> PlaylistListModel::roleNames() const {
    return {{PlaylistIdRole, "playlistId"}, {TitleRole, "title"}, {EntryCountRole, "entryCount"}};
}

} // namespace listenfree::qmlbridge
