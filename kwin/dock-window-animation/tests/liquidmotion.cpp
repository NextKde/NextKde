#include "../liquidmotion.h"
#include <QDebug>
#include <QLineF>

int main()
{
    const QList<QRectF> windows{QRectF(200, 80, 1280, 720), QRectF(-1600, -300, 840, 900)};
    const QList<QRectF> targets{QRectF(920, 1000, 56, 56), QRectF(-1840, 500, 48, 64)};
    const auto check = [](bool value, const char *message) {
        if (!value) qFatal("Liquid motion: %s", message);
    };
    for (const auto &window : windows) {
        for (const auto &target : targets) {
            check(KOS::liquidMotion(window, target, -1).geometry == window, "window endpoint");
            check(KOS::liquidMotion(window, target, 2).geometry == target, "icon endpoint");
            qreal previousAlpha = 0;
            QSizeF previousSize = window.size();
            qreal previousDistance = QLineF(window.center(), target.center()).length();
            const auto envelope = window.united(target).adjusted(-10, -10, 10, 10);
            for (int i = 0; i <= 1000; ++i) {
                const qreal p = i / 1000.0;
                const auto pose = KOS::liquidMotion(window, target, p);
                check(pose.geometry.isValid() && std::isfinite(pose.geometry.x())
                    && std::isfinite(pose.geometry.y()), "finite positive geometry");
                check(envelope.contains(pose.geometry), "motion stays in repaint envelope");
                check(pose.iconOpacity >= previousAlpha && pose.iconOpacity <= 1,
                    "monotonic crossfade");
                check(qFuzzyCompare(pose.windowOpacity() + pose.iconOpacity, 1.0), "crossfade sum");
                if (p >= 1.0 - 55.0 / 240) check(pose.windowOpacity() == 0, "window draw ends at handoff");
                const qreal maxRadius = std::min(pose.geometry.width(), pose.geometry.height()) * 0.24;
                check(pose.topRadius > 0 && pose.bottomRadius > 0
                    && pose.topRadius <= maxRadius && pose.bottomRadius <= maxRadius,
                    "both corner radii fit the animated body");
                if (p >= 1.0) {
                    check(pose.artworkOpacity() == 0, "arrived icon does not double-paint Dock artwork");
                    check(pose.geometry == target, "no oscillation after arrival");
                    check(pose.windowOpacity() == 0, "Dock merge does not resurrect window content");
                }
                if (window.width() >= target.width() && window.height() >= target.height()) {
                    check(pose.geometry.width() <= previousSize.width() + 1e-8
                        && pose.geometry.height() <= previousSize.height() + 1e-8,
                        "size shrinks monotonically through icon handoff and flight");
                }
                const qreal distance = QLineF(pose.geometry.center(), target.center()).length();
                check(distance <= previousDistance + 1e-8,
                    "center approaches Dock monotonically, never flies back out");
                previousDistance = distance;
                previousSize = pose.geometry.size();
                previousAlpha = pose.iconOpacity;
            }
            for (const int duration : {160, 300, 1200}) {
                const qreal start = 1.0 - 80.0 / duration;
                check(KOS::liquidMotion(window, target, start, duration).iconOpacity == 0,
                    "window remains visible until the final 80ms");
                check(KOS::liquidMotion(window, target, 1.0 - 55.0 / duration, duration).windowOpacity() < 1e-8,
                    "window crossfade ends 55ms before arrival");
            }
            const auto held = KOS::liquidMotion(window, target, 1.0 - 35.0 / 240);
            check(held.artworkOpacity() > 1.0 - 1e-8, "full icon remains visible before Dock merge");
            const auto middle = KOS::liquidMotion(window, target, 0.5);
            check(middle.iconOpacity == 0, "no mid-flight artwork replacement");
            check(middle.topRadius == middle.bottomRadius, "symmetric modest corners");
            for (const qreal boundary : {1.0 - 80.0 / 240, 1.0 - 55.0 / 240, 1.0}) {
                const auto before = KOS::liquidMotion(window, target, boundary - 1e-8);
                const auto after = KOS::liquidMotion(window, target, boundary + 1e-8);
                check(QLineF(before.geometry.center(), after.geometry.center()).length() < 0.001,
                    "continuous phase position");
                check(std::abs(before.geometry.width() - after.geometry.width()) < 0.001,
                    "continuous phase size");
            }
        }
    }
    qInfo("Liquid motion geometry and handoff checks passed");
}
