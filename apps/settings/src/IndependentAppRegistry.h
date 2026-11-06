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
};
inline constexpr std::array apps{
    App{"calendar", "org.nextks.calendar", "kos-calendar", "org.nextks.calendar.desktop", "kos-apps", "org.nextks.calendar.flatpak-release.json"},
    App{"calculator", "org.nextks.calculator", "kos-calculator", "org.nextks.calculator.desktop", "kos-apps", "org.nextks.calculator.flatpak-release.json"},
    App{"weather", "org.nextks.weather", "kos-weather", "org.nextks.weather.desktop", "kos-apps", "org.nextks.weather.flatpak-release.json"},
    App{"listenfree", "org.nextkde.ListenFree", "listenfree", "listenfree.desktop", "ListenFree", "flatpak-release.json"},
};
inline const App* find(const QString& id)
{
    for (const auto& app : apps)
        if (id == app.appId || id == app.key) return &app;
    return nullptr;
}
}
