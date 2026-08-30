#include "KosApp/ApplicationRunner.h"

int main(int argc, char *argv[])
{
    return Kos::App::run(argc, argv, {
        QStringLiteral("kos-weather"),
        QStringLiteral("KOS Weather"),
        QStringLiteral("kos-weather"),
        QStringLiteral("Kos.Apps.Weather"),
        QStringLiteral(KOS_APP_VERSION),
    });
}
