#include "KosApp/ApplicationRunner.h"

int main(int argc, char *argv[])
{
    return Kos::App::run(argc, argv, {
        QStringLiteral("kos-music"),
        QStringLiteral("KOS Music"),
        QStringLiteral("kos-music"),
        QStringLiteral("Kos.Apps.Music"),
        QStringLiteral(KOS_APP_VERSION),
    });
}
