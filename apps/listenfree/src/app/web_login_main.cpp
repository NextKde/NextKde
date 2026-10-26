#include "web_login_dialog.h"
#include "interface_translator.h"
#include "SystemLanguage.h"
#include "qmlbridge/account_service.h"
#include <QApplication>
#include <QCommandLineParser>
#include <QDir>
#include <QFileInfo>

int main(int argc, char** argv) {
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QApplication app(argc, argv);
    QLocale::setDefault(Kos::I18n::locale());
    Kos::I18n::QtCatalogs qtTranslations;
    UiTranslator translator;
    if (!Kos::I18n::isChinese()) app.installTranslator(&translator);
    app.setApplicationName("listenfree-web-login");
    app.setQuitOnLastWindowClosed(false);
    QCommandLineParser parser;
    parser.addHelpOption();
    parser.addOption({"provider", "Music provider", "id"});
    parser.addOption({"profile", "Existing ListenFree data directory", "path"});
    parser.process(app);
    const auto provider = parser.value("provider");
    const QFileInfo profile(parser.value("profile"));
    if (listenfree::qmlbridge::AccountService::loginUrl(provider).isEmpty()
        || !profile.isAbsolute() || !profile.isDir()) return 2;
    listenfree::qmlbridge::AccountService accounts(profile.absoluteFilePath());
    listenfree::WebLoginDialog dialog(accounts);
    QObject::connect(&dialog, &listenfree::WebLoginDialog::finished, &app,
                     [&app](bool accepted) { app.exit(accepted ? 0 : 1); });
    dialog.open(provider);
    return app.exec();
}
