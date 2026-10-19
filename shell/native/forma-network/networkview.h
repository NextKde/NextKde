#pragma once
#include <QQuickRhiItem>
#include <QColor>
#include <QTimer>
#include <QVariantMap>
#include <QImage>
#include <QHash>
#include <vector>
#include "mayonnaise/events.hpp"

class NetworkRenderer;
class NetworkView : public QQuickRhiItem {
    Q_OBJECT
    Q_PROPERTY(QVariantMap snapshot READ snapshot WRITE setSnapshot NOTIFY snapshotChanged)
    Q_PROPERTY(bool detailsExpanded READ detailsExpanded WRITE setDetailsExpanded NOTIFY detailsExpandedChanged)
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY darkChanged)
    Q_PROPERTY(QColor ink READ ink WRITE setInk NOTIFY inkChanged)
    Q_PROPERTY(QColor mutedInk READ mutedInk WRITE setMutedInk NOTIFY mutedInkChanged)
    Q_PROPERTY(QSize renderedPixelSize READ renderedPixelSize NOTIFY diagnosticsChanged)
    Q_PROPERTY(int nativeComponentCount READ nativeComponentCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(int renderedFrames READ renderedFrames NOTIFY diagnosticsChanged)
    Q_PROPERTY(qreal scrollOffset READ scrollOffset NOTIFY diagnosticsChanged)
public:
    explicit NetworkView(QQuickItem *parent = nullptr);
    QVariantMap snapshot() const { return m_snapshot; }
    void setSnapshot(const QVariantMap &);
    bool detailsExpanded() const { return m_details; }
    void setDetailsExpanded(bool);
    bool dark() const { return m_dark; }
    void setDark(bool);
    QColor ink() const { return m_ink; }
    void setInk(const QColor &);
    QColor mutedInk() const { return m_muted; }
    void setMutedInk(const QColor &);
    QSize renderedPixelSize() const { return m_pixels; }
    int nativeComponentCount() const { return m_components; }
    int renderedFrames() const { return m_frames; }
    qreal scrollOffset() const { return m_scrollOffset; }
    QQuickRhiItemRenderer *createRenderer() override;
signals:
    void snapshotChanged();
    void detailsExpandedChanged();
    void darkChanged();
    void inkChanged();
    void mutedInkChanged();
    void diagnosticsChanged();
    void closeRequested();
    void detailsToggleRequested();
    void refreshRequested();
    void resetTotalsRequested();
protected:
    void mousePressEvent(QMouseEvent *) override;
    void mouseReleaseEvent(QMouseEvent *) override;
    void mouseMoveEvent(QMouseEvent *) override;
    void hoverEnterEvent(QHoverEvent *) override;
    void hoverMoveEvent(QHoverEvent *) override;
    void hoverLeaveEvent(QHoverEvent *) override;
    void wheelEvent(QWheelEvent *) override;
    void keyPressEvent(QKeyEvent *) override;
    void focusOutEvent(QFocusEvent *) override;
private:
    friend class NetworkRenderer;
    struct Input {
        enum Type { Press, Release, Move, Leave, Scroll, Key, Cancel } type;
        mayo::PointerEvent pointer;
        mayo::ScrollEvent scroll;
        mayo::KeyEvent key;
    };
    void enqueue(Input);
    void scheduleWake(int milliseconds);
    /// Whether p lies on a control that reacts to hover. Moves elsewhere cannot
    /// change the native scene, so they do not need to damage the popup surface
    /// (and the compositor glass behind it) at pointer rate.
    bool hoverTarget(QPointF p) const;
    QVariantMap m_snapshot;
    /// Last map accepted from QML, before icon resolution. The renderer compares
    /// revisions, so neither thread repeats a deep compare on every frame.
    QVariantMap m_source, m_translations;
    bool m_hasSnapshot = false;
    quint64 m_revision = 0, m_translationsRevision = 0;
    bool m_details = false, m_dark = true;
    QColor m_ink = Qt::white, m_muted = QColor("#c4c4c4");
    QSize m_pixels;
    int m_components = 0, m_frames = 0;
    qreal m_scrollOffset = 0;
    std::vector<Input> m_input;
    std::vector<mayo::Rect> m_hoverRects;
    bool m_hoverRectsReady = false, m_lastHoverSensitive = false;
    QTimer m_wake;
    QHash<QString, QImage> m_icons;
    qulonglong m_iconRevision = 0;
};
