#pragma once

#include "MusicTypes.h"

#include <QAbstractListModel>
#include <qqmlintegration.h>

#include <optional>

class TrackListModel : public QAbstractListModel {
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(QString search READ search WRITE setSearch NOTIFY searchChanged)
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY modeChanged)
    Q_PROPERTY(QString filterValue READ filterValue WRITE setFilterValue
                   NOTIFY filterValueChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Role {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        ArtistRole,
        AlbumRole,
        AlbumArtistRole,
        GenreRole,
        DurationMsRole,
        DurationTextRole,
        UrlRole,
        PathRole,
        ArtworkUrlRole,
        TrackNumberRole,
        DiscNumberRole,
        YearRole,
        FormatRole,
        AddedAtRole,
        PlayCountRole,
    };

    explicit TrackListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    int count() const;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString search() const;
    void setSearch(const QString &search);
    QString mode() const;
    void setMode(const QString &mode);
    QString filterValue() const;
    void setFilterValue(const QString &value);

    void setTracks(const QList<TrackRecord> &tracks);
    QList<TrackRecord> visibleTracks() const;
    QList<qint64> visibleIds() const;
    std::optional<TrackRecord> trackById(qint64 id) const;

    Q_INVOKABLE qlonglong trackIdAt(int row) const;

signals:
    void searchChanged();
    void modeChanged();
    void filterValueChanged();
    void countChanged();

private:
    void rebuild();
    static QString durationText(qint64 milliseconds);

    QList<TrackRecord> m_source;
    QList<TrackRecord> m_visible;
    QString m_search;
    QString m_mode = QStringLiteral("songs");
    QString m_filterValue;
};
