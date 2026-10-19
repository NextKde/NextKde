// SPDX-License-Identifier: GPL-2.0-or-later
// Synthetic login-shaped window; never accesses PAM or greetd.
#include <QApplication>
#include <QWidget>
#include <QLabel>
#include <QVBoxLayout>
#include <QSocketNotifier>
#include <QFile>
#include <unistd.h>
int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    if (argc != 2) return 2;
    QFile input(QString::fromLocal8Bit(argv[1]));
    if (!input.open(QIODevice::ReadOnly)) return 3;
    QSocketNotifier notifier(input.handle(), QSocketNotifier::Read);
    QObject::connect(&notifier, &QSocketNotifier::activated, [&] {
        char c;
        if (read(input.handle(), &c, 1) == 1 && c == 'X') app.quit();
    });
    QWidget window;
    window.resize(450, 200);
    window.setStyleSheet("background: #c00080; color: white;");
    QVBoxLayout layout(&window);
    QLabel label("SYNTHETIC LOGIN FIXTURE — NO CREDENTIALS");
    layout.addWidget(&label);
    window.show();
    return app.exec();
}
