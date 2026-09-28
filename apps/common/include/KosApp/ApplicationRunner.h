#pragma once

#include <QString>
#include <QVariantMap>

#include <functional>

class QQmlEngine;

namespace Kos::App {

struct Metadata {
    QString applicationName;
    QString displayName;
    QString desktopFileName;
    QString dbusServiceName;
    QString qmlUri;
    QString version;
    // Called once per application start, after the QGuiApplication and the QML
    // engine exist and before the root component loads. Long-lived controllers
    // are created here and handed to QML through initialProperties, so a
    // --watch-qml reload rebuilds the window without tearing down playback,
    // connections, or service registrations. May be empty.
    std::function<void(QQmlEngine &, QVariantMap &)> prepareEngine;
};

int run(int argc, char *argv[], const Metadata &metadata);

} // namespace Kos::App
