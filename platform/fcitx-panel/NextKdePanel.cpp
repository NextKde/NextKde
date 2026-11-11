#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/event.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>
#include <fcitx/userinterface.h>
#include <fcitx/userinterfacemanager.h>
#include <fcitx-utils/dbus/bus.h>
#include <fcitx-utils/capabilityflags.h>
#include <fcitx-utils/dbus/objectvtable.h>
#include <fcitx-utils/dbus/servicewatcher.h>
#include <fcitx-utils/handlertable.h>
#include <dbus_public.h>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <unordered_map>
#include <vector>

namespace {
constexpr auto shellService = "org.nextkde.InputPanel";
constexpr auto adapterService = "org.nextkde.FcitxPanel";

fcitx::dbus::Bus *sessionBus(fcitx::Instance *instance) {
    auto *addon = instance->addonManager().addon("dbus", true);
    auto *bus = addon ? addon->call<fcitx::IDBusModule::bus>() : nullptr;
    if (!bus) throw std::runtime_error("NextKde input panel requires a session bus");
    return bus;
}

// This module leaves client input modules, engines, dictionaries and hotkeys
// alone. Only the input-panel callback changes while NextKde owns its lease.
class NextKdePanel final : public fcitx::AddonInstance,
                          public fcitx::dbus::ObjectVTable<NextKdePanel> {
public:
    explicit NextKdePanel(fcitx::Instance *instance)
        : instance_(instance), bus_(sessionBus(instance)),
          watcher_(*bus_) {
        bus_->addObjectVTable("/org/nextkde/FcitxPanel", "org.nextkde.FcitxPanel1", *this);
        registered_ = bus_->requestName(adapterService, fcitx::dbus::RequestNameFlag::None);
        ownerWatch_ = watcher_.watchService(shellService,
            [this](const auto &, const auto &, const std::string &owner) {
                requested_ = !owner.empty();
                reconcile();
            });
        events_.push_back(instance_->watchEvent(fcitx::EventType::UIChanged,
            fcitx::EventWatcherPhase::Default, [this](fcitx::Event &) { reconcile(); }));
        events_.push_back(instance_->watchEvent(fcitx::EventType::InputContextUpdateUI,
            fcitx::EventWatcherPhase::Default, [this](fcitx::Event &event) {
                auto &update = static_cast<fcitx::InputContextUpdateUIEvent &>(event);
                if (update.component() == fcitx::UserInterfaceComponent::InputPanel)
                    attach(update.inputContext());
            }));
        events_.push_back(instance_->watchEvent(fcitx::EventType::InputContextDestroyed,
            fcitx::EventWatcherPhase::Default, [this](fcitx::Event &event) {
                previous_.erase(static_cast<fcitx::InputContextEvent &>(event).inputContext());
            }));
    }

    ~NextKdePanel() override {
        ownerWatch_.reset();
        events_.clear();
        requested_ = false;
        reconcile();
        if (registered_) bus_->releaseName(adapterService);
    }

    uint32_t version() const { return 1; }
    bool active() const {
        return registered_ && requested_
            && instance_->userInterfaceManager().currentUI() == "kimpanel"
            && panelUI() && panelUI()->available();
    }
    uint32_t contextCount() const { return static_cast<uint32_t>(previous_.size()); }

private:
    fcitx::UserInterface *panelUI() const {
        return dynamic_cast<fcitx::UserInterface *>(
            instance_->addonManager().addon("kimpanel", false));
    }

    struct PanelCallback {
        NextKdePanel *owner;
        void operator()(fcitx::InputContext *context) const { owner->paint(context); }
    };

    bool owns(const fcitx::CustomInputPanelCallback &callback) const {
        const auto *ours = callback.target<PanelCallback>();
        return ours && ours->owner == this;
    }

    void attach(fcitx::InputContext *context) {
        if (!active()) return;
        auto &panel = context->inputPanel();
        if (owns(panel.customInputPanelCallback())) return;
        // Engines may replace/reset their callback between updates. Remember
        // the latest one, never restore a stale callback over another owner's.
        previous_[context] = panel.customInputPanelCallback();
        panel.setCustomInputPanelCallback(PanelCallback{this});
    }

    void paint(fcitx::InputContext *context) {
        if (active()) {
            auto *ui = panelUI();
            if (ui && ui->available()) {
                // A toolkit may have sent its cursor before Kimpanel finished
                // discovering the panel's methods. Publish the current rect
                // before the table, including for client-side panel contexts.
                if (context->hasFocus()) {
                    const bool relative = context->capabilityFlags().test(fcitx::CapabilityFlag::RelativeRect);
                    auto spot = bus_->createMethodCall("org.kde.impanel", "/org/kde/impanel",
                        "org.kde.impanel2", relative ? "SetRelativeSpotRectV2" : "SetSpotRect");
                    const auto &rect = context->cursorRect();
                    spot << int32_t(rect.left()) << int32_t(rect.top())
                         << int32_t(rect.width()) << int32_t(rect.height());
                    if (relative) spot << context->scaleFactor();
                    spot.send();
                }
                ui->update(fcitx::UserInterfaceComponent::InputPanel, context);
                return;
            }
        }
        // A disappearing desktop lease must not strand a client without UI.
        restore(context);
        context->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
    }

    void restore(fcitx::InputContext *context) {
        const auto entry = previous_.find(context);
        if (entry == previous_.end()) return;
        auto &panel = context->inputPanel();
        if (owns(panel.customInputPanelCallback()))
            panel.setCustomInputPanelCallback(entry->second);
        previous_.erase(entry);
    }

    void reconcile() {
        const bool enabled = active();
        instance_->inputContextManager().foreach([&](fcitx::InputContext *context) {
            if (enabled) attach(context);
            else restore(context);
            if (context->hasFocus())
                context->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
            return true;
        });
    }

    FCITX_OBJECT_VTABLE_METHOD(version, "Version", "", "u");
    FCITX_OBJECT_VTABLE_METHOD(active, "Active", "", "b");
    FCITX_OBJECT_VTABLE_METHOD(contextCount, "ContextCount", "", "u");
    fcitx::Instance *instance_;
    fcitx::dbus::Bus *bus_;
    fcitx::dbus::ServiceWatcher watcher_;
    std::unique_ptr<fcitx::dbus::ServiceWatcherEntry> ownerWatch_;
    std::vector<std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>>> events_;
    std::unordered_map<fcitx::InputContext *, fcitx::CustomInputPanelCallback> previous_;
    bool registered_ = false;
    bool requested_ = false;
};

class Factory final : public fcitx::AddonFactory {
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        return new NextKdePanel(manager->instance());
    }
};
} // namespace

FCITX_ADDON_FACTORY(Factory);
