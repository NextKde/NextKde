#pragma once

// Opt-in UI acceptance, using the existing application's event helpers.
// Invoke only with --todo-regression and an isolated --data-dir.
inline void runNewTodoRegression(QApplication& app, QQuickWindow* window, QObject* shell,
    listenfree::qmlbridge::PortableSession& player,
    listenfree::qmlbridge::SettingsController& settings, const QString& report) {
    struct State {
        int phase=0, ticks=0, mode=0;
        QJsonObject checks;
        QPointer<QQuickItem> albums, songs, artists, grid;
        QPointer<UiInputProbe> probe;
        QVariantMap track;
        double scroll=0;
    };
    auto state=std::make_shared<State>();
    auto* timer=new QTimer(&app);timer->setInterval(300);
    const auto item=[window](const QString& name){return uiItem(window->contentItem(),name);};
    const auto click=[window](QQuickItem* target, double heightFraction=.5) {
        if(!target)return;
        const auto point=target->mapToScene({target->width()/2,target->height()*heightFraction});
        for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}) {
            QMouseEvent event(type,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,
                type==QEvent::MouseButtonPress?Qt::LeftButton:Qt::NoButton,Qt::NoModifier);
            static ulong timestamp=1;event.setTimestamp(timestamp+=20);
            QCoreApplication::sendEvent(window,&event);
        }
    };
    const auto findPage=[window](const QString& section) {
        const auto visit=[&](auto&& self,QQuickItem* node)->QQuickItem* {
            if(node->objectName()=="libraryPage" && node->property("section")==section)return node;
            for(auto* child:node->childItems())if(auto* result=self(self,child))return result;
            return nullptr;
        };
        return visit(visit,window->contentItem());
    };
    const auto capture=[window,report](const QString& name){window->grabWindow().save(report+"."+name+".png");};
    QObject::connect(timer,&QTimer::timeout,&app,[&,state,timer,item,click,findPage,capture,report,window,shell] {
        const auto finish=[&] {
            timer->stop();player.stop();
            bool passed=true;
            for(auto it=state->checks.begin();it!=state->checks.end();++it)passed=passed&&it.value().toBool();
            state->checks["passed"]=passed;
            QFile file(report);if(file.open(QIODevice::WriteOnly))file.write(QJsonDocument(state->checks).toJson());
            app.exit(passed?0:7);
        };
        if(++state->ticks>180){state->checks["timeout"]=false;finish();return;}
        switch(state->phase++) {
        case 0:
            if(!player.ready()){--state->phase;return;}
            if(player.songs().size()<30){state->checks["library_fixture"]=false;finish();return;}
            shell->setProperty("animationsEnabled",false);
            settings.setValue("ui.motionEnabled",false);
            settings.setValue("appearance.dynamicArtworkEnabled",false);
            settings.setValue("background.type","AutoCover");
            settings.setValue("background.blur",85);
            settings.setValue("background.mask",45);
            state->track=player.songs().first().toMap();
            player.clearQueue();player.enqueueTrack(state->track);player.selectQueue(0,false);
            shell->setProperty("currentRoute","library/albums");return;
        case 1:
            state->albums=findPage("albums");
            if(!state->albums){state->checks["album_page_created"]=false;finish();return;}
            state->albums->setProperty("selectedAlbumIndex",8);
            QMetaObject::invokeMethod(shell,"openCollection",Q_ARG(QVariant,"Album"),Q_ARG(QVariant,state->track.value("album")),Q_ARG(QVariant,"#329bd3"));return;
        case 2:
            state->checks["album_detail_over_retained_page"]=state->albums && item("albumDetailSurface") && !state->albums->isEnabled();
            capture("album");QMetaObject::invokeMethod(shell,"closeCollection");return;
        case 3:
            state->checks["album_selection_restored"]=state->albums && state->albums==findPage("albums") && state->albums->property("selectedAlbumIndex").toInt()==8;
            shell->setProperty("currentRoute","library/songs");return;
        case 4:
            state->songs=findPage("songs");
            if(auto* list=state->songs?uiItem(state->songs,"songTableList"):nullptr){list->setProperty("contentY",680.0);state->scroll=list->property("contentY").toDouble();}
            else {state->checks["song_list_created"]=false;finish();return;}
            shell->setProperty("currentRoute","library/artists");return;
        case 5:
            state->artists=findPage("artists");
            state->grid=state->artists?uiItem(state->artists,"libraryArtistGrid"):nullptr;
            if(!state->grid){state->checks["artist_grid_created"]=false;finish();return;}
            state->grid->setProperty("contentY",700.0);
            shell->setProperty("currentRoute","library/songs");return;
        case 6:
            state->checks["song_scroll_restored"]=state->songs==findPage("songs") && qAbs(uiItem(state->songs,"songTableList")->property("contentY").toDouble()-state->scroll)<1;
            shell->setProperty("currentRoute","library/artists");return;
        case 7:
            state->checks["artist_grid_scroll_restored"]=state->artists==findPage("artists") && qAbs(state->grid->property("contentY").toDouble()-700)<1;
            QMetaObject::invokeMethod(shell,"openCollection",Q_ARG(QVariant,"Artist"),Q_ARG(QVariant,state->track.value("artist")),Q_ARG(QVariant,"#329bd3"));return;
        case 8: {
            auto* photo=item("artistHeroArtwork");
            if(photo&&photo->property("status").toInt()!=1&&state->ticks<40){--state->phase;return;}
            auto* hero=item("artistStickyHeader");
            state->checks["artist_hero_height"]=hero&&hero->height()>=440;
            capture("artist-expanded");
            if(auto* scroll=item("artistScroll"))scroll->setProperty("contentY",650.0);
            return;
        }
        case 9: {
            auto* hero=item("artistStickyHeader");
            state->checks["artist_compact_toolbar"]=hero&&qAbs(hero->height()-64)<1;
            state->checks["artist_actions_available"]=item("artistPlayAllButton")&&item("artistFavoriteButton")&&item("artistBackButton");
            capture("artist-compact");QMetaObject::invokeMethod(shell,"closeCollection");return;
        }
        case 10:
            state->checks["artist_detail_back_restores_grid"]=state->grid&&qAbs(state->grid->property("contentY").toDouble()-700)<1;
            shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.0);return;
        case 11: {
            const auto* action=item("nowPlayingMediaAction");const auto* pill=item("nowPlayingFormatPill");
            state->checks["local_information_button"]=action&&action->property("kind")=="info";
            state->checks["format_pill_removed"]=action&&!pill;
            state->checks["local_media_format"]=player.mediaFormat()==QFileInfo(state->track.value("localPath").toString()).suffix().toUpper();
            capture("nowplaying");player.setPlaybackMode("sequential");return;
        }
        case 12:
            click(item("nowPlayingModeButton"));return;
        case 13: {
            static const QStringList modes{"listLoop","singleLoop","shuffle","stopAfterCurrent","sequential"};
            auto* floating=item("floatingPlayer");auto* page=item("nowPlayingPage");
            state->checks["mode_sync_"+QString::number(state->mode)]=player.playbackMode()==modes[state->mode]
                &&floating&&page&&floating->property("playbackMode")==modes[state->mode]&&page->property("playbackMode")==modes[state->mode];
            if(++state->mode<5){state->phase=12;return;}
            click(item("nowPlayingEqualizerButton"));return;
        }
        case 14: {
            auto* popup=shell->findChild<QObject*>("equalizerPopup");
            state->checks["eq_popup_opened"]=popup&&popup->property("visible").toBool();
            click(item("equalizerToggle"));click(item("eqBand5"),.75);
            state->checks["eq_toggle_keeps_popup_open"]=popup->property("visible").toBool();
            state->probe=new UiInputProbe(item("nowPlayingPage"));state->probe->setSize({50,50});state->probe->setPosition({10,80});state->probe->setZ(999);
            const auto point=state->probe->mapToScene({25,25});
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-120),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);
            QCoreApplication::sendEvent(window,&wheel);
            state->checks["eq_blocks_outside_wheel"]=state->probe->wheels==0;
            click(state->probe);return;
        }
        case 15: {
            auto* popup=shell->findChild<QObject*>("equalizerPopup");
            state->checks["eq_outside_click_closes_without_passthrough"]=popup&&!popup->property("visible").toBool()&&state->probe->presses==0;
            state->probe->deleteLater();state->probe=nullptr;
            state->checks["eq_controller_updated"]=player.equalizerEnabled()&&player.equalizerGains()[5].toDouble()<=-5;
            QMetaObject::invokeMethod(popup,"open");return;
        }
        case 16:
            capture("equalizer");
            QMetaObject::invokeMethod(shell->findChild<QObject*>("equalizerPopup"),"close");
            shell->setProperty("nowPlayingOpen",false);return;
        case 17:
            state->checks["eq_survives_page_recreation"]=player.equalizerEnabled()&&player.equalizerGains()[5].toDouble()<=-5;
            shell->setProperty("nowPlayingOpen",true);
            QTimer::singleShot(100,window,[item,click]{click(item("nowPlayingMediaAction"));});return;
        case 18:
            state->checks["editor_opens_from_nowplaying"]=shell->property("musicEditorOpen").toBool();
            capture("editor");shell->setProperty("musicEditorOpen",false);
            settings.setValue("background.type","Color");settings.setValue("background.color","#c6b49e");settings.setValue("background.mask",30);return;
        case 19:
            state->checks["background_color_live"]=item("globalBackground")&&item("globalBackground")->property("backgroundType")=="Color"&&item("globalBackground")->property("mask").toDouble()==.3 && item("nowPlayingBackground")->property("mask").toDouble()==.24;
            capture("color");
            settings.setValue("background.type","Image");
            settings.setValue("background.image",QUrl("qrc:/qt/qml/ListenFree/Bootstrap/music_player_desktop/assets/album_Cover_2@2x.png"));
            settings.setValue("background.blur",35);return;
        case 20:
            state->checks["background_image_live"]=item("globalBackground")->property("backgroundType")=="Image"&&item("nowPlayingBackground")->property("backgroundType")=="AutoCover";
            capture("image");settings.setValue("background.type","AutoCover");settings.setValue("nowPlaying.backgroundStyle","DynamicFlow");return;
        case 21:
            state->checks["background_auto_cover_live"]=item("globalBackground")->property("backgroundType")=="AutoCover"&&item("nowPlayingBackground")->property("visualStyle")=="DynamicFlow";
            capture("flow");
            player.enqueueTrack({{"trackId","test:remote"},{"title","网络曲目"},{"artist","测试艺术家"},{"album","测试专辑"},{"remoteUrl","https://example.invalid/music.mp3"}});player.selectQueue(1,false);return;
        case 22:
            state->checks["remote_download_button"]=item("nowPlayingMediaAction")&&item("nowPlayingMediaAction")->property("kind")=="download";
            click(item("nowPlayingMediaAction"));return;
        case 23:
            if(auto* popup=shell->findChild<QObject*>("downloadSpecificationDialog"))state->checks["existing_download_picker_opened"]=popup->property("visible").toBool();
            else state->checks["existing_download_picker_opened"]=false;
            QMetaObject::invokeMethod(shell->findChild<QObject*>("downloadSpecificationDialog"),"close");
            player.selectQueue(0,false);
            QMetaObject::invokeMethod(item("nowPlayingPage"),"lyricsMatchRequested");return;
        case 24: {
            auto* popup=shell->findChild<QObject*>("lyricsMatchPopup");
            state->checks["lyrics_match_popup_opened"]=popup&&popup->property("visible").toBool();
            capture("lyric-match");
            state->probe=new UiInputProbe(item("nowPlayingPage"));state->probe->setSize({50,50});state->probe->setPosition({10,80});state->probe->setZ(999);
            const auto point=state->probe->mapToScene({25,25});
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-120),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);
            QCoreApplication::sendEvent(window,&wheel);click(state->probe);return;
        }
        case 25: {
            auto* popup=shell->findChild<QObject*>("lyricsMatchPopup");
            state->checks["lyrics_match_overlay_blocks_input"]=popup&&!popup->property("visible").toBool()&&state->probe->wheels==0&&state->probe->presses==0;
            state->probe->deleteLater();state->probe=nullptr;finish();return;
        }
        }
    });
    timer->start();
}
