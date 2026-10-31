#include "../../../../platform/src/windowanimation/NativeGenie.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QDebug>

#define CHECK(x) do { if (!(x)) qFatal("Line %d: %s", __LINE__, #x); } while (false)

class FakeKWin : public KOS::WindowAnimation::EffectRuntime {
public:
    bool connected = true;
    bool supportsLamp = true;
    bool failLampLoad = false;
    bool failDock = false;
    bool failDisableAfterLoadOnce = false;
    bool failSquashDisableOnce = false;
    QMap<QString, bool> loaded{{"magiclamp", false}, {"squash", true},
                              {"kos_dock_window_animation", true}};
    bool available() override { return connected; }
    bool supported(const QString &name) override { return name == "magiclamp" && supportsLamp; }
    bool setEnabled(const QString &name, bool enabled) override {
        if (name == "magiclamp" && !enabled && failDisableAfterLoadOnce && loaded[name]) {
            failDisableAfterLoadOnce = false;
            return false;
        }
        if (name == "magiclamp" && enabled && failLampLoad) return false;
        if (name == "squash" && !enabled && failSquashDisableOnce) {
            failSquashDisableOnce = false;
            return false;
        }
        loaded[name] = enabled;
        return true;
    }
    bool reloadDock() override { return !failDock; }
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir temporary;
    CHECK(temporary.isValid());
    int scenario = 0;
    auto fresh = [&]() {
        auto config = KSharedConfig::openConfig(temporary.path() + "/" + QString::number(scenario++) + ".rc");
        KConfigGroup plugins(config, "Plugins");
        plugins.writeEntry("magiclampEnabled", false);
        plugins.writeEntry("squashEnabled", true);
        plugins.writeEntry("blurEnabled", true);
        KConfigGroup animation(config, "Effect-kos_dock_window_animation");
        animation.writeEntry("CloseAnimation", "fade");
        CHECK(config->sync());
        return config;
    };
    QString error;
    // A previous custom duration (and absence of the key) must survive repeated
    // Genie selection, fallback, switching away, and failed transactions.
    for (bool present : {false, true}) {
        auto config = fresh(); FakeKWin kwin;
        KConfigGroup lamp(config, "Effect-magiclamp");
        if (present) lamp.writeEntry("AnimationDuration", 911);
        CHECK(config->sync());
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "genie", kwin, error));
        CHECK(lamp.readEntry("AnimationDuration", 0) == 250);
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "genie", kwin, error));
        kwin.failSquashDisableOnce = true;
        CHECK(!KOS::WindowAnimation::applyWithRuntime(config, "scale", kwin, error));
        CHECK(lamp.readEntry("AnimationDuration", 0) == 250);
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "scale", kwin, error));
        CHECK(lamp.hasKey("AnimationDuration") == present);
        CHECK(lamp.readEntry("AnimationDuration", 0) == (present ? 911 : 0));
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "genie", kwin, error));
        kwin.failLampLoad = true;
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "genie", kwin, error));
        CHECK(lamp.hasKey("AnimationDuration") == present);
        CHECK(lamp.readEntry("AnimationDuration", 0) == (present ? 911 : 0));
    }

    // Standard installations need no manual KCM step, even when Lamp starts disabled.
    {
        auto config = fresh(); FakeKWin kwin;
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "genie", kwin, error));
        KConfigGroup animation(config, "Effect-kos_dock_window_animation");
        CHECK(animation.readEntry("HideAnimation", QString()) == "none");
        CHECK(kwin.loaded["magiclamp"] && !kwin.loaded["squash"]);
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "scale", kwin, error));
        CHECK(animation.readEntry("HideAnimation", QString()) == "scale");
        CHECK(!kwin.loaded["magiclamp"] && !kwin.loaded["squash"]);
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "none", kwin, error));
        CHECK(!kwin.loaded["magiclamp"] && kwin.loaded["squash"]);
        CHECK(KConfigGroup(config, "Plugins").readEntry("blurEnabled", false));
        CHECK(animation.readEntry("CloseAnimation", QString()) == "fade");
        qInfo("PASS disabled built-in enables; switches are exclusive; None restores previous state");
    }
    // Missing/unsupported effect: retain Genie intent and use project Scale.
    {
        auto config = fresh(); FakeKWin kwin; kwin.supportsLamp = false;
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "genie", kwin, error));
        KConfigGroup animation(config, "Effect-kos_dock_window_animation");
        CHECK(KOS::WindowAnimation::selection(config) == "genie");
        CHECK(animation.readEntry("HideAnimation", QString()) == "scale");
        CHECK(!animation.readEntry("NativeGenieFallback", QString()).isEmpty());
        CHECK(!kwin.loaded["magiclamp"] && !kwin.loaded["squash"]);
        // A later startup after repair recovers native without losing the preference.
        kwin.supportsLamp = true;
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "genie", kwin, error));
        CHECK(animation.readEntry("HideAnimation", QString()) == "none");
        CHECK(!animation.hasKey("NativeGenieFallback"));
        qInfo("PASS missing effect falls back and recovers after support returns");
    }
    {
        auto config = fresh(); FakeKWin kwin; kwin.failLampLoad = true;
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "genie", kwin, error));
        KConfigGroup animation(config, "Effect-kos_dock_window_animation");
        CHECK(animation.readEntry("HideAnimation", QString()) == "scale");
        CHECK(animation.readEntry("NativeGenieFallback", QString()).contains("failed to load"));
        CHECK(!kwin.loaded["magiclamp"] && !kwin.loaded["squash"]);
        qInfo("PASS supported effect load failure settles on Scale");
    }
    {
        auto config = fresh(); FakeKWin kwin; kwin.connected = false;
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "genie", kwin, error));
        CHECK(KConfigGroup(config, "Effect-kos_dock_window_animation").readEntry("HideAnimation", QString()) == "scale");
        qInfo("PASS disconnected installation persists usable fallback for next session");
    }
    {
        auto config = fresh(); FakeKWin kwin;
        KConfigGroup animation(config, "Effect-kos_dock_window_animation");
        animation.writeEntry("HideAnimation", "genie"); CHECK(config->sync());
        kwin.supportsLamp = false;
        CHECK(KOS::WindowAnimation::reconcileWithRuntime(config, kwin, error));
        CHECK(animation.readEntry("HideAnimation", QString()) == "scale");
        CHECK(animation.readEntry("HideAnimationSelection", QString()) == "genie");
        kwin.supportsLamp = true;
        CHECK(KOS::WindowAnimation::reconcileWithRuntime(config, kwin, error));
        CHECK(kwin.loaded["magiclamp"]);
        qInfo("PASS legacy water-drop and saved Genie startup migration");
    }
    {
        auto config = fresh(); FakeKWin kwin;
        KConfigGroup animation(config, "Effect-kos_dock_window_animation");
        animation.writeEntry("HideAnimation", "none"); CHECK(config->sync());
        const auto before = animation.entryMap(); const auto loaded = kwin.loaded;
        CHECK(KOS::WindowAnimation::reconcileWithRuntime(config, kwin, error));
        CHECK(animation.entryMap() == before && kwin.loaded == loaded);
        qInfo("PASS explicit None is untouched by startup reconciliation");
    }
    {
        auto config = fresh(); FakeKWin kwin; kwin.failSquashDisableOnce = true;
        KConfigGroup animation(config, "Effect-kos_dock_window_animation");
        KConfigGroup plugins(config, "Plugins");
        const auto before = animation.entryMap(); const auto beforePlugins = plugins.entryMap();
        CHECK(!KOS::WindowAnimation::applyWithRuntime(config, "scale", kwin, error));
        CHECK(animation.entryMap() == before && plugins.entryMap() == beforePlugins);
        CHECK(!kwin.loaded["magiclamp"] && kwin.loaded["squash"]);
        qInfo("PASS failed exclusivity switch restores configuration and loaded effects");
    }
    {
        auto config = fresh(); FakeKWin kwin; kwin.failDock = true;
        KConfigGroup animation(config, "Effect-kos_dock_window_animation");
        const auto before = animation.entryMap();
        CHECK(!KOS::WindowAnimation::applyWithRuntime(config, "genie", kwin, error));
        CHECK(animation.entryMap() == before);
        CHECK(kwin.loaded["squash"] && !kwin.loaded["magiclamp"]);
        CHECK(error.contains("restart KWin"));
        qInfo("PASS failed fallback backend reports rollback limit rather than claiming success");
    }
    {
        auto config = fresh(); FakeKWin kwin;
        CHECK(KOS::WindowAnimation::applyWithRuntime(config, "genie", kwin, error));
        const auto before = KConfigGroup(config, "Effect-kos_dock_window_animation").entryMap();
        kwin.failDisableAfterLoadOnce = true;
        CHECK(!KOS::WindowAnimation::applyWithRuntime(config, "scale", kwin, error));
        CHECK(KConfigGroup(config, "Effect-kos_dock_window_animation").entryMap() == before);
        CHECK(kwin.loaded["magiclamp"] && !kwin.loaded["squash"]);
        qInfo("PASS failed switch from active native Genie restores active native state");
    }
}
