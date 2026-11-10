#pragma once

#include <QObject>
#include <QDateTime>
#include <QHash>
#include <QNetworkAccessManager>
#include <QSet>
#include <QUrl>

// Only public NextKde contributor data; independent of application catalogs.
class AboutCache : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int avatarRevision READ avatarRevision NOTIFY avatarsChanged)
public:
    explicit AboutCache(QObject *parent = nullptr);
    int avatarRevision() const { return m_revision; }
    Q_INVOKABLE QString readPage(int page) const;
    Q_INVOKABLE bool pageNeedsRefresh(int page);
    Q_INVOKABLE void savePage(int page, const QString &json);
    Q_INVOKABLE QUrl avatar(const QString &remote);

signals:
    void avatarsChanged();

private:
    QString pagePath(int page) const;
    QString m_directory;
    QNetworkAccessManager m_network;
    QHash<QString, QUrl> m_avatars;
    QSet<QString> m_pending;
    QHash<QString, QDateTime> m_failed;
    QHash<int, QDateTime> m_pageRefreshes;
    int m_revision = 0;
};
