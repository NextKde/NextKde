#pragma once
#include "qmlbridge/radio_service.h"

inline void runRadioFavoritesRegression(QApplication& app,QQuickWindow* window,QObject* shell,
    listenfree::qmlbridge::PortableSession& player,listenfree::qmlbridge::SettingsController& settings,
    listenfree::qmlbridge::RadioService& radio,listenfree::qmlbridge::CollectionService& collections,const QString& report) {
    struct State {int phase=0,ticks=0;QJsonObject checks;};
    auto state=std::make_shared<State>();const bool restart=app.arguments().contains("--radio-favorites-restart");
    const QVariantMap station{{"radioProvider","netease-broadcast"},{"radioId","1203"},{"title",QStringLiteral("100.7重庆永川之声")},{"artist",QStringLiteral("重庆")},{"isLive",true}};
    const QVariantMap podcast{{"radioProvider","netease-podcast"},{"radioId","336355127"},{"title",QStringLiteral("代码时间")},{"kind","podcast"}};
    auto* timer=new QTimer(&app);timer->setInterval(220);
    QObject::connect(timer,&QTimer::timeout,&app,[&,window,shell,timer,state,report,restart,station,podcast] {
        const auto item=[&](const QString& name){return uiItem(window->contentItem(),name);};
        const auto shot=[&](const QString& suffix){window->grabWindow().save(report+suffix+".png");};
        const auto click=[&](QQuickItem* target,Qt::MouseButton button=Qt::LeftButton,double x=.5,double y=.5) {
            if(!target || !target->isVisible()){state->checks["click_target_available"]=false;return;}
            const auto point=target->mapToScene({target->width()*x,target->height()*y});
            static ulong timestamp=0;
            for(const auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}) {
                QMouseEvent event(type,point,point,window->mapToGlobal(point.toPoint()),button,type==QEvent::MouseButtonPress?button:Qt::NoButton,Qt::NoModifier);
                event.setTimestamp(timestamp+=24);QCoreApplication::sendEvent(window,&event);
            }
        };
        const auto finish=[&] {
            player.stop();QFile file(report);if(file.open(QIODevice::WriteOnly))file.write(QJsonDocument(QJsonObject{{"checks",state->checks}}).toJson());
            timer->stop();bool ok=true;for(const auto& check:state->checks)ok &= check.toBool();app.exit(ok?0:1);
        };
        if(++state->ticks>360){state->checks["completed"]=false;finish();return;}
        switch(state->phase) {
        case 0:
            window->setFlag(Qt::WindowTransparentForInput,true);window->setFlag(Qt::WindowDoesNotAcceptFocus,true);window->show();window->resize(1066,709);
            settings.setValue("background.type","Color");settings.setValue("background.color","#8192a2");
            shell->setProperty("currentRoute","my-lists");shell->setProperty("playerCollapsed",false);
            if(restart){state->phase=100;return;}
            if(!radio.isFavorite(podcast))radio.toggleFavorite(podcast);
            if(radio.isFavorite(station))radio.toggleFavorite(station);
            player.openTrack(station);++state->phase;return;
        case 1:
            if(player.state()!="Playing" || player.position()<1200)return;
            state->checks["favorite_title"]=item("myFavoritesTitle") && item("myFavoritesTitle")->property("text").toString()==QStringLiteral("我的收藏");
            click(item("floatingFavoriteButton"));++state->phase;return;
        case 2:
            state->checks["miniplayer_favorite_reaches_radio"]=radio.isFavorite(station) && radio.favorites().size()==2;
            state->checks["radio_not_added_as_song_like"]=!collections.isTrackLiked(station);
            click(item("myFavoritesTabs"),Qt::LeftButton,.75);++state->phase;return;
        case 3:
            state->checks["favorites_grid_count"]=item("myPlaylistGrid") && item("myPlaylistGrid")->property("count").toInt()==2;
            shot("-collections");click(item("myRadioFavoriteCard0"),Qt::LeftButton,.5,.4);++state->phase;return;
        case 4:
            if(player.state()!="Playing" || player.position()<1200)return;
            state->checks["favorite_plays_live"]=player.isCurrentTrack(station) && player.live();
            click(item("myRadioFavoriteCard0"),Qt::RightButton,.5,.4);++state->phase;return;
        case 5:
            shot("-context");click(item("myFavoriteRemove"));++state->phase;return;
        case 6:
            state->checks["remove_keeps_playback"]=!radio.isFavorite(station) && player.state()=="Playing" && player.isCurrentTrack(station);
            state->checks["miniplayer_unliked"]=item("floatingPlayer") && !item("floatingPlayer")->property("favorite").toBool();
            state->checks["remaining_podcast_card"]=item("myPlaylistGrid") && item("myPlaylistGrid")->property("count").toInt()==1;
            click(item("myRadioFavoriteCard0"),Qt::LeftButton,.5,.4);++state->phase;return;
        case 7:
            if(radio.busy())return;
            state->checks["podcast_opens_correct_source"]=shell->property("currentRoute")=="radio" && radio.provider()=="netease" && radio.podcast().value("radioId")==podcast.value("radioId") && !radio.rows().isEmpty();
            shot("-podcast");click(item("radioPodcastBack"));++state->phase;return;
        case 8:
            state->checks["podcast_returns_to_favorites"]=shell->property("currentRoute")=="my-lists" && item("myListsPage") && item("myListsPage")->property("collectionTab").toInt()==1;
            click(item("floatingFavoriteButton"));++state->phase;return;
        case 9:
            state->checks["favorite_readded_from_current_queue"]=radio.isFavorite(station) && radio.favorites().size()==2;
            shot("-returned");state->checks["completed"]=true;finish();return;
        case 100:
            state->checks["restart_restores_all_favorites"]=radio.isFavorite(station) && radio.isFavorite(podcast) && radio.favorites().size()==2;
            state->checks["restart_does_not_fetch_directory"]=!radio.busy() && radio.rows().isEmpty();
            click(item("myFavoritesTabs"),Qt::LeftButton,.75);++state->phase;return;
        case 101:
            state->checks["restart_grid_has_favorites"]=item("myPlaylistGrid") && item("myPlaylistGrid")->property("count").toInt()==2;
            shot("-restored");state->checks["completed"]=true;finish();return;
        }
    });timer->start();
}

