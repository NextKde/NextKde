#pragma once

#include <QString>
#include <array>

namespace IndependentAppRegistry {
struct App {
    const char* key;
    const char* appId;
    const char* executable;
    const char* desktop;
    const char* repository;
    const char* manifest;
    const char* retiredId;
};
inline constexpr std::array apps{
    App{"calendar", "org.nextks.calendar", "kos-calendar", "kos-calendar.desktop", "kos-apps", "org.nextks.calendar.flatpak-release.json", "org.nextkde.Calendar"},
    App{"calculator", "org.nextks.calculator", "kos-calculator", "kos-calculator.desktop", "kos-apps", "org.nextks.calculator.flatpak-release.json", "org.nextkde.Calculator"},
    App{"weather", "org.nextks.weather", "kos-weather", "kos-weather.desktop", "kos-apps", "org.nextks.weather.flatpak-release.json", "org.nextkde.Weather"},
    App{"listenfree", "org.nextkde.ListenFree", "listenfree", "listenfree.desktop", "ListenFree", "flatpak-release.json", ""},
};
inline const App* find(const QString& id)
{
    for (const auto& app : apps)
        if (id == app.appId || id == app.key) return &app;
    return nullptr;
}
}
