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
    qputenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-kos-test-bus");
    QCoreApplication app(argc, argv);
    QDir().mkpath(temporary.path() + "/kos");
    const QString filename = temporary.path() + "/kos/window-appearance.json";
    auto put = [&](const QByteArray &bytes) { QFile f(filename); CHECK(f.open(QIODevice::WriteOnly)); CHECK(f.write(bytes)==bytes.size()); };
    auto get = [&]() { QFile f(filename); CHECK(f.open(QIODevice::ReadOnly)); return f.readAll(); };
    put(R"({"version":2,"revision":7,"extra":"keep","apps":{"demo":{"enabled":false}},"defaults":{"corners":{"radius":20,"extra":42}}})");
    WindowSettings settings;
    CHECK(settings.setRadius(28));
    CHECK(settings.setShadow(false));
    auto json=QJsonDocument::fromJson(get()).object();
    CHECK(json["extra"]=="keep"); CHECK(json["apps"].toObject().contains("demo"));
    CHECK(json["revision"].toInt()==9);
    CHECK(json["defaults"].toObject()["corners"].toObject()["extra"].toInt()==42);
    CHECK(settings.state()["radius"].toInt()==28);
    CHECK(!settings.state()["shadow"].toBool());
    auto config=KSharedConfig::openConfig("kwinrc");
    KConfigGroup decoration(config,"org.kde.kdecoration2");
    decoration.writeEntry("library", "third_party"); decoration.writeEntry("theme", "theme-a"); CHECK(config->sync());
    CHECK(settings.installDefaults());
    CHECK(settings.state()["decoration"]=="kos_decoration");
    CHECK(settings.setTakeover(false));
    CHECK(settings.state()["decoration"]=="third_party");
    CHECK(decoration.readEntry("theme", QString())=="theme-a");
    CHECK(settings.installDefaults()); // upgrade must preserve opt-out
    CHECK(!settings.state()["enabled"].toBool());
    CHECK(settings.setTakeover(true));
    decoration.writeEntry("library", "changed_externally"); CHECK(config->sync());
    CHECK(settings.setTakeover(false));
    CHECK(settings.state()["decoration"]=="changed_externally");
    CHECK(settings.setAnimation("close", "fade"));
    CHECK(settings.setAnimation("hide", "none"));
    CHECK(settings.state()["closeAnimation"]=="fade");
    CHECK(settings.state()["hideAnimation"]=="none");
    // Without a compositor, Genie fails explicitly and preserves the choice.
    CHECK(!settings.setAnimation("hide", "genie"));
    CHECK(settings.state()["hideAnimation"]=="none");
    CHECK(!settings.state()["nativeGenieSupported"].toBool());

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
    CHECK(!persisted["enabled"].toBool()); CHECK(persisted["decoration"]=="changed_externally");
    const auto saved=get();
    CHECK(!settings.setRadius(-1)); CHECK(!settings.setRadius(201)); CHECK(get()==saved);
    { QLockFile lock(filename+".lock"); CHECK(lock.tryLock(0)); CHECK(!settings.setShadow(true)); CHECK(get()==saved); }
    CHECK(!settings.setAnimation("close", "genie"));
    CHECK(settings.state()["closeAnimation"]=="fade");
    put("malformed"); CHECK(!settings.setRadius(12)); CHECK(get()=="malformed");
    put(R"({"version":1,"defaults":{"stroke":{"width":1}}})");
    CHECK(settings.setRadius(8)); json=QJsonDocument::fromJson(get()).object();
    CHECK(json["version"].toInt()==1);
    CHECK(json["defaults"].toObject()["stroke"].toObject()["width"].toInt()==1);
    qInfo("Window settings configuration checks passed");
}
