#pragma once

#include <QJsonObject>

#include <functional>

namespace KosPlatform {

using KWinEventHandler = std::function<void(const QJsonObject &)>;

// Starts the KWin D-Bus bridge in the current Qt event loop. The bridge is
// deliberately optional: on compositors other than KWin this simply returns
// false and the rest of the platform service remains available.
bool startKWinBridge(const KWinEventHandler &handler);

// Queues a command for the KWin script. Commands are consumed through the
// bridge's D-Bus polling API, preserving the existing KWin script contract.
bool enqueueKWinCommand(const QJsonObject &command);

} // namespace KosPlatform
