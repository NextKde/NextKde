#pragma once
#include <QElapsedTimer>
#include <algorithm>

// Explicit opt-in native regression; always run against a disposable --data-dir.
inline void runPlaylistTransitionRegression(QApplication& app, QQuickWindow* window, QObject* shell,
    listenfree::qmlbridge::PortableSession& player,
    listenfree::qmlbridge::SettingsController& settings, const QString& report) {
    struct State {
        QElapsedTimer clock; qint64 at=0, previous=0; int stage=0, cycle=0, missing=0, samples=0;
        double clickMax=0, startDelayMax=0; bool started=false; QList<double> gaps; QJsonObject checks;
    };
    auto s=std::make_shared<State>(); s->clock.start();
    auto* timer=new QTimer(&app); timer->setInterval(16); timer->setTimerType(Qt::PreciseTimer);
    QObject::connect(timer,&QTimer::timeout,&app,[&,window,shell,report,s,timer] {
        const auto now=s->clock.elapsed();
        const auto item=[&](const QString& name){return uiItem(window->contentItem(),name);};
        const auto finish=[&] {
            timer->stop();std::sort(s->gaps.begin(),s->gaps.end());
            const double maximum=s->gaps.isEmpty()?0:s->gaps.last();
            const double p95=s->gaps.isEmpty()?0:s->gaps[qMin(s->gaps.size()-1,s->gaps.size()*95/100)];
            s->checks["three_round_trips"]=s->cycle==3;
            s->checks["no_placeholder_during_flight"]=s->samples>0&&s->missing==0;
            s->checks["click_under_50ms"]=s->clickMax<50;
            s->checks["gui_stall_under_100ms"]=maximum<100;
            bool pass=true;for(auto it=s->checks.begin();it!=s->checks.end();++it)pass&=it.value().toBool();
            s->checks["passed"]=pass;
            s->checks["measurements"]=QJsonObject{{"click_max_ms",s->clickMax},{"gui_gap_max_ms",maximum},
                {"gui_gap_p95_ms",p95},{"transition_start_delay_max_ms",s->startDelayMax},{"transition_samples",s->samples},{"missing_artwork_samples",s->missing}};
            QFile file(report);if(file.open(QIODevice::WriteOnly))file.write(QJsonDocument(s->checks).toJson());
            app.exit(pass?0:7);
        };
        if(now>30000){s->checks["timeout"]=false;finish();return;}
        if(s->stage==0) {
            if(!player.ready())return;
            window->resize(1066,709);shell->setProperty("currentRoute","my-lists");shell->setProperty("settingsOpen",false);
            shell->setProperty("darkMode",false);shell->setProperty("animationsEnabled",true);
            settings.setValue("ui.motionEnabled",true);settings.setValue("ui.motionStyle","Elegant");
            settings.setValue("background.type","AutoCover");settings.setValue("background.mask",0);
            if(!player.songs().isEmpty()){player.clearQueue();player.enqueueTrack(player.songs().first().toMap());player.selectQueue(0,false);}
            s->stage=1;s->at=now;return;
        }
        if(s->stage==1) {
            auto* grid=item("myPlaylistGrid");
            if(grid&&qAbs(grid->property("contentY").toDouble())>.1){grid->setProperty("contentY",0);s->at=now;return;}
            auto* card=item("myPlaylistCard"+QString::number(s->cycle+3));
            auto* art=card?uiItem(card,"artworkTileImage"):nullptr;
            if(now-s->at<700||!art||art->property("missingArtwork").toBool())return;
            if(s->cycle==0)window->grabWindow().save(report+".before.png");
            const auto point=card->mapToScene({card->width()/2,card->width()/2});QElapsedTimer click;click.start();
            for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}) {
                QMouseEvent e(type,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,
                    type==QEvent::MouseButtonPress?Qt::LeftButton:Qt::NoButton,Qt::NoModifier);
                static ulong stamp=100;e.setTimestamp(stamp+=50);QCoreApplication::sendEvent(window,&e);
            }
            s->clickMax=qMax(s->clickMax,double(click.nsecsElapsed())/1000000.0);s->previous=s->clock.elapsed();
            s->stage=2;s->at=s->clock.elapsed();s->started=false;return;
        }
        if(s->stage==2||s->stage==3) {
            s->gaps.append(double(now-s->previous));s->previous=now;
            if(shell->property("collectionMorphActive").toBool()) {
                if(s->stage==2&&!s->started&&shell->property("collectionMorphProgress").toDouble()>0){s->started=true;s->startDelayMax=qMax(s->startDelayMax,double(now-s->at));}
                auto* art=item("collectionMorphArtwork");
                if(art&&art->isVisible()){++s->samples;if(art->property("missingArtwork").toBool())++s->missing;}
                return;
            }
            if(now-s->at<100)return;
            if(s->stage==2) {
                if(shell->property("currentRoute")!="detail/playlist"){s->checks["clicked_card_opens_detail"]=false;finish();return;}
                auto* detailArt=item("playlistDetailArtwork");
                s->checks["detail_artwork_ready"]=detailArt&&!detailArt->property("missingArtwork").toBool();
                if(s->cycle==0)window->grabWindow().save(report+".detail.png");
                QMetaObject::invokeMethod(shell,"closeCollection");s->stage=3;s->at=now;s->previous=s->clock.elapsed();
            } else {
                ++s->cycle;if(s->cycle==3){finish();return;}s->stage=1;s->at=now;
            }
        }
    });timer->start();
}
