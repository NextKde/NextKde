#pragma once

#include <KDecoration3/Decoration>

// The QVariantList default argument below is instantiated by moc, which needs
// QVariant complete rather than merely forward-declared.
#include <QVariant>

namespace KOS
{

// The KOS window decoration: a thin frame with nothing drawn in it.
//
// It draws the title bar and the caption and stops there. No buttons and no
// glass on purpose: the three-dot panel over server-side decorated windows is
// drawn by the kos-bridge effect, which reads this title bar back to choose the
// panel's tint, so a translucent bar over the compositor's blur would tint the
// panel from something other than the window's own colour. The liquid material
// the plugin used to paint has been dropped with it.
//
// The window's own shape is left alone as well -- no setBorderRadius(), no
// setBorderOutline(), square corners painted here. See updateLayout() for why;
// briefly, setBorderRadius() is how KWin clips the whole window, so calling it
// would override the rounding and outline the user set on the decoration they
// came from.
class KosDecoration final : public KDecoration3::Decoration
{
    Q_OBJECT

public:
    explicit KosDecoration(QObject *parent = nullptr, const QVariantList &args = {});
    ~KosDecoration() override;

    bool init() override;
    void paint(QPainter *painter, const QRectF &repaintArea) override;

private:
    // Borders are double-buffered through DecorationState: borderTop() still
    // reports the previous value right after setBorders(). So the buffered
    // properties are written here...
    void updateLayout();
    // ...and everything derived from the applied geometry is written from
    // here, which also runs on bordersChanged() once the compositor has taken
    // the new state.
    void updateDerivedGeometry();

    QColor barColor() const;
    QColor captionColor() const;

    void paintTitleBar(QPainter *painter);
    void paintCaption(QPainter *painter);
};

} // namespace KOS
