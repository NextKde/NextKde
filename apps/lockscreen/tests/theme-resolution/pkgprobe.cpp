// Does kscreenlocker actually load THIS lock screen?
//
// The skin is resolved from a **Plasma/Shell** package, never from the
// Look-and-Feel package. Two functions in the kscreenlocker 6.7.4 tree decide it:
//
//   settings/shell_integration.cpp
//       QString ShellIntegration::defaultShell() const
//       {
//           KSharedConfig::Ptr startupConf = KSharedConfig::openConfig(QStringLiteral("plasmashellrc"));
//           KConfigGroup startupConfGroup(startupConf, QStringLiteral("Shell"));
//           const QString defaultValue = qEnvironmentVariable("PLASMA_DEFAULT_SHELL", QStringLiteral("org.kde.plasma.desktop"));
//           QString value = startupConfGroup.readEntry("ShellPackage", defaultValue);
//           return value.isEmpty() ? defaultValue : value;
//       }
//
//   greeter/greeterapp.cpp
//       void UnlockApp::initialize()            { setShell(m_shellIntegration->defaultShell()); ... }
//       void UnlockApp::setShell(const QString &shell)
//       {
//           KPackage::Package package = KPackage::PackageLoader::self()->loadPackage(QStringLiteral("Plasma/Shell"));
//           if (!m_packageName.isEmpty()) package.setPath(m_packageName);
//           if (!verifyPackageApi(package)) {
//               qCWarning(KSCREENLOCKER_GREET) << "Lockscreen QML outdated, falling back to default";
//               package.setPath(QStringLiteral("org.kde.plasma.desktop"));
//           }
//           m_mainQmlPath = package.fileUrl("lockscreenmainscript");   // contents/lockscreen/LockScreen.qml
//       }
//
// So a custom lock screen needs BOTH conditions to hold:
//
//   1. plasmashellrc [Shell] ShellPackage names a package that lives in a
//      plasma/shells/ directory. The greeter loads the *shell* structure, and
//      ~/.local/share/plasma/look-and-feel/ is not searched at all. Shipping the
//      skin as a Look-and-Feel package (plus kdeglobals [KDE] LookAndFeelPackage
//      pointing at it) does nothing for the lock screen: the default shell
//      package org.kde.plasma.desktop owns a perfectly good
//      contents/lockscreen/LockScreen.qml, so nothing ever falls through to the
//      Look-and-Feel package.
//   2. That package's metadata.json carries a TOP-LEVEL X-Plasma-APIVersion >= 2.
//      verifyPackageApi() asks for exactly that key with a default of "1", and
//      KPluginMetaData::value() reads top-level keys only. Nested inside
//      "KPlugin" -- where it looks like it belongs -- the greeter sees "1", logs
//      "Lockscreen QML outdated, falling back to default" and quietly loads
//      org.kde.plasma.desktop instead. A locked session shows you nothing.
//
// Being wrong on either point looks identical on screen: the Breeze skin, whose
// WallpaperFader (org.kde.breeze.components) applies FastBlur { radius: 50 } to
// the wallpaper. Hence this test.
//
// Run it through run.sh, which hands the probe a throwaway HOME mirroring the
// real install. Exits 0 when the greeter would load *this* package's
// LockScreen.qml; nonzero (with the reason on stderr) otherwise.
#include <KConfigGroup>
#include <KPackage/Package>
#include <KPackage/PackageLoader>
#include <KSharedConfig>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QUrl>
#include <cstdio>

static bool ok = true;

static void say(const char *label, const QString &value)
{
    fprintf(stderr, "  %-26s %s\n", label, qPrintable(value));
}

static void check(bool condition, const char *what, const QString &detail)
{
    fprintf(stderr, "  %s %s%s\n", condition ? "ok  " : "FAIL", what,
            detail.isEmpty() ? "" : qPrintable(QStringLiteral(" -- ") + detail));
    if (!condition)
        ok = false;
}

// Verbatim from settings/shell_integration.cpp.
static QString defaultShell()
{
    KSharedConfig::Ptr startupConf = KSharedConfig::openConfig(QStringLiteral("plasmashellrc"));
    KConfigGroup startupConfGroup(startupConf, QStringLiteral("Shell"));
    const QString defaultValue = qEnvironmentVariable("PLASMA_DEFAULT_SHELL", QStringLiteral("org.kde.plasma.desktop"));
    const QString value = startupConfGroup.readEntry("ShellPackage", defaultValue);
    return value.isEmpty() ? defaultValue : value;
}

// Verbatim from greeter/greeterapp.cpp.
static bool verifyPackageApi(const KPackage::Package &package)
{
    if (package.metadata().value(QStringLiteral("X-Plasma-APIVersion"), QStringLiteral("1")).toInt() >= 2) {
        return true;
    }
    if (!package.filePath(QByteArrayLiteral("lockscreenmainscript")).contains(package.path())) {
        // The package does not contain the lock screen, so it is coming from the
        // fallback package; check that one's API version instead.
        if (package.fallbackPackage().metadata().value(QStringLiteral("X-Plasma-APIVersion"), QStringLiteral("1")).toInt() >= 2) {
            return true;
        }
    }
    return false;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);

    const QString shell = argc > 1 ? QString::fromLocal8Bit(argv[1]) : defaultShell();
    say("ShellPackage", shell);

    KPackage::Package package = KPackage::PackageLoader::self()->loadPackage(QStringLiteral("Plasma/Shell"));
    package.setPath(shell);

    check(package.isValid(), "resolves under a plasma/shells/ root", package.path());
    if (!package.isValid()) {
        say("hint", QStringLiteral("install the package into ~/.local/share/plasma/shells/%1").arg(shell));
        say("hint", QStringLiteral("look-and-feel/ is not searched for the lock screen"));
        return 1;
    }

    // The exact expression verifyPackageApi() evaluates.
    const QString apiVersion = package.metadata().value(QStringLiteral("X-Plasma-APIVersion"), QStringLiteral("1"));
    say("apiVersion (as read)", apiVersion);
    check(apiVersion.toInt() >= 2, "X-Plasma-APIVersion >= 2 reached KPluginMetaData",
          QStringLiteral("value() sees top-level metadata.json keys only -- keep the key a sibling of KPlugin"));

    const QString skin = package.filePath(QByteArrayLiteral("lockscreenmainscript"));
    check(!skin.isEmpty() && QFileInfo::exists(skin), "lockscreenmainscript is a real file", skin);
    check(skin.endsWith(QStringLiteral("contents/lockscreen/LockScreen.qml")),
          "it is contents/lockscreen/LockScreen.qml", QString());
    check(skin.startsWith(package.path()),
          "the file belongs to this package", skin.startsWith(package.path()) ? QString()
          : QStringLiteral("came from the fallback package %1").arg(package.fallbackPackage().path()));

    // What the greeter ends up handing to the view.
    if (!verifyPackageApi(package)) {
        fprintf(stderr, "  note verifyPackageApi() failed -> falling back to org.kde.plasma.desktop\n");
        package.setPath(QStringLiteral("org.kde.plasma.desktop"));
    }
    const QUrl loaded = package.fileUrl(QByteArrayLiteral("lockscreenmainscript"));
    say("greeter would load", loaded.toString());

    if (ok) {
        fprintf(stderr, "  => this package is the lock screen\n");
    } else {
        fprintf(stderr, "  => the lock screen is NOT this package (expect KDE's Breeze skin,\n"
                        "     whose WallpaperFader blurs the wallpaper at radius 50)\n");
    }
    return ok ? 0 : 1;
}
