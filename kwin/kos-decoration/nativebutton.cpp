#include "nativebutton.h"
#include "kosdecoration.h"
#include "../kos-bridge/windowbuttons/buttonglyph.h"
#include <KDecoration3/DecoratedWindow>
#include <QPainter>

namespace KOS {
using ButtonType = KDecoration3::DecorationButtonType;
NativeButton::NativeButton(ButtonType type, KDecoration3::Decoration *decoration, QObject *parent)
    : DecorationButton(type, decoration, parent)
{
    setGeometry(QRectF(0, 0, type == ButtonType::Spacer ? 10 : 28, 28));
    if (type == ButtonType::Close || type == ButtonType::Minimize || type == ButtonType::Maximize)
        setAcceptedButtons(Qt::LeftButton); // Green always toggles full maximize/restore.
    setObjectName(type == ButtonType::Close ? "close" : type == ButtonType::Minimize ? "minimize"
        : type == ButtonType::Maximize ? "maximize" : "auxiliary");
    const auto repaint = [decoration] { decoration->update(); };
    connect(this, &DecorationButton::hoveredChanged, decoration, repaint);
    connect(this, &DecorationButton::pressedChanged, decoration, repaint);
    connect(this, &DecorationButton::checkedChanged, decoration, repaint);
    connect(this, &DecorationButton::enabledChanged, decoration, repaint);
}
void NativeButton::paint(QPainter *painter, const QRectF &)
{
    if (!isVisible() || type() == ButtonType::Spacer) return;
    auto *owner = static_cast<KosDecoration *>(decoration());
    auto *client = owner->window();
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    const QPointF center = geometry().center();
    const QRectF dot(center-QPointF(7,7), QSizeF(14,14));
    if (type() == ButtonType::Close || type() == ButtonType::Minimize || type() == ButtonType::Maximize) {
        const Type light = type() == ButtonType::Close ? Close : type() == ButtonType::Minimize ? Minimize : Maximize;
        if (isHovered()) drawHoverRing(*painter, dot, light, client->palette().color(QPalette::Window).lightness()<128);
        if (isPressed()) painter->setOpacity(.8);
        drawLight(*painter, dot, light, client->isActive() && isEnabled(), client->isMaximized(), owner->showButtonGlyphs());
    } else {
        // Preserve KDE's optional menu/pin/shade/stacking actions and input.
        painter->setPen(QPen(client->palette().color(QPalette::WindowText), 1.5));
        if (!isEnabled()) painter->setOpacity(.4);
        painter->setBrush(isChecked() ? painter->pen().color() : Qt::transparent);
        const QRectF mark(center-QPointF(5,5), QSizeF(10,10));
        switch (type()) {
        case ButtonType::Menu:
        case ButtonType::ApplicationMenu:
            for (int y : {-4,0,4}) painter->drawLine(center+QPointF(-5,y),center+QPointF(5,y));
            break;
        case ButtonType::KeepAbove:
        case ButtonType::KeepBelow: {
            const int direction = type() == ButtonType::KeepAbove ? -1 : 1;
            painter->drawPolyline(QPolygonF{center+QPointF(-5,-direction*3),center+QPointF(0,direction*3),center+QPointF(5,-direction*3)});
            break;
        }
        case ButtonType::Shade:
            painter->drawRect(mark); painter->drawLine(mark.topLeft()+QPointF(0,3), mark.topRight()+QPointF(0,3)); break;
        case ButtonType::OnAllDesktops:
            painter->drawEllipse(mark.adjusted(2,0,-2,-4)); painter->drawLine(center,center+QPointF(0,6)); break;
        case ButtonType::ContextHelp:
            painter->drawText(geometry(), Qt::AlignCenter, QStringLiteral("?")); break;
        default: painter->drawRect(mark); break;
        }
    }
    painter->restore();
}
}
