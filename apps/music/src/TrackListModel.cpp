#include "TrackListModel.h"

#include <algorithm>
#include <utility>

namespace {

const QChar albumSeparator(0x1f);

QString trackArtist(const TrackRecord &track)
{
    return track.artist.isEmpty() ? track.albumArtist : track.artist;
}

} // namespace

TrackListModel::TrackListModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int TrackListModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_visible.size());
}

int TrackListModel::count() const
{
    return static_cast<int>(m_visible.size());
}

QVariant TrackListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_visible.size())
        return {};
    const TrackRecord &track = m_visible.at(index.row());
    switch (role) {
    case IdRole: return track.id;
    case TitleRole: return track.title;
    case ArtistRole: return track.artist;
    case AlbumRole: return track.album;
    case AlbumArtistRole: return track.albumArtist;
    case GenreRole: return track.genre;
    case DurationMsRole: return track.durationMs;
    case DurationTextRole: return durationText(track.durationMs);
    case UrlRole: return track.url;
    case PathRole: return track.path;
    case ArtworkUrlRole: return track.artworkUrl;
    case TrackNumberRole: return track.trackNumber;
    case DiscNumberRole: return track.discNumber;
    case YearRole: return track.year;
    case FormatRole: return track.format;
    case AddedAtRole: return track.addedAt;
    case PlayCountRole: return track.playCount;
    default: return {};
    }
}

QHash<int, QByteArray> TrackListModel::roleNames() const
{
    return {
        {IdRole, "trackId"}, {TitleRole, "title"}, {ArtistRole, "artist"},
        {AlbumRole, "album"}, {AlbumArtistRole, "albumArtist"},
        {GenreRole, "genre"}, {DurationMsRole, "durationMs"},
        {DurationTextRole, "durationText"}, {UrlRole, "url"}, {PathRole, "path"},
        {ArtworkUrlRole, "artworkUrl"}, {TrackNumberRole, "trackNumber"},
        {DiscNumberRole, "discNumber"}, {YearRole, "year"}, {FormatRole, "format"},
        {AddedAtRole, "addedAt"}, {PlayCountRole, "playCount"},
    };
}

QString TrackListModel::search() const
{
    return m_search;
}

void TrackListModel::setSearch(const QString &search)
{
    if (m_search == search)
        return;
    m_search = search;
    emit searchChanged();
    rebuild();
}

QString TrackListModel::mode() const
{
    return m_mode;
}

void TrackListModel::setMode(const QString &mode)
{
    if (m_mode == mode)
        return;
    m_mode = mode;
    emit modeChanged();
    rebuild();
}

QString TrackListModel::filterValue() const
{
    return m_filterValue;
}

void TrackListModel::setFilterValue(const QString &value)
{
    if (m_filterValue == value)
        return;
    m_filterValue = value;
    emit filterValueChanged();
    rebuild();
}

void TrackListModel::setTracks(const QList<TrackRecord> &tracks)
{
    m_source = tracks;
    rebuild();
}

QList<TrackRecord> TrackListModel::visibleTracks() const
{
    return m_visible;
}

QList<qint64> TrackListModel::visibleIds() const
{
    QList<qint64> result;
    result.reserve(m_visible.size());
    for (const TrackRecord &track : m_visible)
        result.append(track.id);
    return result;
}

std::optional<TrackRecord> TrackListModel::trackById(qint64 id) const
{
    const auto found = std::find_if(m_source.cbegin(), m_source.cend(),
                                    [id](const TrackRecord &track) { return track.id == id; });
    return found == m_source.cend() ? std::nullopt : std::optional<TrackRecord>(*found);
}

qlonglong TrackListModel::trackIdAt(int row) const
{
    return row >= 0 && row < m_visible.size() ? m_visible.at(row).id : -1;
}

void TrackListModel::rebuild()
{
    QList<TrackRecord> filtered;
    const QString needle = m_search.trimmed();
    for (const TrackRecord &track : std::as_const(m_source)) {
        if (m_mode == QLatin1String("album")) {
            const qsizetype separator = m_filterValue.indexOf(albumSeparator);
            const QString album = separator < 0
                ? m_filterValue : m_filterValue.left(separator);
            const QString albumArtist = separator < 0
                ? QString{} : m_filterValue.mid(separator + 1);
            if (track.album.compare(album, Qt::CaseInsensitive) != 0
                || (separator >= 0
                    && track.albumArtist.compare(albumArtist,
                                                 Qt::CaseInsensitive) != 0)) {
                continue;
            }
        }
        if (m_mode == QLatin1String("artist")
            && trackArtist(track).compare(m_filterValue,
                                          Qt::CaseInsensitive) != 0) {
            continue;
        }
        if (!needle.isEmpty()
            && !track.title.contains(needle, Qt::CaseInsensitive)
            && !track.artist.contains(needle, Qt::CaseInsensitive)
            && !track.album.contains(needle, Qt::CaseInsensitive)
            && !track.genre.contains(needle, Qt::CaseInsensitive)) {
            continue;
        }
        filtered.append(track);
    }
    if (m_mode == QLatin1String("queue")) {
        // The source order is the persisted playback order.
    } else if (m_mode == QLatin1String("recent")) {
        std::stable_sort(filtered.begin(), filtered.end(), [](const TrackRecord &left,
                                                              const TrackRecord &right) {
            return left.addedAt > right.addedAt;
        });
    } else if (m_mode == QLatin1String("album")) {
        std::stable_sort(filtered.begin(), filtered.end(), [](const TrackRecord &left,
                                                              const TrackRecord &right) {
            if (left.discNumber != right.discNumber)
                return left.discNumber < right.discNumber;
            if (left.trackNumber != right.trackNumber)
                return left.trackNumber < right.trackNumber;
            return left.title.localeAwareCompare(right.title) < 0;
        });
    } else {
        std::stable_sort(filtered.begin(), filtered.end(), [](const TrackRecord &left,
                                                              const TrackRecord &right) {
            const int titleOrder = left.title.localeAwareCompare(right.title);
            return titleOrder == 0
                ? left.artist.localeAwareCompare(right.artist) < 0 : titleOrder < 0;
        });
    }

    beginResetModel();
    m_visible = std::move(filtered);
    endResetModel();
    emit countChanged();
}

QString TrackListModel::durationText(qint64 milliseconds)
{
    const qint64 seconds = std::max<qint64>(0, milliseconds / 1000);
    const qint64 hours = seconds / 3600;
    const qint64 minutes = (seconds / 60) % 60;
    const qint64 remainder = seconds % 60;
    return hours > 0
        ? QStringLiteral("%1:%2:%3").arg(hours).arg(minutes, 2, 10, QLatin1Char('0'))
              .arg(remainder, 2, 10, QLatin1Char('0'))
        : QStringLiteral("%1:%2").arg(minutes).arg(remainder, 2, 10, QLatin1Char('0'));
}
