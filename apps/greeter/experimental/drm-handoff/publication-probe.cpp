// SPDX-License-Identifier: GPL-2.0-or-later
#include "core/kos_bootstrap_publication.h"
#include <QCoreApplication>
#include <cstdio>
int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    auto image = KosBootstrapPublication::openForUid(getuid(), true, 30);
    if (image.fd < 0) return 1;
    close(image.fd);
    std::printf("valid publication: %s %dx%d\n", image.fit.toUtf8().constData(), image.size.width(), image.size.height());
    return 0;
}
