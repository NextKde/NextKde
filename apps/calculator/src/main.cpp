#include "KosApp/ApplicationRunner.h"

int main(int argc, char *argv[])
{
    return Kos::App::run(argc, argv, {
        QStringLiteral("kos-calculator"),
        QStringLiteral("KOS Calculator"),
        QStringLiteral("kos-calculator"),
        QStringLiteral("org.nextkde.Kos.Calculator"),
        QStringLiteral("Kos.Apps.Calculator"),
        QStringLiteral(KOS_APP_VERSION),
    });
}
