#pragma once

#include <QString>
#include <functional>

namespace KosPlatform {

// Keeps Plasma's wallpaper-colour setting usable while KOS displays the full
// image. Plasma receives a tiny light/dark wallpaper package whose metadata
// carries the accent sampled from the original image.
class PlasmaWallpaperAdapter final {
public:
    static void showDesktop(bool showing,
        std::function<void(bool, bool, const QString &)> completion);
    static bool applyProxy(const QString &accent, bool dark, int screenCount,
                           QString *error);
    static bool restoreImage(const QString &imagePath, int screenCount,
                             QString *error);
};

} // namespace KosPlatform
