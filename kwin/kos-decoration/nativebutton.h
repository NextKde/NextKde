#pragma once
#include <KDecoration3/DecorationButton>
namespace KOS {
class NativeButton final : public KDecoration3::DecorationButton {
public:
    NativeButton(KDecoration3::DecorationButtonType, KDecoration3::Decoration *, QObject *);
    void paint(QPainter *, const QRectF &) override;
};
}
