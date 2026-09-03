#include "KosApp/ApplicationRunner.h"

int main(int argc, char *argv[])
{
    return Kos::App::run(argc, argv, {
        QStringLiteral("kos-calendar"),
        QStringLiteral("KOS Calendar"),
        QStringLiteral("kos-calendar"),
        QStringLiteral("org.nextkde.Kos.Calendar"),
        QStringLiteral("Kos.Apps.Calendar"),
        QStringLiteral(KOS_APP_VERSION),
    });
}