inline void runRadioRegression(QApplication& app,QQuickWindow* window,QObject* shell,
    listenfree::qmlbridge::PortableSession& player,listenfree::qmlbridge::SettingsController& settings,
    listenfree::qmlbridge::RadioService& radio,const QString& report) {
    struct State {int phase=0,wait=0,frames=0;bool geometry=true;double wavePhase=0;QJsonObject checks;};
    auto state=std::make_shared<State>();auto* timer=new QTimer(&app);timer->setInterval(80);
    QObject::connect(timer,&QTimer::timeout,&app,[&,window,shell,timer,state,report] {
        const auto item=[&](const QString& name){return uiItem(window->contentItem(),name);};
        const auto shot=[&](const QString& suffix){window->grabWindow().save(report+suffix+".png");};
        const auto geometry=[&] {
            auto* a=item("radioSource0");auto* b=item("radioSource1");auto* c=item("radioSource2");auto* bar=item("radioSources");
            return a && b && c && bar && qAbs(a->width()+b->width()+c->width()-(bar->width()-8))<1 && qAbs(b->x()-a->width())<1 && qAbs(c->x()-b->x()-b->width())<1;
        };
        const auto waiting=[&] {
            if(radio.busy() && ++state->wait<550)return true;
            state->wait=0;return false;
        };
        switch(state->phase) {
        case 0:
            window->setFlag(Qt::WindowTransparentForInput,true);window->setFlag(Qt::WindowDoesNotAcceptFocus,true);window->show();window->resize(1066,709);
            settings.setValue("background.type","Color");settings.setValue("background.color","#8192a2");settings.setValue("ui.animations",true);
            shell->setProperty("currentRoute","radio");++state->phase;break;
        case 1:
            if(waiting())return;
            state->checks["icecast_loaded"]=!radio.rows().isEmpty() && radio.error().isEmpty();radio.search("Anime");++state->phase;break;
        case 2:
            if(waiting())return;
            shot("-icecast");state->checks["initial_geometry"]=geometry();radio.setProvider("radiobrowser");state->frames=0;++state->phase;break;
        case 3:
            window->grabWindow();state->geometry &= geometry();
            if(++state->frames==2)shot("-sources-midpoint");
            if(state->frames<5)return;
            state->checks["source_transition_no_overlap"]=state->geometry;radio.setCategory("CN");++state->phase;break;
        case 4:
            if(waiting())return;
            state->checks["browser_loaded"]=!radio.rows().isEmpty() && radio.error().isEmpty();shot("-browser");radio.setProvider("netease");++state->phase;break;
        case 5:
            if(waiting())return;
            state->checks["netease_loaded"]=!radio.rows().isEmpty() && radio.error().isEmpty();shot("-netease");
            player.openTrack({{"radioProvider","netease-broadcast"},{"radioId","1203"},{"title",QStringLiteral("网易云广播")},{"artist",QStringLiteral("实时广播")},{"isLive",true}});++state->phase;break;
        case 6: {
            if((player.state()!="Playing" || player.position()<1200) && ++state->wait<650)return;
            state->wait=0;auto* wave=item("floatingLiveWave");auto* progress=item("floatingProgressBar");
            state->checks["live_playing"]=player.state()=="Playing" && player.position()>1000;
            state->checks["live_wave_replaces_progress"]=wave && wave->isVisible() && progress && !progress->isVisible();
            auto* left=item("floatingCurrentTime");auto* right=item("floatingRemainingTime");
            state->checks["live_times_hidden"]=left && right && !left->isVisible() && !right->isVisible();
            state->wavePhase=wave?wave->property("phase").toDouble():0;shot("-live");++state->phase;break;
        }
        case 7: {
            auto* wave=item("floatingLiveWave");state->checks["wave_moves"]=wave && wave->property("phase").toDouble()!=state->wavePhase;
            player.stop();radio.setMode("podcast");++state->phase;break;
        }
        case 8:
            if(waiting())return;
            if(++state->frames<25)return;
            state->checks["podcasts_loaded"]=!radio.rows().isEmpty();shot("-podcasts");radio.openPodcast({{"radioId","336355127"},{"title",QStringLiteral("代码时间")}});++state->phase;break;
        case 9:
            if(waiting())return;
            state->checks["programs_loaded"]=radio.rows().size()==30;shot("-programs");window->resize(1600,960);++state->phase;break;
        case 10:
            shot("-wide");state->checks["wide_geometry"]=geometry();shell->setProperty("darkMode",true);++state->phase;break;
        case 11:
            shot("-dark");player.stop();
            {QFile file(report);if(file.open(QIODevice::WriteOnly))file.write(QJsonDocument(QJsonObject{{"checks",state->checks}}).toJson());}
            timer->stop();{bool ok=true;for(const auto& value:state->checks)ok &= value.toBool();app.exit(ok?0:1);}break;
        }
    });timer->start();
}
