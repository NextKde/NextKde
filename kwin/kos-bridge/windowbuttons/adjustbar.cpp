#include "adjustbar.h"

#include <QFont>
#include <QLocale>
#include <QPainter>
#include <QPainterPath>

#include <algorithm>
#include <cmath>

namespace KOS
{
namespace
{
constexpr int Supersample = 4;
constexpr qreal BarPadX = 6.0;
constexpr qreal BarPadY = 4.0;
constexpr qreal ChipHeight = 22.0;
constexpr qreal ChipRadius = 6.0;
constexpr qreal BarRadius = 10.0;
constexpr qreal Gap = 3.0;
constexpr qreal RowGap = 4.0;
constexpr qreal GroupGap = 9.0;
constexpr qreal BarInset = 6.0;
constexpr qreal PanelGap = 6.0;

constexpr qreal ModeWidth = 42.0;
constexpr qreal ScopeWidth = 48.0;
constexpr qreal IconWidth = 24.0;

bool useChineseLabels()
{
    const QString name = QLocale::system().name();
    return name.startsWith(QLatin1String("zh"), Qt::CaseInsensitive);
}

QString actionLabel(AdjustAction action, bool hasRole, bool zh)
{
    switch (action) {
    case AdjustAction::ModeCover:
        return zh ? QStringLiteral("遮罩") : QStringLiteral("Cover");
    case AdjustAction::ModeTransparent:
        return zh ? QStringLiteral("透明") : QStringLiteral("Bare");
    case AdjustAction::ModeHidden:
        return zh ? QStringLiteral("隐藏") : QStringLiteral("Hide");
    case AdjustAction::ScopeWindow:
        if (hasRole) return zh ? QStringLiteral("本角色") : QStringLiteral("Role");
        return zh ? QStringLiteral("此标题") : QStringLiteral("Title");
    case AdjustAction::ScopeApp:
        return zh ? QStringLiteral("同应用") : QStringLiteral("App");
    case AdjustAction::Reset:
    case AdjustAction::Done:
    case AdjustAction::None:
        break;
    }
    return {};
}

void drawResetGlyph(QPainter &painter, const QRectF &rect, const QColor &color)
{
    const QPointF c = rect.center();
    const qreal r = 4.6;
    painter.save();
    painter.setPen(QPen(color, 1.35, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    painter.setBrush(Qt::NoBrush);
    painter.drawArc(QRectF(c.x() - r, c.y() - r, 2 * r, 2 * r), 120 * 16, -280 * 16);
    QPainterPath head;
    head.moveTo(c.x() - r + 0.5, c.y() - r + 1.5);
    head.lineTo(c.x() - r - 2.2, c.y() - r + 4.4);
    head.lineTo(c.x() - r + 2.4, c.y() - r + 4.2);
    head.closeSubpath();
    painter.setPen(Qt::NoPen);
    painter.setBrush(color);
    painter.drawPath(head);
    painter.restore();
}

void drawDoneGlyph(QPainter &painter, const QRectF &rect, const QColor &color)
{
    const QPointF c = rect.center();
    painter.save();
    painter.setPen(QPen(color, 1.5, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    painter.setBrush(Qt::NoBrush);
    QPainterPath check;
    check.moveTo(c.x() - 4.2, c.y() + 0.2);
    check.lineTo(c.x() - 1.2, c.y() + 3.2);
    check.lineTo(c.x() + 4.4, c.y() - 3.0);
    painter.drawPath(check);
    painter.restore();
}
} // namespace

AdjustBarLayout adjustBarLayout(const QRectF &panelRect, const QRectF &windowRect,
                                bool canToggleScope, bool hasExistingRule)
{
    AdjustBarLayout layout;
    const qreal maxAvailableW = windowRect.width() - 2.0 * BarInset;
    const qreal maxAvailableH = windowRect.height() - 2.0 * BarInset;
    if (maxAvailableW <= 0 || maxAvailableH <= 0) {
        return layout;
    }

    const qreal modeGroupW = 3.0 * ModeWidth + 2.0 * Gap;
    const qreal scopeGroupW = canToggleScope ? (2.0 * ScopeWidth + Gap) : 0.0;
    const qreal actionGroupW = 2.0 * IconWidth + Gap;

    const qreal singleW = 2.0 * BarPadX + modeGroupW + GroupGap
        + (canToggleScope ? scopeGroupW + GroupGap : 0.0) + actionGroupW;
    const qreal singleH = 2.0 * BarPadY + ChipHeight;

    const qreal twoRowW = 2.0 * BarPadX
        + std::max(modeGroupW, (canToggleScope ? scopeGroupW + GroupGap : 0.0) + actionGroupW);
    const qreal twoRowH = 2.0 * BarPadY + 2.0 * ChipHeight + RowGap;

    bool twoRows = false;
    qreal barW = singleW;
    qreal barH = singleH;
    if (singleW > maxAvailableW) {
        if (twoRowW > maxAvailableW) {
            return layout;
        }
        twoRows = true;
        barW = twoRowW;
        barH = twoRowH;
    }
    if (barH > maxAvailableH) {
        return layout;
    }

    const qreal minX = windowRect.left() + BarInset;
    const qreal maxX = windowRect.right() - BarInset - barW;
    const qreal x = std::clamp(panelRect.center().x() - barW / 2.0, minX, maxX);

    const qreal belowY = panelRect.bottom() + PanelGap;
    const qreal aboveY = panelRect.top() - PanelGap - barH;
    qreal y = belowY;
    if (belowY + barH > windowRect.bottom() - BarInset) {
        if (aboveY >= windowRect.top() + BarInset) {
            y = aboveY;
        } else {
            y = std::clamp(belowY, windowRect.top() + BarInset,
                           windowRect.bottom() - BarInset - barH);
        }
    }

    layout.rect = QRectF(x, y, barW, barH);
    layout.twoRows = twoRows;

    const qreal row1Y = y + BarPadY;
    qreal cx = x + BarPadX;
    for (AdjustAction a : {AdjustAction::ModeCover, AdjustAction::ModeTransparent, AdjustAction::ModeHidden}) {
        layout.buttons.append({a, QRectF(cx, row1Y, ModeWidth, ChipHeight), true});
        cx += ModeWidth + Gap;
    }

    qreal row2Y = row1Y;
    if (twoRows) {
        row2Y = row1Y + ChipHeight + RowGap;
        cx = x + BarPadX;
    } else {
        cx += GroupGap - Gap;
    }

    if (canToggleScope) {
        for (AdjustAction a : {AdjustAction::ScopeWindow, AdjustAction::ScopeApp}) {
            layout.buttons.append({a, QRectF(cx, row2Y, ScopeWidth, ChipHeight), true});
            cx += ScopeWidth + Gap;
        }
        cx += GroupGap - Gap;
    }

    layout.buttons.append({AdjustAction::Reset, QRectF(cx, row2Y, IconWidth, ChipHeight), hasExistingRule});
    cx += IconWidth + Gap;
    layout.buttons.append({AdjustAction::Done, QRectF(cx, row2Y, IconWidth, ChipHeight), true});

    return layout;
}

std::optional<AdjustAction> adjustBarActionAt(const AdjustBarLayout &layout,
                                              const QPointF &point)
{
    if (layout.isEmpty() || !layout.rect.contains(point)) {
        return std::nullopt;
    }
    for (const auto &btn : layout.buttons) {
        if (btn.enabled && btn.rect.contains(point)) {
            return btn.action;
        }
    }
    return std::nullopt;
}

QString adjustBarTextureKey(qreal scale, const AdjustBarLayout &layout,
                            const AdjustBarState &state)
{
    return QStringLiteral("adjustbar_%1x%2@%3_%4_%5_%6_%7_%8_%9_%10_%11")
        .arg(qRound(layout.rect.width() * scale))
        .arg(qRound(layout.rect.height() * scale))
        .arg(qRound(scale * 100))
        .arg(int(state.mode))
        .arg(int(state.scope))
        .arg(state.canToggleScope ? 1 : 0)
        .arg(state.hasRole ? 1 : 0)
        .arg(state.hasExistingRule ? 1 : 0)
        .arg(state.dark ? 1 : 0)
        .arg(layout.twoRows ? 1 : 0)
        .arg(state.hovered ? int(*state.hovered) : -1);
}

QImage buildAdjustBar(qreal scale, const AdjustBarLayout &layout,
                      const AdjustBarState &state)
{
    const QSizeF size = layout.rect.size();
    const QSize deviceSize(std::max(1, qRound(size.width() * scale)),
                           std::max(1, qRound(size.height() * scale)));
    const QSize superSize(deviceSize.width() * Supersample,
                          deviceSize.height() * Supersample);
    QImage superImage(superSize, QImage::Format_ARGB32_Premultiplied);
    superImage.fill(Qt::transparent);

    QPainter painter(&superImage);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setRenderHint(QPainter::TextAntialiasing, true);
    painter.scale(qreal(superSize.width()) / size.width(),
                  qreal(superSize.height()) / size.height());

    const QRectF box(QPointF(0, 0), size);
    const QColor surface = state.dark ? QColor(30, 31, 36, 245) : QColor(245, 245, 248, 245);
    const QColor border = state.dark ? QColor(255, 255, 255, 0x26) : QColor(0, 0, 0, 0x1F);
    painter.setPen(QPen(border, 0.75));
    painter.setBrush(surface);
    painter.drawRoundedRect(box.adjusted(0.375, 0.375, -0.375, -0.375), BarRadius, BarRadius);

    const bool zh = useChineseLabels();
    QFont font = painter.font();
    font.setPixelSize(10.5);
    font.setWeight(QFont::Medium);
    painter.setFont(font);

    const QColor accent(0x0A, 0x84, 0xFF);
    const QColor textPrimary = state.dark ? QColor(242, 242, 247) : QColor(28, 28, 32);
    const QColor textMuted = state.dark ? QColor(255, 255, 255, 90) : QColor(0, 0, 0, 80);
    const QColor chipHover = state.dark ? QColor(255, 255, 255, 0x22) : QColor(0, 0, 0, 0x14);
    const QColor chipIdle = state.dark ? QColor(255, 255, 255, 0x10) : QColor(0, 0, 0, 0x08);
    const QColor dividerColor = state.dark ? QColor(255, 255, 255, 0x1C) : QColor(0, 0, 0, 0x18);

    const auto isSelected = [&](AdjustAction a) {
        switch (a) {
        case AdjustAction::ModeCover:
            return state.mode == OverlayMode::Cover;
        case AdjustAction::ModeTransparent:
            return state.mode == OverlayMode::Transparent;
        case AdjustAction::ModeHidden:
            return state.mode == OverlayMode::Hidden;
        case AdjustAction::ScopeWindow:
            return state.scope == MatchScope::Window;
        case AdjustAction::ScopeApp:
            return state.scope == MatchScope::App;
        default:
            return false;
        }
    };

    const QPointF origin = layout.rect.topLeft();
    for (int i = 0; i < layout.buttons.size(); ++i) {
        const auto &btn = layout.buttons[i];
        const QRectF localRect = btn.rect.translated(-origin);
        const bool selected = isSelected(btn.action);
        const bool hovered = btn.enabled && state.hovered && *state.hovered == btn.action;

        QColor fill = chipIdle;
        if (selected) {
            fill = accent;
        } else if (btn.action == AdjustAction::Done) {
            fill = hovered ? QColor(0x28, 0xCD, 0x41) : QColor(0x28, 0xCD, 0x41, 0x2B);
        } else if (hovered) {
            fill = chipHover;
        }

        painter.setPen(Qt::NoPen);
        painter.setBrush(fill);
        painter.drawRoundedRect(localRect, ChipRadius, ChipRadius);

        const QColor fg = !btn.enabled ? textMuted
            : (selected || (btn.action == AdjustAction::Done && hovered))
                ? QColor(Qt::white)
                : (btn.action == AdjustAction::Done ? QColor(state.dark ? 0x30 : 0x1D, state.dark ? 0xD1 : 0x9F, state.dark ? 0x58 : 0x38) : textPrimary);

        if (btn.action == AdjustAction::Reset) {
            drawResetGlyph(painter, localRect, fg);
        } else if (btn.action == AdjustAction::Done) {
            drawDoneGlyph(painter, localRect, fg);
        } else {
            painter.setPen(fg);
            painter.drawText(localRect, Qt::AlignCenter,
                             actionLabel(btn.action, state.hasRole, zh));
        }

        // Draw subtle separators between button groups on single-row layout.
        if (!layout.twoRows && (btn.action == AdjustAction::ModeHidden
            || (state.canToggleScope && btn.action == AdjustAction::ScopeApp))) {
            const qreal divX = localRect.right() + GroupGap / 2.0;
            painter.setPen(QPen(dividerColor, 0.75));
            painter.drawLine(QPointF(divX, localRect.top() + 4.0),
                             QPointF(divX, localRect.bottom() - 4.0));
        }
    }

    painter.end();
    return superImage.scaled(deviceSize, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
}

} // namespace KOS
