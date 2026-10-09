#pragma once
#include <QElapsedTimer>

// Exercises the real packaged Qt scene, including event delivery and interrupted
// staged transitions. The isolated profile prevents touching the user's queue.
inline void runDiscQueueRegression(QApplication& app, QQuickWindow* window, QObject* shell,
    listenfree::qmlbridge::SettingsController& settings, const QString& report) {
    struct State {
        int step=0,ticks=0,stepTicks=0,maxSectors=0;
        bool entryBeforeExpand=true,rotationCollapsed=true,closeOrder=true;
        QStringList phases; QJsonObject checks; QVariantList rows;
        QPointer<listenfree::qmlbridge::QueueModel> nativeModel;
        QElapsedTimer clock; double baselineMiB=0;
    };
    auto s=std::make_shared<State>();s->clock.start();
    auto* timer=new QTimer(&app);timer->setInterval(25);
    QObject::connect(timer,&QTimer::timeout,&app,[&,window,shell,report,s,timer] {
        const auto item=[&](const QString& name){return uiItem(window->contentItem(),name);};
        auto* disc=item("immersiveDiscQueue");auto* page=item("nowPlayingPage");
        const auto capture=[&](const QString& name){window->grabWindow().save(report+"."+name+".png");};
        const auto finish=[&]{
            timer->stop();bool pass=true;for(const auto& v:s->checks)pass &=v.toBool();
            s->checks["passed"]=pass;s->checks["maxLiveSectors"]=s->maxSectors;
            s->checks["elapsedMs"]=s->clock.elapsed();
            QFile f(report);if(f.open(QIODevice::WriteOnly))f.write(QJsonDocument(s->checks).toJson());app.exit(pass?0:7);
        };
        const auto next=[&](int step){s->step=step;s->stepTicks=0;s->phases.clear();};
        const auto call=[&](const char* method,int arg){QMetaObject::invokeMethod(disc,method,Q_ARG(QVariant,QVariant(arg)));};
        const auto click=[&](QPointF p){
            for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}){
                QMouseEvent e(type,p,p,window->mapToGlobal(p.toPoint()),Qt::LeftButton,
                    type==QEvent::MouseButtonPress?Qt::LeftButton:Qt::NoButton,Qt::NoModifier);
                QCoreApplication::sendEvent(window,&e);
            }
        };
        if(++s->ticks>1600){s->checks[QString("timeout_step_%1").arg(s->step)]=false;finish();return;}
        ++s->stepTicks;
        QString phase=disc?disc->property("phase").toString():"closed";
        if(s->phases.isEmpty()||s->phases.last()!=phase)s->phases.append(phase);
        if(disc){
            const double expansion=disc->property("expansion").toDouble();
            s->maxSectors=qMax(s->maxSectors,disc->property("loadedSectorCount").toInt());
            if(phase=="enter"&&expansion>.001)s->entryBeforeExpand=false;
            if(phase=="rotate"&&expansion>.001)s->rotationCollapsed=false;
            if(s->step==6 && phase=="retract" && disc->property("travel").toDouble()<.999)s->closeOrder=false;
        }
        if(s->ticks%40==0){
            QJsonObject progress=s->checks;progress["step"]=s->step;progress["phase"]=phase;
            if(disc)for(const auto& key:{"travel","expansion","trackCount","selectedIndex","requestedIndex","wheelPosition","width","height","visible"})progress[key]=QJsonValue::fromVariant(disc->property(key));
            QFile f(report);if(f.open(QIODevice::WriteOnly))f.write(QJsonDocument(progress).toJson());
        }
        // Keep native animations advancing even if another window covers this one.
        window->requestUpdate();window->grabWindow();
        switch(s->step){
        case 0:
            window->showNormal();window->resize(1440,900);window->requestActivate();
            settings.setValue("immersive.background","blur");settings.setValue("immersive.visualization","none");
            settings.setValue("immersive.lyricStyle","classic");
            shell->setProperty("animationsEnabled",false);shell->setProperty("useBackendModels",false);
            shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.);shell->setProperty("coverMorphProgress",1.);
            for(int i=0;i<1000;++i)s->rows.append(QVariantMap{{"title",i==500?QStringLiteral("One Last Kiss"):QStringLiteral("唱片选曲 %1").arg(i+1)},
                {"artist",QStringLiteral("宇多田ヒカル · ListenFree")},{"album",QStringLiteral("精选音乐 / Native Disc")},{"duration",246000},
                {"artwork",QUrl::fromLocalFile(QFileInfo(report).dir().absoluteFilePath(QString("../../music_player_desktop/assets/album_Cover_%1@2x.png").arg(2+i%6)))}});
            shell->setProperty("queueSongs",s->rows);shell->setProperty("currentQueueIndex",500);next(1);return;
        case 1:
            if(!page)return;
            page->setProperty("trackTitle","One Last Kiss");page->setProperty("trackArtist",QStringLiteral("宇多田ヒカル"));
            page->setProperty("artworkSource",s->rows[500].toMap()["artwork"]);
            page->setProperty("lyrics",QVariantList{QVariantMap{{"text",QStringLiteral("你能再给我最后一吻吗")},{"timeMs",0}}});
            page->setProperty("playing",false);page->setProperty("positionMs",1000.);
            QMetaObject::invokeMethod(page,"toggleImmersive");next(2);return;
        case 2:
            if(!item("immersiveStage")||s->stepTicks<8)return;
            capture("before");s->baselineMiB=immersivePrivateMiB();shell->setProperty("animationsEnabled",true);
            QMetaObject::invokeMethod(shell,"openQueue",Q_ARG(QVariant,QVariant(true)));next(3);return;
        case 3:
            if(disc&&phase=="enter"&&s->stepTicks==4)capture("enter");
            if(!disc||phase!="idle")return;
            s->checks["opening_disc_then_sector"]=s->entryBeforeExpand&&s->phases.contains("enter")&&s->phases.contains("expand");
            s->checks["opens_at_playing_track"]=disc->property("selectedIndex").toInt()==500;
            s->checks["thousand_tracks_bounded_window"]=disc->property("trackCount").toInt()==1000&&s->maxSectors<=11;
            capture("open");
            {const QPointF p(window->width()*.7,window->height()*.65);
             QWheelEvent e(p,window->mapToGlobal(p.toPoint()),{},QPoint(0,-120),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);QCoreApplication::sendEvent(window,&e);}
            next(4);return;
        case 4:
            if(phase!="idle"||s->stepTicks<4)return;
            s->checks["wheel_collapses_rotates_expands"]=disc->property("selectedIndex").toInt()==501&&s->phases.contains("retract")&&s->phases.contains("rotate")&&s->phases.contains("expand");
            if(auto* wedge=item("queueSector503"))click(wedge->mapToScene(QPointF(wedge->width()*.55,wedge->height()*.5)));
            next(5);return;
        case 5:
            if(phase!="idle"||s->stepTicks<4)return;
            s->checks["click_selects_actual_sector"]=disc->property("selectedIndex").toInt()==503;
            capture("selected");QMetaObject::invokeMethod(shell,"navigateBack");next(6);return;
        case 6:
            if(disc&&phase=="exit"&&s->stepTicks%3==0)capture("exit");
            if(disc)return;
            s->checks["closing_sector_then_disc"]=s->closeOrder&&s->phases.contains("retract")&&s->phases.contains("exit");
            s->checks["back_closes_only_queue"]=page&&page->property("immersiveActive").toBool()&&!shell->property("queueOpen").toBool();
            capture("closed");QMetaObject::invokeMethod(shell,"openQueue",Q_ARG(QVariant,QVariant(true)));next(7);return;
        case 7:
            if(!disc||phase!="idle")return;
            call("step",1);next(8);return;
        case 8:
            if(!disc)return;
            if(s->stepTicks==2)call("step",3);
            if(s->stepTicks==4)call("step",-2);
            if(s->stepTicks<5||phase!="idle")return;
            s->checks["rapid_input_coalesces"]=disc->property("selectedIndex").toInt()==502&&s->rotationCollapsed;
            QMetaObject::invokeMethod(shell,"closeQueue");next(9);return;
        case 9:
            if(disc&&phase=="exit"){
                QMetaObject::invokeMethod(shell,"openQueue",Q_ARG(QVariant,QVariant(true)));next(10);
            }return;
        case 10:
            if(!disc||phase!="idle")return;
            s->checks["reverse_close_reopens_smoothly"]=disc->property("travel").toDouble()>.999&&disc->property("expansion").toDouble()>.999;
            shell->setProperty("queueSongs",QVariantList{s->rows.first()});next(11);return;
        case 11:
            if(!disc||phase!="idle")return;
            s->checks["queue_shrink_clamps_selection"]=disc->property("selectedIndex").toInt()==0&&disc->property("trackCount").toInt()==1;
            call("step",1);shell->setProperty("queueSongs",QVariantList{});next(12);return;
        case 12:
            if(!disc||phase!="idle")return;
            s->checks["empty_queue_safe"]=disc->property("selectedIndex").toInt()==-1&&disc->property("loadedSectorCount").toInt()==0;
            shell->setProperty("queueSongs",s->rows);shell->setProperty("animationsEnabled",false);next(13);return;
        case 13:
            if(!disc||phase!="idle")return;
            call("selectIndex",999);
            s->checks["reduced_motion_jumps_without_animation"]=disc->property("selectedIndex").toInt()==999&&disc->property("phase").toString()=="idle";
            window->resize(960,640);next(14);return;
        case 14:
            if(s->stepTicks<5)return;
            capture("compact");
            s->nativeModel=new listenfree::qmlbridge::QueueModel(&app);
            {std::vector<listenfree::domain::Track> tracks;
             for(int i=0;i<3;++i){listenfree::domain::Track track;track.id=listenfree::domain::TrackId(std::to_string(i));track.title="Native queue "+std::to_string(i);tracks.push_back(track);}
             s->nativeModel->setTracks(std::move(tracks));}
            disc->setProperty("sourceModel",QVariant::fromValue(static_cast<QObject*>(s->nativeModel)));
            next(17);return;
        case 17:
            if(!disc||phase!="idle")return;
            s->checks["native_model_count_and_get"]=disc->property("trackCount").toInt()==3&&disc->property("selectedIndex").toInt()==2;
            s->nativeModel->setTracks({});next(18);return;
        case 18:
            if(!disc||phase!="idle")return;
            s->checks["native_model_reset_empty"]=disc->property("trackCount").toInt()==0&&disc->property("loadedSectorCount").toInt()==0;
            QMetaObject::invokeMethod(shell,"closeQueue");next(15);return;
        case 15:
            if(disc)return;
            s->checks["closed_releases_disc"]=true;
            QMetaObject::invokeMethod(shell,"navigateBack");next(16);return;
        case 16:
            s->checks["next_back_returns_nowplaying"]=page&&!page->property("immersiveActive").toBool()&&shell->property("nowPlayingOpen").toBool();
            finish();return;
        }
    });timer->start();
}
