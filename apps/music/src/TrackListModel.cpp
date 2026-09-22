#include "TrackListModel.h"

#include <algorithm>
#include <utility>

namespace {

const QChar albumSeparator(0x1f);

QString trackArtist(const TrackRecord &track)
{
    return track.artist.isEmpty() ? track.albumArtist : track.artist;
}

QStringList normalizedTokens(const QString &text)
{
    return TrackListModel::normalizeSearchText(text)
        .split(QLatin1Char(' '), Qt::SkipEmptyParts);
}

int trackSearchScore(const TrackRecord &track, const QString &query)
{
    const QString normalizedQuery = TrackListModel::normalizeSearchText(query);
    if (normalizedQuery.isEmpty())
        return 0;

    const QString title = TrackListModel::normalizeSearchText(track.title);
    const QString artist = TrackListModel::normalizeSearchText(track.artist);
    const QString albumArtist = TrackListModel::normalizeSearchText(track.albumArtist);
    const QString album = TrackListModel::normalizeSearchText(track.album);
    const QString genre = TrackListModel::normalizeSearchText(track.genre);
    const QString document =
        QStringList{title, artist, albumArtist, album, genre}.join(QLatin1Char(' '));
    const QStringList tokens = normalizedTokens(normalizedQuery);
    for (const QString &token : tokens) {
        if (!document.contains(token))
            return -1;
    }

    int score = tokens.size() * 10;
    if (title == normalizedQuery)
        score += 1200;
    else if (title.startsWith(normalizedQuery))
        score += 900;
    if (artist == normalizedQuery || albumArtist == normalizedQuery)
        score += 720;
    else if (artist.startsWith(normalizedQuery) || albumArtist.startsWith(normalizedQuery))
        score += 540;
    if (album == normalizedQuery)
        score += 460;
    else if (album.startsWith(normalizedQuery))
        score += 340;

    for (const QString &token : tokens) {
        if (title == token)
            score += 150;
        else if (title.startsWith(token))
            score += 100;
        else if (title.contains(token))
            score += 60;
        if (artist == token || albumArtist == token)
            score += 90;
        else if (artist.startsWith(token) || albumArtist.startsWith(token))
            score += 60;
        if (album == token)
            score += 50;
    }
    return score;
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
    case SourceRole: return track.source;
    case ProviderIdRole: return track.providerId;
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
        {SourceRole, "source"}, {ProviderIdRole, "providerId"},
    };
}

QString TrackListModel::search() const
{
    return m_search;
}

void TrackListModel::setSearch(const QString &search)
{
    const QString normalized = normalizeSearchText(search);
    if (m_search == normalized)
        return;
    m_search = normalized;
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

void TrackListModel::setView(const QString &mode, const QString &filterValue)
{
    const bool modeChangedValue = m_mode != mode;
    const bool filterChangedValue = m_filterValue != filterValue;
    if (!modeChangedValue && !filterChangedValue)
        return;
    m_mode = mode;
    m_filterValue = filterValue;
    if (modeChangedValue)
        emit modeChanged();
    if (filterChangedValue)
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

std::optional<TrackRecord> TrackListModel::trackAt(int row) const
{
    return row >= 0 && row < m_visible.size()
        ? std::optional<TrackRecord>(m_visible.at(row)) : std::nullopt;
}

void TrackListModel::rebuild()
{
    QList<std::pair<TrackRecord, int>> filtered;
    const QString needle = m_search;
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
        const int score = trackSearchScore(track, needle);
        if (score < 0)
            continue;
        filtered.append({track, score});
    }

    const auto relevanceOrder = [&needle](const auto &left, const auto &right) {
        return !needle.isEmpty() && left.second != right.second
            ? std::optional<bool>(left.second > right.second) : std::nullopt;
    };
    if (m_mode == QLatin1String("queue") && needle.isEmpty()) {
        // The source order is the persisted playback order.
    } else if (m_mode == QLatin1String("recent")) {
        std::stable_sort(filtered.begin(), filtered.end(), [&relevanceOrder](const auto &left,
                                                                            const auto &right) {
            if (const auto relevant = relevanceOrder(left, right))
                return *relevant;
            return left.first.addedAt > right.first.addedAt;
        });
    } else if (m_mode == QLatin1String("album")) {
        std::stable_sort(filtered.begin(), filtered.end(), [&relevanceOrder](const auto &left,
                                                                            const auto &right) {
            if (const auto relevant = relevanceOrder(left, right))
                return *relevant;
            if (left.first.discNumber != right.first.discNumber)
                return left.first.discNumber < right.first.discNumber;
            if (left.first.trackNumber != right.first.trackNumber)
                return left.first.trackNumber < right.first.trackNumber;
            return left.first.title.localeAwareCompare(right.first.title) < 0;
        });
    } else {
        std::stable_sort(filtered.begin(), filtered.end(), [&relevanceOrder](const auto &left,
                                                                            const auto &right) {
            if (const auto relevant = relevanceOrder(left, right))
                return *relevant;
            const int titleOrder = left.first.title.localeAwareCompare(right.first.title);
            return titleOrder == 0
                ? left.first.artist.localeAwareCompare(right.first.artist) < 0
                : titleOrder < 0;
        });
    }

    QList<TrackRecord> visible;
    visible.reserve(filtered.size());
    for (auto &candidate : filtered)
        visible.append(std::move(candidate.first));
    beginResetModel();
    m_visible = std::move(visible);
    endResetModel();
    emit countChanged();
}

QString TrackListModel::normalizeSearchText(const QString &text)
{
    return text.normalized(QString::NormalizationForm_KC).toCaseFolded().simplified();
}

bool TrackListModel::matchesSearch(const QStringList &fields, const QString &query)
{
    const QStringList tokens = normalizedTokens(query);
    if (tokens.isEmpty())
        return true;
    QStringList normalizedFields;
    normalizedFields.reserve(fields.size());
    for (const QString &field : fields)
        normalizedFields.append(normalizeSearchText(field));
    const QString document = normalizedFields.join(QLatin1Char(' '));
    return std::all_of(tokens.cbegin(), tokens.cend(),
                       [&document](const QString &token) {
                           return document.contains(token);
                       });
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
