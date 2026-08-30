#pragma once

#include <QString>

namespace Kos::App {

struct Metadata {
    QString applicationName;
    QString displayName;
    QString desktopFileName;
    QString qmlUri;
    QString version;
};

int run(int argc, char *argv[], const Metadata &metadata);

} // namespace Kos::App
