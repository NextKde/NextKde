#include "CacheMaintenance.h"

#include <QAtomicInt>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QThreadPool>
#include <QVector>
#include <QtGlobal>

#include <algorithm>

namespace CacheMaintenance {

void schedule(const QString &dir, qint64 maxBytes, int maxFiles)
{
    static QAtomicInt inFlight;
    if (!inFlight.testAndSetAcquire(0, 1))
        return;
    QThreadPool::globalInstance()->start([dir, maxBytes, maxFiles]() {
        struct Entry { QString path; qint64 size; qint64 mtime; };
        QVector<Entry> entries;
        qint64 totalBytes = 0;
        for (QDirIterator it(dir, {QStringLiteral("*.png"), QStringLiteral("*.webp")},
                             QDir::Files | QDir::NoSymLinks); it.hasNext();) {
            const QFileInfo info = it.nextFileInfo();
            entries.append({ info.absoluteFilePath(), info.size(),
                             info.lastModified().toMSecsSinceEpoch() });
            totalBytes += info.size();
        }
        if (totalBytes <= maxBytes && entries.size() <= maxFiles) {
            inFlight.storeRelease(0);
            return;
        }
        // mtime 从旧到新:最新生成的缩略图最可能还在被用(新导入排最上)。
        std::sort(entries.begin(), entries.end(),
                  [](const Entry &a, const Entry &b) { return a.mtime < b.mtime; });
        qint64 removedBytes = 0;
        int removedCount = 0;
        for (const Entry &entry : entries) {
            if (totalBytes - removedBytes <= maxBytes
                    && entries.size() - removedCount <= maxFiles)
                break;
            if (QFile::remove(entry.path)) {
                removedBytes += entry.size;
                ++removedCount;
            }
        }
        inFlight.storeRelease(0);
    });
}

} // namespace CacheMaintenance
