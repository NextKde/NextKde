#include "WindowSettings.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <KSharedConfig>
#include <KConfigGroup>
#include <cstdlib>
#define CHECK(x) do { if (!(x)) { qFatal("Failed line %d: %s", __LINE__, #x); } } while (false)
int main(int argc, char **argv) {
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
    CHECK(!settings.setAnimation("close", "genie"));
    CHECK(settings.state()["closeAnimation"]=="fade");
    put("malformed"); CHECK(!settings.setRadius(12)); CHECK(get()=="malformed");
    put(R"({"version":1,"defaults":{"stroke":{"width":1}}})");
    CHECK(settings.setRadius(8)); json=QJsonDocument::fromJson(get()).object();
    CHECK(json["version"].toInt()==1);
    CHECK(json["defaults"].toObject()["stroke"].toObject()["width"].toInt()==1);
    qInfo("Window settings configuration checks passed");
}
