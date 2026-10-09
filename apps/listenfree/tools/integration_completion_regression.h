#pragma once
#include <QApplication>
#include <QClipboard>
#include <QFile>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJSValue>
#include <QQuickWindow>
#include <QQuickItem>
#include <QTimer>
#include "qmlbridge/controllers.h"
#include "../src/app/platform_settings.h"

inline QQuickItem* integrationFindItem(QQuickItem* item,const QString& name) {
    if(!item)return nullptr;if(item->objectName()==name)return item;
    for(auto* child:item->childItems())if(auto* found=integrationFindItem(child,name))return found;
    return nullptr;
}

inline void runIntegrationCompletionRegression(QApplication& app,QQuickWindow* window,QObject* shell,
    listenfree::qmlbridge::SettingsController& settings,listenfree::PlatformSettings& platform,const QString& reportPath) {
    auto results=std::make_shared<QJsonObject>();
    // Run only against --data-dir; the caller never touches a normal profile.
    (*results)["startupLanguage"]=shell->property("uiLanguage").toString();
    (*results)["startupMotion"]=shell->property("animationStyle").toString();
    (*results)["startupRefreshRate"]=shell->property("refreshRateLimit").toInt();
    settings.setValue("ui.language","EnUs");settings.setValue("ui.motionStyle","Bright");settings.setValue("ui.refreshRateLimit",120);
    settings.setValue("lyrics.showTranslation",true);settings.setValue("lyrics.showRomanization",true);
    shell->setProperty("settingsOpen",true);
    QTimer::singleShot(700,&app,[&,results,window,shell,reportPath] {
        auto* page=shell->findChild<QObject*>("settingsPage");
        (*results)["settingsPageLoaded"]=page!=nullptr;
        (*results)["languageApplied"]=shell->property("uiLanguage")=="en-US";
        (*results)["motionApplied"]=shell->property("animationStyle")=="Bright";
        (*results)["refreshApplied"]=shell->property("refreshRateLimit").toInt()==120;
        if(page) {
            auto* row=integrationFindItem(qobject_cast<QQuickItem*>(page),"settingRow/ui.language");
            (*results)["englishSettings"]=row && row->property("title")=="Language";
            auto* order=integrationFindItem(qobject_cast<QQuickItem*>(page),"settingRow/lyrics.secondaryLineOrder");
            (*results)["lyricOrderEnabled"]=order && order->property("enabled").toBool();
            window->grabWindow().save(reportPath+"-english.png");
            page->setProperty("selectedCategory",8);
            QMetaObject::invokeMethod(page,"handleAction",Q_ARG(QVariant,QString("settings.resetDefaults")));
        }
        platform.action("diagnostics.copy");
        const auto copied=QGuiApplication::clipboard()->text();
        (*results)["diagnosticsCopied"]=copied.startsWith("ListenFree 0.3.0") && !copied.contains("Users",Qt::CaseInsensitive) && !copied.contains("Cookie");
        shell->setProperty("globalAlertOpen",false);
        QTimer::singleShot(300,&app,[&,results,window,shell,reportPath] {
            window->grabWindow().save(reportPath+"-backup.png");
            settings.setValue("window.transparencyEnabled",false);
            (*results)["transparencyDisabled"]=!shell->property("desktopTransparencyActive").toBool();
            settings.setValue("window.transparencyEnabled",true);
            (*results)["transparencyAvailable"]=shell->property("desktopTransparencyActive").toBool();
            settings.setValue("scroll.library.grid.artists",600);
            settings.setValue("list.rememberScrollPosition",false);
            (*results)["scrollCleared"]=settings.value("scroll.library.grid.artists",0).toInt()==0;
            auto* cache=shell->findChild<QObject*>("navigationStateCache");
            (*results)["navigationMemoryDisabled"]=cache && !cache->property("remember").toBool();
            settings.setValue("ui.language","ZhCn");
            QTimer::singleShot(100,&app,[&,results,shell,reportPath] {
                auto* row=integrationFindItem(qobject_cast<QQuickItem*>(shell),"settingRow/ui.language");
                (*results)["chineseRestored"]=row && row->property("title")==QString::fromUtf8("语言");
                // Leave explicit non-default values to verify the next process restores them.
                settings.setValue("ui.language","EnUs");
                QFile report(reportPath);if(report.open(QIODevice::WriteOnly))report.write(QJsonDocument(*results).toJson());
                app.quit();
            });
        });
    });
}
