#pragma once

#include <QPointer>
#include <QQuickItem>
#include <map>
#include <utility>

namespace KWin
{
// Keep the native panel delegate and all its QML bindings intact. Its complete
// material is rendered inside the desktop preview instead. A separate invisible
// visual parent prevents native opacity animations from exposing a second copy.
class OverviewPanelProjection
{
public:
    ~OverviewPanelProjection() { restore(); }

    void project(QQuickItem *item)
    {
        auto &saved = m_items[item];
        if (saved.item) return;
        if (saved.container) delete saved.container;
        auto *parent = item->parentItem();
        auto *container = new QQuickItem(parent);
        container->setOpacity(0);
        saved = {item, parent, container};
        item->setParentItem(container);
    }

    void restore()
    {
        auto items = std::exchange(m_items, {});
        for (const auto &[key, saved] : items) {
            if (saved.item) saved.item->setParentItem(saved.parent);
            if (saved.container) delete saved.container;
        }
    }

private:
    struct Saved {
        QPointer<QQuickItem> item, parent, container;
    };
    std::map<QQuickItem *, Saved> m_items;
};
}
