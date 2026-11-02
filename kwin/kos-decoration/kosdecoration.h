#pragma once

#include <KDecoration3/Decoration>

// The QVariantList default argument below is instantiated by moc, which needs
// QVariant complete rather than merely forward-declared.
#include <QVariant>
#include <QFileSystemWatcher>
#include <KDecoration3/DecorationButtonGroup>

namespace KOS
{

// Native server-side frame and controls; Bridge supplies only appearance policy.
class KosDecoration final : public KDecoration3::Decoration
{
    Q_OBJECT

public:
    explicit KosDecoration(QObject *parent = nullptr, const QVariantList &args = {});
    ~KosDecoration() override;

    bool init() override;
    void paint(QPainter *painter, const QRectF &repaintArea) override;

public:
    bool showButtonGlyphs() const;

private:
    void refreshButtonPreferences();
    bool event(QEvent *event) override;
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
    KDecoration3::DecorationButtonGroup *m_leftButtons = nullptr;
    KDecoration3::DecorationButtonGroup *m_rightButtons = nullptr;
    QFileSystemWatcher m_buttonWatcher;
    bool m_hoverGlyphs = false;
    bool m_updatingGeometry = false;
    bool m_bridgeShadowActive = false;
    std::shared_ptr<KDecoration3::DecorationShadow> m_shadowBeforeBridge;
};

} // namespace KOS
