#pragma once

#include <QPointer>
#include <QQuickItem>
#include <QVariant>
#include <QJSValue>
#include <map>
#include <utility>

namespace KWin
{
inline QQuickItem *overviewTextureSource(const QObject *consumer)
{
    const QVariant source = consumer->property("source");
    if (source.metaType() == QMetaType::fromType<QJSValue>())
        return qobject_cast<QQuickItem *>(source.value<QJSValue>().toQObject());
    return qobject_cast<QQuickItem *>(source.value<QObject *>());
}

// ShadowedTexture/FastBlur sample source->textureProvider() directly. Merely
// adding a child to DesktopBackground does not replace the sampled texture.
class OverviewTextureSources
{
public:
    ~OverviewTextureSources() { restore(); }
    bool replace(QObject *consumer, QQuickItem *original, QQuickItem *preview)
    {
        if (overviewTextureSource(consumer) != original) return false;
        if (!consumer->setProperty("source", QVariant::fromValue(preview))) return false;
        m_saved[consumer] = {consumer, original, preview};
        return true;
    }
    void restore()
    {
        const auto saved = std::exchange(m_saved, {});
        for (const auto &[key, entry] : saved) {
            if (entry.consumer
                && overviewTextureSource(entry.consumer) == entry.preview) {
                entry.consumer->setProperty("source", QVariant::fromValue(entry.original.data()));
            }
        }
    }
private:
    struct Saved {
        QPointer<QObject> consumer;
        QPointer<QQuickItem> original, preview;
    };
    std::map<QObject *, Saved> m_saved;
};
}
