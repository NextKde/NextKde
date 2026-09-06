#include "KosApp/ApplicationRunner.h"

int main(int argc, char *argv[])
{
    return Kos::App::run(argc, argv, {
        QStringLiteral("kos-todo"),
        QStringLiteral("KOS Todo"),
        QStringLiteral("kos-todo"),
        QStringLiteral("org.nextkde.Kos.Todo"),
        QStringLiteral("Kos.Apps.Todo"),
        QStringLiteral(KOS_APP_VERSION),
    });
}
