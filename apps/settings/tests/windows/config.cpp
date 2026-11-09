#include "WindowSettings.h"
#include "../../../../platform/src/windowanimation/NativeGenie.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <KSharedConfig>
#include <KConfigGroup>
#include <cstdlib>
#include <QProcess>
#include <QTextStream>
#include <QLockFile>
#define CHECK(x) do { if (!(x)) { qFatal("Failed line %d: %s", __LINE__, #x); } } while (false)
int main(int argc, char **argv) {
    if (argc == 2) {
        QCoreApplication app(argc, argv);
        WindowSettings settings;
        if (app.arguments()[1] == "--install-defaults") CHECK(settings.installDefaults());
        QTextStream(stdout) << QJsonDocument(QJsonObject::fromVariantMap(settings.state())).toJson(QJsonDocument::Compact);
        return 0;
    }
    QTemporaryDir temporary;
    CHECK(temporary.isValid());
    qputenv("XDG_CONFIG_HOME", temporary.path().toUtf8());
    qputenv("GSETTINGS_BACKEND", "keyfile");
    qputenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-kos-test-bus");
    QCoreApplication app(argc, argv);
    QDir().mkpath(temporary.path() + "/kos");
    QDir().mkpath(temporary.path() + "/gtk-3.0");
    const QString gtkCss = temporary.path() + "/gtk-3.0/gtk.css";
    { QFile file(gtkCss); CHECK(file.open(QIODevice::WriteOnly)); file.write("/* personal GTK style */\n"); }
    auto gtkStyle = [&]() { QFile file(gtkCss); CHECK(file.open(QIODevice::ReadOnly)); return file.readAll(); };
    const QString filename = temporary.path() + "/kos/window-appearance.json";
    auto put = [&](const QByteArray &bytes) { QFile f(filename); CHECK(f.open(QIODevice::WriteOnly)); CHECK(f.write(bytes)==bytes.size()); };
    auto get = [&]() { QFile f(filename); CHECK(f.open(QIODevice::ReadOnly)); return f.readAll(); };
    put(R"({"version":2,"revision":7,"extra":"keep","apps":{"demo":{"enabled":false}},"defaults":{"corners":{"radius":20,"extra":42},"states":{"fullscreen":"off","tiled":"square","extra":42}}})");
    WindowSettings settings;
    CHECK(settings.setRadius(28));
    CHECK(settings.setShadow(false));
    auto json=QJsonDocument::fromJson(get()).object();
    CHECK(json["extra"]=="keep"); CHECK(json["apps"].toObject().contains("demo"));
    CHECK(json["revision"].toInt()==9);
    CHECK(json["defaults"].toObject()["corners"].toObject()["extra"].toInt()==42);
    CHECK(settings.state()["radius"].toInt()==28);
    CHECK(!settings.state()["shadow"].toBool());
    CHECK(!settings.state()["squareMaximized"].toBool());
    CHECK(settings.setSquareMaximized(true));
    CHECK(settings.state()["squareMaximized"].toBool());
    json=QJsonDocument::fromJson(get()).object();
    const auto states=json["defaults"].toObject()["states"].toObject();
    CHECK(states["maximized"]=="square");
    CHECK(states["fullscreen"]=="off"); CHECK(states["tiled"]=="square");
    CHECK(states["extra"].toInt()==42);
    CHECK(settings.state()["radius"].toInt()==28);
    CHECK(!settings.state()["shadow"].toBool());
    CHECK(json["extra"]=="keep"); CHECK(json["apps"].toObject().contains("demo"));
    CHECK(settings.setSquareMaximized(false));
    CHECK(!settings.state()["squareMaximized"].toBool());
    CHECK(QJsonDocument::fromJson(get()).object()["defaults"].toObject()["states"].toObject()["maximized"]=="inherit");
    CHECK(settings.setSquareMaximized(true));
    auto config=KSharedConfig::openConfig("kwinrc");
    KConfigGroup decoration(config,"org.kde.kdecoration2");
    decoration.writeEntry("library", "third_party"); decoration.writeEntry("theme", "theme-a"); CHECK(config->sync());
    CHECK(settings.installDefaults());
    CHECK(settings.state()["decoration"]=="kos_decoration");
    CHECK(gtkStyle().contains("kos_native_controls"));
    CHECK(gtkStyle().contains("personal GTK style"));
    // Exercise the embedded installer, not a source-only mock. It must not
    // send Chromium/GTK originals to the opposite side of KOS overlays.
    for (const auto &version : {"3.0", "4.0"}) {
        QFile ini(temporary.path() + "/gtk-" + QString::fromLatin1(version) + "/settings.ini");
        CHECK(ini.open(QIODevice::ReadOnly));
        const auto lines = QString::fromUtf8(ini.readAll()).split('\n');
        bool found = false;
        for (const auto &line : lines) if (line.startsWith("gtk-decoration-layout=")) {
            found = true;
            const auto parts = line.section('=', 1).split(':');
            CHECK(parts.size() == 2);
            for (const auto &action : {"close", "minimize", "maximize"}) {
                CHECK(!parts[0].split(',').contains(QString::fromLatin1(action)));
                CHECK(parts[1].split(',').contains(QString::fromLatin1(action)));
            }
        }
        CHECK(found);
    }

    CHECK(settings.setButtonGlyphMode("hover"));
    CHECK(gtkStyle().contains("opacity: 0"));
    CHECK(settings.setButtonGlyphMode("always"));
    CHECK(!gtkStyle().contains("opacity: 0;"));
    CHECK(settings.setTakeover(false));
    CHECK(gtkStyle()=="/* personal GTK style */\n");
    CHECK(settings.state()["decoration"]=="third_party");
    CHECK(decoration.readEntry("theme", QString())=="theme-a");
    CHECK(settings.installDefaults()); // upgrade must preserve opt-out
    CHECK(!settings.state()["enabled"].toBool());
    CHECK(settings.setTakeover(true));
    CHECK(gtkStyle().contains("kos_native_controls"));
    // Repeated startup/upgrade sync keeps the choice and does not duplicate CSS.
    CHECK(settings.installDefaults());
    CHECK(gtkStyle().count("NextKde native GTK buttons: begin")==1);
    decoration.writeEntry("library", "changed_externally"); CHECK(config->sync());
    CHECK(settings.setTakeover(false));
    CHECK(settings.state()["decoration"]=="changed_externally");
    CHECK(gtkStyle()=="/* personal GTK style */\n");
    CHECK(settings.setAnimation("close", "fade"));
    CHECK(settings.setAnimation("hide", "none"));
    CHECK(settings.state()["closeAnimation"]=="fade");
    CHECK(settings.state()["hideAnimation"]=="none");
    // An offline upgrade must retain a usable animation, not silently turn off
    // the removed water-drop path. Genie intent is retained for later recovery.
    CHECK(settings.setAnimation("hide", "genie"));
    CHECK(settings.state()["hideAnimation"]=="genie");
    CHECK(!settings.state()["nativeGenieFallback"].toString().isEmpty());
    KConfigGroup offlineAnimation(config, "Effect-kos_dock_window_animation");
    CHECK(offlineAnimation.readEntry("HideAnimation", QString())=="scale");
    CHECK(settings.setAnimation("hide", "none"));

    KConfigGroup plugins(config, "Plugins");
    plugins.writeEntry("magiclampEnabled", false);
    plugins.writeEntry("squashEnabled", true);
    plugins.writeEntry("blurEnabled", true);
    CHECK(config->sync());
    CHECK(KOS::WindowAnimation::configure(config, "genie"));
    KConfigGroup animation(config, "Effect-kos_dock_window_animation");
    CHECK(KOS::WindowAnimation::selection(config)=="genie");
    CHECK(animation.readEntry("HideAnimation", QString())=="none");
    CHECK(plugins.readEntry("magiclampEnabled", false));
    CHECK(!plugins.readEntry("squashEnabled", true));
    CHECK(plugins.readEntry("blurEnabled", false));
    CHECK(KOS::WindowAnimation::configure(config, "scale"));
    CHECK(!plugins.readEntry("magiclampEnabled", true));
    CHECK(animation.readEntry("HideAnimation", QString())=="scale");
    CHECK(KOS::WindowAnimation::configure(config, "none"));
    CHECK(!plugins.readEntry("magiclampEnabled", true));
    CHECK(plugins.readEntry("squashEnabled", false));
    CHECK(!animation.hasKey("NativeEffectsManaged"));
    // Missing keys must restore the compositor's default, not a guessed false.
    plugins.deleteEntry("magiclampEnabled");
    plugins.deleteEntry("squashEnabled");
    CHECK(config->sync());
    CHECK(KOS::WindowAnimation::configure(config, "genie"));
    CHECK(KOS::WindowAnimation::configure(config, "none"));
    CHECK(!plugins.hasKey("magiclampEnabled"));
    CHECK(!plugins.hasKey("squashEnabled"));
    CHECK(settings.state()["buttonGlyphMode"]=="always");
    CHECK(settings.setButtonGlyphMode("hover"));
    CHECK(settings.state()["buttonGlyphMode"]=="hover");
    CHECK(!settings.setButtonGlyphMode("invalid"));
    CHECK(settings.state()["buttonGlyphMode"]=="hover");
    QProcess reopened;
    reopened.start(QCoreApplication::applicationFilePath(), {"--install-defaults"});
    CHECK(reopened.waitForFinished(5000)); CHECK(reopened.exitCode()==0);
    const auto persisted=QJsonDocument::fromJson(reopened.readAllStandardOutput()).object();
    CHECK(persisted["hideAnimation"]=="none"); CHECK(persisted["closeAnimation"]=="fade");
    CHECK(persisted["buttonGlyphMode"]=="hover");
    CHECK(persisted["radius"].toInt()==28); CHECK(!persisted["shadow"].toBool());
    CHECK(persisted["squareMaximized"].toBool());
    CHECK(!persisted["enabled"].toBool()); CHECK(persisted["decoration"]=="changed_externally");
    const auto saved=get();
    CHECK(!settings.setRadius(-1)); CHECK(!settings.setRadius(201)); CHECK(get()==saved);
    { QLockFile lock(filename+".lock"); CHECK(lock.tryLock(0)); CHECK(!settings.setShadow(true)); CHECK(get()==saved); }
    { QLockFile lock(filename+".lock"); CHECK(lock.tryLock(0)); CHECK(!settings.setSquareMaximized(false)); CHECK(get()==saved); }
    CHECK(!settings.setAnimation("close", "genie"));
    CHECK(settings.state()["closeAnimation"]=="fade");
    put("malformed"); CHECK(!settings.setRadius(12)); CHECK(get()=="malformed");
    CHECK(!settings.setSquareMaximized(true)); CHECK(get()=="malformed");
    put(R"({"version":1,"defaults":{"stroke":{"width":1}}})");
    CHECK(settings.setRadius(8)); json=QJsonDocument::fromJson(get()).object();
    CHECK(json["version"].toInt()==1);
    CHECK(json["defaults"].toObject()["stroke"].toObject()["width"].toInt()==1);
    const auto beforeGtkFailure = get();
    const QString managedCss = temporary.path() + "/managed.css";
    { QFile file(managedCss); CHECK(file.open(QIODevice::WriteOnly)); file.write("managed externally"); }
    CHECK(QFile::remove(gtkCss));
    CHECK(QFile::link(managedCss, gtkCss));
    CHECK(!settings.setTakeover(true));
    CHECK(get()==beforeGtkFailure);
    CHECK(gtkStyle()=="managed externally");
    const QString buttonsPath = temporary.path() + "/kos/window-buttons.json";
    auto putButtons = [&](const QByteArray &data) { QFile file(buttonsPath); CHECK(file.open(QIODevice::WriteOnly)); CHECK(file.write(data) == data.size()); };
    auto getButtons = [&]() { QFile file(buttonsPath); CHECK(file.open(QIODevice::ReadOnly)); return file.readAll(); };
    putButtons(R"({"extra":42,"default":{"buttonSize":30},"apps":{"demo":{"buttonSize":24}},"rules":[{"match":{"class":"demo"},"buttonSize":26}]})");
    CHECK(!settings.state()["independentButtonBackground"].toBool());
    CHECK(settings.setIndependentButtonBackground(true));
    CHECK(settings.state()["independentButtonBackground"].toBool());
    const auto coverDoc = QJsonDocument::fromJson(getButtons()).object();
    CHECK(coverDoc["extra"].toInt() == 42);
    CHECK(coverDoc["default"].toObject()["buttonSize"].toInt() == 30);
    CHECK(coverDoc["apps"].toObject()["demo"].toObject()["buttonSize"].toInt() == 24);
    CHECK(coverDoc["rules"].isArray());
    WindowSettings reread;
    CHECK(reread.state()["independentButtonBackground"].toBool());
    CHECK(settings.setIndependentButtonBackground(false));
    CHECK(!settings.state()["independentButtonBackground"].toBool());
    const auto beforeCoverFailure = getButtons();
    { QLockFile lock(buttonsPath + ".lock"); CHECK(lock.tryLock(0)); CHECK(!settings.setIndependentButtonBackground(true)); }
    CHECK(getButtons() == beforeCoverFailure);
    putButtons("malformed");
    CHECK(!settings.setIndependentButtonBackground(true));
    CHECK(getButtons() == "malformed");
    qInfo("Window settings configuration checks passed");
}
