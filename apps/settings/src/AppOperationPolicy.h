#pragma once

#include <QString>

// Read-only inventory, update discovery and cleanup previews may be abandoned.
inline bool isAppMutation(const QString &action)
{
    return action == QLatin1String("install") || action == QLatin1String("update")
        || action == QLatin1String("uninstall") || action == QLatin1String("prune")
        || action == QLatin1String("remove-retired") || action == QLatin1String("setup-runtime-source");
}
