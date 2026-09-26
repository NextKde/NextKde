#pragma once

#include <QString>
#include <QUrl>

// PlaybackEngine owns the progressive download. This index only publishes
// completed files, keyed by track and quality rather than expiring URLs.
class AudioCache {
public:
    explicit AudioCache(const QString &directory, qint64 maxBytes = 1024LL * 1024 * 1024);
    QUrl lookup(const QString &key);
    bool storeCompleted(const QString &key, const QString &path);
    void remove(const QString &key);
    QString downloadDirectory() const;

private:
    QString pathFor(const QString &key) const;
    void prune();
    QString m_directory;
    qint64 m_maxBytes;
};
