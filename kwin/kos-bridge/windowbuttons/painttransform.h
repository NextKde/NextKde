#pragma once

#include <QtGlobal>

namespace KOS
{

// State of the pixels underneath the panel, copied from WindowPaintData.
struct PaintTransform {
    qreal xScale = 1.0;
    qreal yScale = 1.0;
    qreal zScale = 1.0;
    qreal xTranslate = 0.0;
    qreal yTranslate = 0.0;
    qreal zTranslate = 0.0;
    qreal rotationAngle = 0.0;
    qreal opacity = 1.0;
    qreal brightness = 1.0;
    qreal saturation = 1.0;
    bool transformed = false;

    bool isIdentityGeometry() const {
        return qFuzzyCompare(xScale, qreal(1))
            && qFuzzyCompare(yScale, qreal(1))
            && qFuzzyCompare(zScale, qreal(1))
            && qFuzzyIsNull(xTranslate)
            && qFuzzyIsNull(yTranslate)
            && qFuzzyIsNull(zTranslate)
            && qFuzzyIsNull(rotationAngle);
    }

    bool isNeutral() const {
        return isIdentityGeometry()
            && qFuzzyCompare(opacity, qreal(1))
            && qFuzzyCompare(brightness, qreal(1))
            && qFuzzyCompare(saturation, qreal(1));
    }

    bool canSampleTitlebar() const {
        return !transformed && isNeutral();
    }

    bool canPaintOverlay() const {
        return qFuzzyCompare(zScale, qreal(1))
            && qFuzzyIsNull(zTranslate)
            && qFuzzyIsNull(rotationAngle)
            && opacity > 0.0;
    }
};

} // namespace KOS
