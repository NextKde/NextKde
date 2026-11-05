#pragma once

#include <QJsonObject>
#include <QString>
#include <atomic>
#include <chrono>
#include <memory>

typedef struct _GCancellable GCancellable;

namespace KosPlatform::IndependentAppWidgets {
// Fixed app keys only; no caller-supplied filesystem paths or executable names.
bool supported(const QString &key);
struct QueryControl {
    QueryControl();
    ~QueryControl();
    QueryControl(const QueryControl &) = delete;
    QueryControl &operator=(const QueryControl &) = delete;
    void cancel();
    bool expired() const;
    GCancellable *cancellable;
    const std::chrono::steady_clock::time_point deadline;
    std::atomic_bool cancelled{false};
};
QJsonObject snapshot(const QString &key, const std::shared_ptr<QueryControl> &control);
// Recheck only the resolved entry/deployment immediately around KService loading.
bool launchEntryMatches(const QJsonObject &source);
}
