#pragma once
#include <QVariantMap>
#include <QColor>
#include <functional>
#include <memory>
#include "mayonnaise/mayonnaise.hpp"

namespace Kos::Forma {
class NetworkScene {
public:
    NetworkScene(std::function<void()> close, std::function<void()> toggleDetails,
                 std::function<void()> refresh, std::function<void()> reset,
                 const QVariantMap &translations = {});
    ~NetworkScene();
    /// Snapshot values, chart data and the details toggle. Cheap when nothing changed.
    void applyData(const QVariantMap &snapshot, bool details);
    /// Ink colours only. Separated from applyData so a data tick does not mark the
    /// whole native tree for relayout, which apply() used to do every second.
    void applyTheme(const QColor &ink, const QColor &muted);
    const std::shared_ptr<mayo::Widget> &root() const;
    int nativeComponentCount() const;
    float scrollOffset() const;
private:
    struct Impl;
    std::unique_ptr<Impl> d;
};
}
