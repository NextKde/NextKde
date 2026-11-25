#pragma once

#include <QString>
#include <functional>

namespace KosPlatform {

// Keeps Plasma's wallpaper-colour setting usable while KOS displays the full
// image. While the Shell takes over, Plasma is given a plain black (dark
// theme) or white (light theme) wallpaper package: that is the login
// background until the Shell's own login screen paints, and the original
// wallpaper configuration is restored when the takeover ends.
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
