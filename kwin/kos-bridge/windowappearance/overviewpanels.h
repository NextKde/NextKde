#pragma once

#include <scene/item.h>
#include <QPointer>
#include <map>
#include <utility>

namespace KOS::WindowAppearance
{
// Native Overview captures WindowItems without the Glass draw chain. Keep
// shell panels absent from those captures until normal compositing resumes.
// Change only scene opacity, never client visibility, focus, or desktop state.
class OverviewPanels
{
public:
    ~OverviewPanels() { restore(); }

    void suppress(KWin::Item *item)
    {
        if (!item) return;
        auto it = m_items.find(item);
        if (it == m_items.end() || !it->second.item) {
            m_items[item] = {item, item->opacity()};
        } else if (item->opacity() != 0) {
            // Preserve a newer opacity supplied by the compositor/client.
            it->second.opacity = item->opacity();
        }
        item->setOpacity(0);
    }

    void restore()
    {
        // Clear tracking before scene damage can synchronously re-enter us.
        auto items = std::exchange(m_items, {});
        for (const auto &entry : items) {
            const auto &saved = entry.second;
            if (saved.item && saved.item->opacity() == 0)
                saved.item->setOpacity(saved.opacity);
        }
    }

private:
    struct SavedOpacity {
        QPointer<KWin::Item> item;
        qreal opacity;
    };
    std::map<KWin::Item *, SavedOpacity> m_items;
};
}
