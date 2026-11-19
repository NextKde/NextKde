#pragma once

#include <QImage>
#include <QPointF>
#include <QRectF>
#include <QString>
#include <QVector>

#include <optional>

#include "windowrules.h"

namespace KOS
{

enum class AdjustAction {
    None,
    ModeCover,
    ModeTransparent,
    ModeHidden,
    ScopeWindow,
    ScopeApp,
    Reset,
    Done,
};

enum class MatchScope {
    Window,
    App,
};

struct AdjustBarState {
    OverlayMode mode = OverlayMode::Cover;
    MatchScope scope = MatchScope::Window;
    bool canToggleScope = true;
    bool hasRole = false;
    bool hasExistingRule = false;
    bool dark = true;
    std::optional<AdjustAction> hovered;
};

struct AdjustBarButton {
    AdjustAction action = AdjustAction::None;
    QRectF rect; // Global or window-local coordinates matching AdjustBarLayout::rect
    bool enabled = true;
};

struct AdjustBarLayout {
    QRectF rect;
    QVector<AdjustBarButton> buttons;
    bool twoRows = false;

    bool isEmpty() const { return rect.isEmpty(); }
};

AdjustBarLayout adjustBarLayout(const QRectF &panelRect, const QRectF &windowRect,
                                bool canToggleScope, bool hasExistingRule);

std::optional<AdjustAction> adjustBarActionAt(const AdjustBarLayout &layout,
                                              const QPointF &point);

QImage buildAdjustBar(qreal scale, const AdjustBarLayout &layout,
                      const AdjustBarState &state);

QString adjustBarTextureKey(qreal scale, const AdjustBarLayout &layout,
                            const AdjustBarState &state);

} // namespace KOS
