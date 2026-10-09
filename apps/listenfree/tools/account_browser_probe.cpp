#include "app/account_browser.h"
#include "qmlbridge/account_service.h"
#include <QApplication>
#include <QDialog>
#include <QTemporaryDir>
#include <QTimer>
#include <QDir>
#include <QFileInfo>
#include <QDebug>
#include <QLabel>
#include <QWebEngineView>
#include <QWebEnginePage>

int main(int argc,char** argv) {
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QApplication app(argc,argv);
    if(app.arguments().size()<3)return 2;
    const auto provider=app.arguments()[1], output=app.arguments()[2];
    QTemporaryDir data;
    listenfree::qmlbridge::AccountService accounts(data.path());
    listenfree::AccountBrowser browser(accounts);
    browser.open(provider);
    QTimer::singleShot(12000,&app,[&] {
        for(auto* widget:app.topLevelWidgets()) {
            if(!qobject_cast<QDialog*>(widget)||!widget->isVisible())continue;
            QDir().mkpath(QFileInfo(output).absolutePath());
            const bool saved=widget->grab().save(output);
            const auto views=widget->findChildren<QWebEngineView*>();
            for(auto* view:views) qInfo().noquote()<<provider<<"page host:"<<view->url().host()<<"title:"<<view->title();
            for(auto* label:widget->findChildren<QLabel*>())qInfo().noquote()<<label->text();
            widget->close();app.exit(saved?0:3);return;
        }
        app.exit(4);
    });
    return app.exec();
}
