#include "KimpanelBridge.h"
#include <QCoreApplication>
#include <QJsonDocument>
#include <QTextStream>
#include <cstdlib>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    KosPlatform::KimpanelBridge bridge;
    const QString mode = app.arguments().value(1);
    if (mode == "off") {
        bridge.setShellConnected(true);
        return bridge.isTakeoverActive() ? 1 : 0;
    }
    if (mode == "recover")
        return bridge.isTakeoverActive() ? 1 : 0;
    bridge.setShellConnected(true);
    const bool enabled = bridge.setUserEnabled(true);
    if (mode == "failure")
        return !enabled && !bridge.isTakeoverActive() ? 0 : 2;
    if (!enabled || !bridge.isTakeoverActive()) {
        QTextStream(stderr) << QJsonDocument(bridge.currentState()).toJson();
        return 3;
    }
    if (mode == "crash")
        std::_Exit(0); // Simulate SIGKILL; takeover must leave no durable addon state.
    if (mode == "disconnect")
        bridge.setShellConnected(false);
    else if (!bridge.setUserEnabled(false))
        return 4;
    return bridge.isTakeoverActive() ? 5 : 0;
}
