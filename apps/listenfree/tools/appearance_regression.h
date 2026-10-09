#pragma once
#include <QJsonArray>
#include <QQmlContext>

// Runs only when explicitly requested, with a separate --data-dir.
inline void runAppearanceRegression(QApplication& app, QQuickWindow* window, QObject* shell,
    listenfree::qmlbridge::PortableSession& player,
    listenfree::qmlbridge::SettingsController& settings, const QString& report) {
    struct State { int phase=0, ticks=0, flowWait=0; double previewWidth=0, barSize=0, flowPhase=0; QJsonObject checks, measures; QVariantMap track; QVariantList tracks; QVariant npSource; QPointer<UiInputProbe> probe; QPointer<QQuickItem> flow; QSharedPointer<QQuickItemGrabResult> flowGrab; QImage flowFrame; };
    auto state=std::make_shared<State>();
    auto* timer=new QTimer(&app); timer->setInterval(450);
    QObject::connect(timer,&QTimer::timeout,&app,[&,window,shell,report,state,timer] {
        const auto item=[&](const QString& name){return uiItem(window->contentItem(),name);};
        const auto searchItem=[&](const QString& name){return uiItem(item("searchPage"),name);};
        const auto mapProperty=[](QObject* object,const char* name) {
            const auto value=object->property(name);
            return value.metaType()==QMetaType::fromType<QJSValue>() ? value.value<QJSValue>().toVariant().toMap() : value.toMap();
        };
        const auto capture=[&](const QString& name){window->grabWindow().save(report+"."+name+".png");};
        const auto click=[&](QQuickItem* target) {
            if(!target)return;
            const auto point=target->mapToScene({target->width()/2,20});
            for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}) {
                QMouseEvent event(type,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,type==QEvent::MouseButtonPress?Qt::LeftButton:Qt::NoButton,Qt::NoModifier);
                static ulong stamp=1;event.setTimestamp(stamp+=20);QCoreApplication::sendEvent(window,&event);
            }
        };
        const auto movePointer=[&](const QPointF& point) {
            QMouseEvent event(QEvent::MouseMove,point,point,window->mapToGlobal(point.toPoint()),Qt::NoButton,Qt::NoButton,Qt::NoModifier);
            QCoreApplication::sendEvent(window,&event);
        };
        const auto songRows=[&] {
            QList<QQuickItem*> rows;
            const auto visit=[&](auto&& self,QQuickItem* node)->void {
                if(!node||!node->isVisible())return;
                if(node->objectName()=="songRow")rows.append(node);
                for(auto* child:node->childItems())self(self,child);
            };
            visit(visit,window->contentItem());return rows;
        };
        const auto followsPlayback=[&] {
            const auto rows=songRows();bool found=false;
            for(auto* row:rows) {
                const bool expected=row->property("track").toMap().value("trackId").toString()==player.currentTrackId();
                found|=expected;
                if(row->property("current").toBool()!=expected)return false;
                if(!expected&&!row->property("hovered").toBool()&&row->property("color").value<QColor>().alpha()>0)return false;
            }
            return found;
        };
        const auto otherRow=[&]()->QQuickItem* {
            for(auto* row:songRows())if(row->property("track").toMap().value("trackId").toString()!=player.currentTrackId())return row;
            return nullptr;
        };
        const auto finish=[&] {
            timer->stop();bool pass=true;
            for(auto it=state->checks.begin();it!=state->checks.end();++it)pass&=it.value().toBool();
            state->checks["passed"]=pass;
            if(!state->measures.isEmpty())state->checks["measurements"]=state->measures;
            QFile file(report);if(file.open(QIODevice::WriteOnly)){file.write(QJsonDocument(state->checks).toJson());file.close();}app.exit(pass?0:7);
        };
        if(++state->ticks>140){state->checks["timeout"]=false;finish();return;}
        switch(state->phase++) {
        case 0:
            if(!player.ready()){--state->phase;return;}
            settings.setValue("ui.motionEnabled",false);
            settings.setValue("appearance.dynamicArtworkEnabled",false);
            shell->setProperty("animationsEnabled",false);
            if(QCoreApplication::arguments().contains("--classic-lyrics-only")){state->phase=500;return;}
            if(QCoreApplication::arguments().contains("--mix-status-only")){state->phase=480;return;}
            if(QCoreApplication::arguments().contains("--overflow-player-only")){state->phase=440;return;}
            if(QCoreApplication::arguments().contains("--lyric-sources-only")){state->phase=120;return;}
            if(QCoreApplication::arguments().contains("--sylvakru-only")){state->phase=150;return;}
            if(QCoreApplication::arguments().contains("--metadata-only")){state->phase=100;return;}
            if(QCoreApplication::arguments().contains("--metadata-query-only")){state->phase=100;return;}
            if(QCoreApplication::arguments().contains("--search-scroll-only")){state->phase=200;return;}
            if(QCoreApplication::arguments().contains("--search-ui-only")){state->phase=210;return;}
            if(QCoreApplication::arguments().contains("--album-layout-only")){state->phase=230;return;}
            if(QCoreApplication::arguments().contains("--playlist-popup-only")){state->phase=240;return;}
            if(QCoreApplication::arguments().contains("--nowplaying-morph-only")){state->phase=250;return;}
            if(QCoreApplication::arguments().contains("--nowplaying-layout-only")){state->phase=280;return;}
            if(QCoreApplication::arguments().contains("--global-layout-only")){state->phase=300;return;}
            if(QCoreApplication::arguments().contains("--cover-grid-only")){state->phase=330;return;}
            if(QCoreApplication::arguments().contains("--volume-controls-only")){state->phase=360;return;}
            if(QCoreApplication::arguments().contains("--album-mosaic-only")){state->phase=380;return;}
            if(QCoreApplication::arguments().contains("--discovery-home-only")){state->phase=400;return;}
            if(QCoreApplication::arguments().contains("--scrollbars-only")){state->phase=420;return;}
            if(QCoreApplication::arguments().contains("--scrollbars-restore-only")){state->phase=426;return;}
            if(QCoreApplication::arguments().contains("--miniplayer-glass-only")){state->phase=260;return;}
            if(QCoreApplication::arguments().contains("--dynamic-autoplay-only")){state->phase=220;return;}
            if(QCoreApplication::arguments().contains("--artist-menu-only")){state->phase=180;return;}
            if(QCoreApplication::arguments().contains("--empty-lyrics-only")){state->phase=190;return;}
            if(QCoreApplication::arguments().contains("--album-artist-only")){state->phase=130;return;}
            if(QCoreApplication::arguments().contains("--miniplayer-only")){state->phase=80;return;}
            if(QCoreApplication::arguments().contains("--flow-only")){state->phase=50;return;}
            if(QCoreApplication::arguments().contains("--sidebar-lists-only")){state->phase=30;return;}
            state->track=player.songs().isEmpty()?QVariantMap{}:player.songs().first().toMap();
            player.clearQueue();player.enqueueTrack(state->track);player.selectQueue(0,false);
            settings.setValue("background.type","AutoCover");settings.setValue("background.mask",0);
            settings.setValue("nowPlaying.backgroundStyle","BlurredArtwork");
            shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.0);return;
        case 500:
            window->showNormal();window->resize(1200,800);
            settings.setValue("nowPlaying.playerStyle","Classic");
            shell->setProperty("animationsEnabled",true);
            shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.0);return;
        case 501: {
            auto* page=item("nowPlayingPage");if(!page){--state->phase;return;}
            QVariantList lines;
            for(int i=0;i<24;++i) {
                QVariantList words{QVariantMap{{"text",QStringLiteral("让此刻 ")},{"startMs",i*4000},{"endMs",i*4000+400}},
                    QVariantMap{{"text",QStringLiteral("停留")},{"startMs",i*4000+400},{"endMs",i*4000+3400}}};
                lines.append(QVariantMap{{"text",QStringLiteral("让此刻 停留")},{"translation","Let this moment stay"},{"timeMs",i*4000},{"words",words}});
            }
            page->setProperty("lyrics",lines);page->setProperty("currentLine",3);page->setProperty("positionMs",12500);
            page->setProperty("playing",true);page->setProperty("reducedMotion",false);return;
        }
        case 502: {
            auto* panel=item("nowPlayingLyricsPanel");auto* page=item("nowPlayingPage");
            auto* word=item("lyricWord3/1");auto* list=item("lyricList");
            if(!word||!list){state->checks["lyrics_created"]=false;finish();return;}
            state->previewWidth=word->y();state->barSize=list->property("contentY").toDouble();
            state->checks["lyrics_reach_window_bottom"]=qAbs(panel->mapToScene({0,panel->height()}).y()-window->height())<1;
            auto* comments=item("nowPlayingCommentsButton");auto* immersive=item("nowPlayingImmersiveButton");
            const auto a=comments->mapToScene({0,0}),b=immersive->mapToScene({0,0});
            state->checks["utility_vertical_at_edge"]=qAbs(a.x()-b.x())<1&&a.y()+comments->height()<b.y()&&window->width()-b.x()-immersive->width()<16;
            page->setProperty("positionMs",14200);capture("rise-start");return;
        }
        case 503: {
            auto* glyph=item("lyricGrapheme3/1/0");
            state->checks["long_word_rises_and_scales"]=item("lyricWord3/1")->y()<state->previewWidth&&glyph&&glyph->scale()>1.01;
            capture("long-word");
            // A fully occluded regression window can suspend Qt's frame-driven
            // animation clock. Input/idle timing runs independently of that
            // visual clock; motion was measured above while it was enabled.
            item("nowPlayingLyricsPanel")->setProperty("animationActive",false);
            auto* panel=item("nowPlayingLyricsPanel");const auto point=panel->mapToScene({panel->width()/2,panel->height()/2});
            movePointer(point);
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-240),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);
            QCoreApplication::sendEvent(window,&wheel);return;
        }
        case 504:
            state->flowPhase=item("lyricList")->property("contentY").toDouble();
            state->checks["wheel_scrolls_lyrics"]=qAbs(state->flowPhase-state->barSize)>10;
            item("nowPlayingPage")->setProperty("currentLine",4);return;
        case 505:
            state->checks["song_line_does_not_steal_scroll"]=qAbs(item("lyricList")->property("contentY").toDouble()-state->flowPhase)<1;
            capture("manual-scroll");state->flowWait=0;return;
        case 506:
            if(++state->flowWait<12){--state->phase;return;}
            state->checks["focus_returns_after_idle"]=qAbs(item("lyricList")->property("contentY").toDouble()-state->flowPhase)>10;
            item("nowPlayingPage")->setProperty("playing",false);return;
        case 507:
            if(++state->flowWait<17){--state->phase;return;}
            state->checks["paused_lines_restore_scale"]=qAbs(item("lyricPrimary3")->scale()-1)<.002;
            capture("paused");finish();return;
        case 480:
            window->showNormal();window->resize(1200,800);
            settings.setValue("nowPlaying.playerStyle","Classic");
            shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.0);return;
        case 481:
            if(!item("nowPlayingMixStatus")){--state->phase;return;}
            state->checks["idle_has_no_mix_label"]=!item("nowPlayingMixStatus")->isVisible();
            item("nowPlayingPage")->setProperty("mixing",true);
            item("nowPlayingPage")->setProperty("playing",true);
            item("nowPlayingPage")->setProperty("reducedMotion",false);return;
        case 482: {
            auto* label=item("nowPlayingMixStatus");auto* bar=item("nowPlayingProgressBar");
            state->checks["mix_label_visible"]=label->isVisible();
            state->checks["label_below_progress"]=label->y()>=bar->y()+bar->height();
            state->checks["label_centered"]=qAbs(label->x()+label->width()/2-bar->width()/2)<1;
            state->checks["small_grey_text"]=label->property("text").toString()==QStringLiteral("混音");
            state->flowPhase=label->property("shimmerPhase").toDouble();capture("classic");return;
        }
        case 483:
            state->checks["highlight_moves_right"]=item("nowPlayingMixStatus")->property("shimmerPhase").toDouble()>state->flowPhase;
            capture("classic-highlight");item("nowPlayingPage")->setProperty("reducedMotion",true);return;
        case 484:
            state->checks["reduced_motion_keeps_text"]=item("nowPlayingMixStatus")->isVisible()&&!item("nowPlayingMixStatus")->property("shimmering").toBool();
            state->flowPhase=item("nowPlayingMixStatus")->property("shimmerPhase").toDouble();return;
        case 485:
            state->checks["reduced_motion_stops_highlight"]=item("nowPlayingMixStatus")->property("shimmerPhase").toDouble()==state->flowPhase;
            settings.setValue("nowPlaying.playerStyle","Overflow");return;
        case 486: {
            auto* label=item("nowPlayingMixStatus");auto* bar=item("nowPlayingProgressBar");
            state->checks["overflow_label_visible_without_controls"]=label->isVisible();
            state->checks["overflow_progress_still_flush"]=qAbs(bar->mapToScene({0,bar->height()}).y()-window->height())<1;
            state->checks["overflow_label_inside_window"]=label->mapToScene({0,label->height()}).y()<window->height();
            capture("overflow");item("nowPlayingPage")->setProperty("mixing",false);return;
        }
        case 487:
            state->checks["completion_hides_label"]=!item("nowPlayingMixStatus")->isVisible();
            state->checks["hidden_stops_highlight"]=!item("nowPlayingMixStatus")->property("shimmering").toBool();
            finish();return;
        case 440:
            window->showNormal();window->resize(1440,900);
            settings.setValue("nowPlaying.playerStyle","Classic");
            state->track=player.songs().isEmpty()?QVariantMap{}:player.songs().first().toMap();
            for(const auto& song:player.songs())if(song.toMap().value("title").toString()==QStringLiteral("Love Story")){state->track=song.toMap();break;}
            player.setVolume(0.f);player.clearQueue();player.enqueueTrack(state->track);player.selectQueue(0,true);
            shell->setProperty("settingsOpen",true);return;
        case 441:
            item("settingsPage")->setProperty("selectedCategory",3);return;
        case 442: {
            auto* row=item("settingRow/nowPlaying.playerStyle");
            state->checks["appearance_style_selector_present"]=row && row->property("currentIndex").toInt()==0;
            if(!row){finish();return;}
            QMetaObject::invokeMethod(row,"settingChanged",Q_ARG(QString,QString("nowPlaying.playerStyle")),Q_ARG(QVariant,QVariant("Overflow")));
            state->checks["appearance_selector_saves_overflow"]=settings.value("nowPlaying.playerStyle",{}).toString()=="Overflow";
            capture("settings");shell->setProperty("settingsOpen",false);
            shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.0);shell->setProperty("coverMorphProgress",1.0);return;
        }
        case 443: {
            if(player.duration()<10000){--state->phase;return;}
            player.pause();
            auto* page=item("nowPlayingPage");
            if(!page){state->checks["page_created"]=false;finish();return;}
            state->flow=item("nowPlayingLyricsPanel");
            QVariantList lines;
            for(int i=0;i<12;++i)lines.append(QVariantMap{{"text",QStringList{QStringLiteral("风穿过安静的街"),QStringLiteral("光落在窗边"),QStringLiteral("把这一刻留在耳边"),QStringLiteral("继续向前")}[i%4]},{"timeMs",i*10000}});
            page->setProperty("lyrics",lines);page->setProperty("currentLine",2);
            movePointer({window->width()/2.0,40});state->flowWait=0;return;
        }
        case 444: {
            if(++state->flowWait<3){--state->phase;return;}
            auto* page=item("nowPlayingPage");auto* cover=item("nowPlayingArtwork");auto* bar=item("nowPlayingProgressBar");
            const auto rect=cover->mapRectToScene(cover->boundingRect());
            state->checks["cover_fills_left_top_to_bottom"]=qAbs(rect.left())<1&&qAbs(rect.top())<1&&qAbs(rect.height()-page->height())<1&&qAbs(rect.width()-page->width()*.68)<1;
            state->checks["cover_loaded"]=!cover->property("missingArtwork").toBool();
            state->checks["lyrics_on_right"]=item("nowPlayingLyricsRegion")->x()>page->width()*.6;
            state->checks["small_top_song_heading"]=item("overflowTrackHeading")->isVisible()&&item("overflowTrackHeading")->y()<16;
            state->checks["idle_progress_flush_bottom_readonly"]=bar->height()==2&&!bar->property("interactive").toBool()&&qAbs(bar->mapToScene({0,bar->height()}).y()-page->height())<1;
            state->checks["idle_controls_hidden"]=item("nowPlayingTransport")->opacity()==0;
            capture("idle");movePointer({window->width()/2.0,window->height()-2.0});return;
        }
        case 445: {
            auto* bar=item("nowPlayingProgressBar");
            state->checks["bottom_hover_expands_controls"]=item("nowPlayingTransport")->opacity()>.99&&bar->height()==24&&bar->property("trackThickness").toDouble()==6&&bar->property("interactive").toBool();
            auto* track=uiItem(bar,"progressTrack");
            state->checks["expanded_progress_flush_bottom"]=track && qAbs(track->mapToScene({0,track->height()}).y()-window->height())<1;
            capture("controls");
            auto point=bar->mapToScene({bar->width()*.3,bar->height()/2});
            QMouseEvent press(QEvent::MouseButtonPress,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,Qt::LeftButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&press);
            point=bar->mapToScene({bar->width()*.6,-180});
            QMouseEvent move(QEvent::MouseMove,point,point,window->mapToGlobal(point.toPoint()),Qt::NoButton,Qt::LeftButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&move);
            state->flowWait=0;return;
        }
        case 446: {
            if(++state->flowWait<3){--state->phase;return;}
            auto* bar=item("nowPlayingProgressBar");
            state->checks["drag_outside_bottom_keeps_controls"]=bar->property("pressed").toBool()&&item("nowPlayingTransport")->opacity()>.99;
            const auto point=bar->mapToScene({bar->width()*.6,-180});
            QMouseEvent release(QEvent::MouseButtonRelease,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,Qt::NoButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&release);
            state->checks["drag_commits_seek"]=qAbs(bar->property("dragValue").toDouble()-.6)<.01;
            state->flowWait=0;return;
        }
        case 447:
            if(++state->flowWait<3){--state->phase;return;}
            state->checks["leaving_bottom_hides_again"]=item("nowPlayingTransport")->opacity()==0;
            state->checks["seek_reaches_playback"]=player.duration()>0&&qAbs(player.position()-player.duration()*.6)<2500;
            state->measures["seek_position"]=double(player.position());state->measures["duration"]=double(player.duration());
            window->resize(1000,650);return;
        case 448:
            state->checks["compact_lyrics_have_room"]=item("nowPlayingLyricsRegion")->width()>280;
            state->checks["compact_cover_full_height"]=qAbs(item("nowPlayingArtwork")->height()-window->height())<1;
            movePointer({window->width()/2.0,window->height()-2.0});return;
        case 449: {
            capture("compact-controls");
            const auto point=item("nowPlayingVolumeSlider")->mapToScene({item("nowPlayingVolumeSlider")->width()*.4,7});
            for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}){QMouseEvent event(type,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,type==QEvent::MouseButtonPress?Qt::LeftButton:Qt::NoButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&event);}
            state->checks["volume_control_connected"]=qAbs(player.volume()-.4)<.02;
            auto* comments=item("nowPlayingCommentsButton");auto* immersive=item("nowPlayingImmersiveButton");auto* queue=item("nowPlayingQueueButton");
            state->checks["utility_buttons_bottom_right_in_order"]=comments->mapToScene({0,0}).x()<immersive->mapToScene({0,0}).x()&&immersive->mapToScene({0,0}).x()<queue->mapToScene({0,0}).x()&&qAbs(queue->mapToScene({0,0}).y()-(window->height()-77))<1;
            click(queue);state->phase=460;return;
        }
        case 460:
            state->checks["overflow_queue_opens_at_right"]=shell->property("queueOpen").toBool()&&qAbs(item("playbackQueuePanel")->x()+item("playbackQueuePanel")->width()-window->width())<1;
            capture("right-queue");shell->setProperty("queueProgress",.5);return;
        case 461:
            state->checks["overflow_queue_slides_from_right"]=qAbs(item("playbackQueuePanel")->x()-(window->width()-item("playbackQueuePanel")->width()*.5))<1;
            capture("right-queue-midpoint");QMetaObject::invokeMethod(shell,"closeQueue");shell->setProperty("queueProgress",0.0);
            QMetaObject::invokeMethod(item("nowPlayingPage"),"toggleImmersive");return;
        case 462:
            state->checks["immersive_button_enters_native_stage"]=item("immersiveStage")&&item("nowPlayingPage")->property("immersiveActive").toBool();
            capture("immersive");QMetaObject::invokeMethod(item("nowPlayingPage"),"toggleImmersive");return;
        case 463:
            state->checks["immersive_restores_window"]=window->visibility()==QWindow::Windowed;
            settings.setValue("nowPlaying.playerStyle","Classic");state->phase=450;return;
        case 450:
            state->checks["classic_restores_square_cover"]=qAbs(item("nowPlayingArtwork")->width()-item("nowPlayingArtwork")->height())<1;
            state->checks["classic_controls_stay_visible"]=item("nowPlayingTransport")->opacity()==1&&item("nowPlayingProgressBar")->property("interactive").toBool();
            state->checks["style_switch_keeps_lyrics_component"]=state->flow==item("nowPlayingLyricsPanel");
            state->checks["style_switch_keeps_track"]=player.currentTrackId()==state->track.value("trackId").toString();
            capture("classic");settings.setValue("nowPlaying.playerStyle","Overflow");return;
        case 451:
            item("nowPlayingPage")->setProperty("artworkSource",QUrl("file:///missing-overflow-cover.jpg"));state->flowWait=0;return;
        case 452:
            if(++state->flowWait<3){--state->phase;return;}
            state->checks["missing_cover_retains_page_and_controls"]=item("nowPlayingArtwork")->property("missingArtwork").toBool()&&item("overflowTrackHeading")->isVisible();
            capture("missing");finish();return;
        case 200:
            shell->setProperty("currentRoute","search");return;
        case 201: {
            auto* table=searchItem("songTable");
            for(int i=0;i<30;++i)state->tracks.append(QVariantMap{{"trackId",QString("kw:%1").arg(i)},{"source","kw"},{"rid",QString::number(i)},{"title",QString("搜索结果 %1").arg(i)},{"artist","测试"},{"artwork","file:///missing-fixture.jpg"}});
            table->setProperty("rows",state->tracks);return;
        }
        case 202:
            searchItem("songTableList")->setProperty("contentY",700);return;
        case 203: {
            state->previewWidth=searchItem("songTableList")->property("contentY").toDouble();
            auto row=state->tracks[12].toMap();row["artwork"]="file:///loaded-fixture.jpg";state->tracks[12]=row;
            searchItem("songTable")->setProperty("rows",state->tracks);return;
        }
        case 204:
            state->measures["scroll_before_cover"]=state->previewWidth;
            state->measures["scroll_after_cover"]=searchItem("songTableList")->property("contentY").toDouble();
            state->checks["artwork_update_preserves_scroll"]=state->previewWidth>500 && qAbs(searchItem("songTableList")->property("contentY").toDouble()-state->previewWidth)<1;
            capture("search-scroll");finish();return;
        case 210:
            settings.setValue("background.type","Image");settings.setValue("background.image","");settings.setValue("background.mask",0);
            shell->setProperty("currentRoute","discover");player.setPlatform("kw");
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("Taylor Swift")));return;
        case 211: {
            if(player.busy()){--state->phase;return;}
            state->checks["search_first_page_30"]=player.searchResults().size()==30;
            state->checks["search_toolbars_share_row"]=item("searchCategoryToolbar") && qAbs(item("searchCategoryToolbar")->y()-item("searchPlatformToolbar")->y())<1;
            state->checks["pagination_is_compact"]=item("searchPaginationToolbar")->height()<item("searchPlatformToolbar")->height();
            auto* list=searchItem("songTableList");auto* footer=item("searchInlineFooter");
            state->checks["pagination_follows_all_30_songs"]=footer && footer->y()>=30*searchItem("songTable")->property("rowHeight").toDouble()-1;
            state->checks["pagination_outside_initial_viewport"]=footer && footer->mapToScene({0,0}).y()>=list->mapToScene({0,list->height()}).y();
            capture("search-top");
            QMetaObject::invokeMethod(list,"positionViewAtEnd");state->phase=216;return;
        }
        case 216: {
            auto* list=searchItem("songTableList");auto* pager=item("searchPaginationToolbar");
            state->checks["pagination_reachable_at_list_end"]=pager->mapToScene({0,0}).y()>=list->mapToScene({0,0}).y() && pager->mapToScene({0,pager->height()}).y()<=list->mapToScene({0,list->height()}).y();
            state->previewWidth=item("searchInlineFooter")->y();state->barSize=pager->mapToScene({0,0}).y();
            capture("search-bottom");shell->setProperty("playerCollapsed",true);return;
        }
        case 217:
            state->checks["miniplayer_does_not_reposition_pagination"]=qAbs(item("searchInlineFooter")->y()-state->previewWidth)<1 && qAbs(item("searchPaginationToolbar")->mapToScene({0,0}).y()-state->barSize)<1;
            shell->setProperty("playerCollapsed",false);
            click(item("searchPageButton2"));state->phase=212;return;
        case 212: {
            if(player.busy()){--state->phase;return;}
            state->checks["page_button_loads_second_page"]=player.searchPage()==2 && player.searchResults().size()==30;
            state->checks["new_page_starts_at_top"]=qAbs(searchItem("songTableList")->property("contentY").toDouble())<1;
            capture("search-songs");
            auto* tabs=item("searchCategoryToolbar");const auto point=tabs->mapToScene({tabs->width()*5/6,tabs->height()/2});
            for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}) {
                QMouseEvent event(type,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,type==QEvent::MouseButtonPress?Qt::LeftButton:Qt::NoButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&event);
            }return;
        }
        case 213:
            if(player.busy()){--state->phase;return;}
            state->checks["album_tab_resets_page"]=player.searchCategory()=="albums" && player.searchPage()==1;
            state->checks["album_tab_has_real_cards"]=item("searchCollectionGrid")->isVisible() && !player.searchResults().isEmpty() && player.searchResults().first().toMap().value("kind")=="album";
            capture("search-albums");click(item("searchCollectionCard"));return;
        case 214: {
            auto* controller=shell->property("playlistController").value<QObject*>();
            if(controller && controller->property("detailBusy").toBool()){--state->phase;return;}
            const auto value=shell->property("selectedCollectionRows");
            const auto rows=value.metaType()==QMetaType::fromType<QJSValue>() ? value.value<QJSValue>().toVariant().toList() : value.toList();
            state->checks["album_card_opens_detail"]=shell->property("currentRoute")=="detail/album" && !rows.isEmpty();
            state->checks["search_album_uses_regular_detail"]=item("playlistDetailPage")->isVisible() && !item("collectionPage")->property("albumWindow").toBool() && !item("albumDetailSurface");
            state->checks["regular_detail_hides_retained_search_grid"]=item("navigationStateCache")->opacity()<.01;
            capture("search-album-detail");QMetaObject::invokeMethod(shell,"closeCollection");return;
        }
        case 215: {
            state->checks["return_keeps_search_category"]=shell->property("currentRoute")=="search" && player.searchCategory()=="albums" && item("searchCollectionGrid")->isVisible();
            auto* grid=item("searchCollectionGrid");auto* footer=item("searchInlineFooter");
            const int columns=qMax(1,int(grid->width()/grid->property("cellWidth").toDouble()));
            const int rows=(player.searchResults().size()+columns-1)/columns;
            state->checks["collection_pagination_follows_cards"]=footer && qAbs(footer->y()-rows*grid->property("cellHeight").toDouble())<2;
            QMetaObject::invokeMethod(grid,"positionViewAtEnd");state->phase=218;return;
        }
        case 218:
            capture("search-albums-bottom");finish();return;
        case 230:
            shell->setProperty("currentRoute","library/albums");settings.setValue("appearance.albumLayout","Flow");return;
        case 231:
            state->checks["local_album_flow_available"]=item("libraryAlbumFlow") && item("libraryAlbumFlow")->isVisible();
            shell->setProperty("settingsOpen",true);return;
        case 232:
            QMetaObject::invokeMethod(item("settingsPage"),"handleSettingChanged",Q_ARG(QVariant,QVariant("appearance.albumLayout")),Q_ARG(QVariant,QVariant("Grid")));
            shell->setProperty("settingsOpen",false);return;
        case 233:
            state->checks["album_setting_switches_to_grid"]=settings.value("appearance.albumLayout")=="Grid" && item("libraryAlbumGrid")->isVisible() && !item("libraryAlbumFlow")->isVisible();
            state->checks["grid_releases_flow_delegates"]=!item("albumCard0");
            state->checks["grid_uses_real_albums"]=item("libraryAlbumGrid")->property("count").toInt()==player.albums().size();
            capture("local-album-grid");click(item("libraryAlbumCard0"));return;
        case 234:
            if(shell->property("collectionMorphActive").toBool()){--state->phase;return;}
            state->checks["local_grid_album_opens_regular_detail"]=shell->property("currentRoute")=="detail/album" && item("collectionPage") && !item("collectionPage")->property("albumWindow").toBool() && item("playlistDetailPage")->isVisible() && !item("albumDetailSurface");
            state->checks["grid_album_uses_card_transition"]=shell->property("collectionMorphUsesGrid").toBool() && !item("collectionMorphSurface")->property("visible").toBool();
            state->checks["grid_album_detail_hides_primary_grid"]=item("navigationStateCache")->opacity()<.01;
            state->checks["grid_album_uses_detail_background"]=shell->property("backgroundArtwork").toUrl()==shell->property("selectedCollectionArtwork").toUrl();
            capture("local-grid-album-detail");
            QMetaObject::invokeMethod(shell,"closeCollection");return;
        case 235:
            if(shell->property("collectionMorphActive").toBool()){--state->phase;return;}
            state->checks["return_preserves_album_grid"]=shell->property("currentRoute")=="library/albums" && item("libraryAlbumGrid")->isVisible();
            shell->setProperty("settingsOpen",true);return;
        case 236:
            QMetaObject::invokeMethod(item("settingsPage"),"handleSettingChanged",Q_ARG(QVariant,QVariant("appearance.albumLayout")),Q_ARG(QVariant,QVariant("Flow")));
            shell->setProperty("settingsOpen",false);return;
        case 237:
            state->checks["album_setting_switches_back_to_flow"]=settings.value("appearance.albumLayout")=="Flow" && item("libraryAlbumFlow")->isVisible() && !item("libraryAlbumGrid")->isVisible();
            state->npSource=shell->property("backgroundArtwork");
            click(item("albumCard"+QString::number(item("libraryAlbumFlow")->parentItem()->property("selectedAlbumIndex").toInt())));return;
        case 238:
            if(shell->property("collectionMorphActive").toBool()){--state->phase;return;}
            state->checks["flow_album_keeps_window_detail"]=shell->property("currentRoute")=="detail/album" && item("collectionPage") && item("collectionPage")->property("albumWindow").toBool() && item("albumDetailSurface") && !shell->property("collectionMorphUsesGrid").toBool();
            state->checks["flow_album_keeps_playing_background"]=shell->property("backgroundArtwork").toUrl()==state->npSource.toUrl();
            shell->setProperty("selectedCollectionArtwork",QUrl("qrc:/qt/qml/ListenFree/assets/album_Cover_7.png"));
            state->checks["flow_album_ignores_detail_cover_change"]=shell->property("backgroundArtwork").toUrl()==state->npSource.toUrl();
            capture("local-flow-album-detail");
            finish();return;
        case 240:
            state->npSource=shell->property("selectedCollectionTitle");
            shell->setProperty("currentRoute","playlists");return;
        case 260:
            shell->setProperty("settingsOpen",false);shell->setProperty("nowPlayingOpen",false);shell->setProperty("playerCollapsed",false);
            shell->setProperty("currentRoute","library/artists");return;
        case 420:
            settings.setValue("ui.showScrollbars",true);
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("settingsOpen",true);return;
        case 421: {
            auto* page=item("settingsPage");if(!page){--state->phase;return;}
            page->setProperty("filterText","全局滚动条");capture("setting");
            state->checks["global_scrollbar_setting_removed"]=!item("settingSwitch/ui.showScrollbars")&&!mapProperty(page,"settingKeys").contains("showScrollbars");
            return;
        }
        case 422: {
            auto* frost=item("sidebarFrost");
            state->checks["sidebar_uses_light_backdrop_blur"]=frost&&frost->property("backdropBlur").toDouble()==12&&frost->property("backdrop").value<QObject*>()!=item("libraryBackdrop");
            shell->setProperty("settingsOpen",false);
            auto* fixture=new QQmlComponent(qmlEngine(shell),shell);
            fixture->setObjectName("scrollbarFixtureComponent");
            fixture->setData(R"qml(import QtQuick
QtObject {
 property var lyricCandidates: []
 property var lyricMatchSources: []
 property var lyricPreviewLines: []
 property string lyricPreview: "fixture"
 property bool lyricMatchBusy: false
 property string lyricMatchError: ""
 function cancelLyricMatch() {}
 function releaseLyricMatch() { lyricPreviewLines=[];lyricCandidates=[];lyricPreview="" }
})qml",qmlContext(shell)->baseUrl());
            state->phase=428;return;
        }
        case 428: {
            auto* fixture=shell->findChild<QQmlComponent*>("scrollbarFixtureComponent");
            if(fixture->isLoading()){--state->phase;return;}
            if(fixture->isError())qWarning().noquote()<<fixture->errorString();
            auto* controller=fixture->create(qmlContext(shell));
            if(!controller){state->checks["fixture_created"]=false;finish();return;}
            controller->setParent(shell);controller->setObjectName("scrollbarFixture");
            QVariantList lines,candidates;
            for(int i=0;i<40;++i){lines.append(QVariantMap{{"timeMs",i*2000},{"text",QString("歌词预览第 %1 行，关闭滚动条后继续滚轮浏览。").arg(i+1)}});candidates.append(QVariantMap{{"title",QString("验证歌曲 %1").arg(i+1)},{"artist","测试艺术家"},{"score",100}});}
            controller->setProperty("lyricPreviewLines",lines);controller->setProperty("lyricCandidates",candidates);
            auto* popup=shell->findChild<QObject*>("lyricsMatchPopup");popup->setProperty("controller",QVariant::fromValue(controller));popup->setProperty("selectedIndex",0);QMetaObject::invokeMethod(popup,"open");state->phase=423;return;
        }
        case 423: {
            capture("hidden");auto* preview=item("lyricMatchPreview");auto* lines=item("lyricMatchPreviewLines");auto* bar=item("lyricMatchPreviewScrollbar");
            state->checks["hidden_bar_reclaims_preview_width"]=!bar->isVisible()&&bar->width()==0&&qAbs(lines->width()-preview->width())<.1;
            state->previewWidth=lines->width();
            const auto point=preview->mapToScene({preview->width()/2,preview->height()/2});movePointer(point);
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-240),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);QCoreApplication::sendEvent(window,&wheel);return;
        }
        case 424:
            state->checks["hidden_preview_still_scrolls"]=item("lyricMatchPreview")->property("contentY").toDouble()>30;
            settings.setValue("ui.showScrollbars",false);return;
        case 425: {
            capture("scrolled");auto* bar=item("lyricMatchPreviewScrollbar");
            state->checks["legacy_setting_cannot_restore_bar_or_gutter"]=!bar->isVisible()&&bar->width()==0&&qAbs(state->previewWidth-item("lyricMatchPreviewLines")->width())<.1;
            state->checks["legacy_setting_keeps_scroll_position"]=item("lyricMatchPreview")->property("contentY").toDouble()>30;
            auto* popup=shell->findChild<QObject*>("lyricsMatchPopup");QMetaObject::invokeMethod(popup,"close");popup->setProperty("controller",QVariant::fromValue(&player));
            settings.setValue("ui.showScrollbars",false);finish();return;
        }
        case 426:
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("settingsOpen",false);shell->setProperty("currentRoute","discover");return;
        case 427:
            capture("restored");state->checks["new_page_keeps_scrollbar_hidden"]=item("discoverScrollbar")&&!item("discoverScrollbar")->isVisible()&&item("discoverScrollbar")->width()==0;
            finish();return;
        case 400:
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("settingsOpen",false);shell->setProperty("playerCollapsed",false);
            shell->setProperty("currentRoute","discover");settings.setValue("appearance.mode","Dark");
            settings.setValue("ui.motionEnabled",true);shell->setProperty("animationsEnabled",true);return;
        case 401: {
            auto* page=item("discoverPage");auto* service=page ? page->property("catalog").value<QObject*>() : nullptr;
            if(!service || service->property("homeBusy").toBool()){--state->phase;return;}
            // Hidden regression windows do not polish positioners until drawn.
            if(++state->flowWait<7){if(state->flowWait==5)capture("layout-warmup");--state->phase;return;}state->flowWait=0;
            const auto rec=service->property("homeRecommendations").toList(),charts=service->property("homeCharts").toList(),daily=service->property("dailyTracks").toList();
            state->checks["home_receives_netease_sections"]=rec.size()==12&&charts.size()>10&&daily.size()>10;
            QList<QQuickItem*> recommendationCards;
            for(auto* child:item("discoverRecommendations")->childItems())
                if(child->objectName()=="discoverRecommendation")recommendationCards.append(child);
            state->checks["recommendations_form_six_columns_two_rows"]=recommendationCards.size()==12
                &&qAbs(recommendationCards[0]->y()-recommendationCards[5]->y())<1
                &&recommendationCards[6]->y()>recommendationCards[0]->height()
                &&qAbs(recommendationCards[6]->y()-recommendationCards[11]->y())<1
                &&qAbs(recommendationCards[0]->x()-recommendationCards[6]->x())<1;
            state->measures["recommended_playlists"]=rec.size();state->measures["charts"]=charts.size();state->measures["daily_tracks"]=daily.size();
            state->measures["charts_y"]=item("discoverChartStage")->y();state->measures["daily_y"]=item("discoverDailySection")->y();state->measures["history_y"]=item("discoverHistorySection")->y();state->measures["scroll_content_height"]=item("discoverScroll")->property("contentHeight").toDouble();
            state->checks["section_order_matches_request"]=item("discoverChartStage")->y()>item("discoverRecommendations")->parentItem()->y()&&item("discoverDailySection")->y()>item("discoverChartStage")->y()&&item("discoverHistorySection")->y()>item("discoverDailySection")->y();
            item("discoverScroll")->setProperty("contentY",0.);capture("home");
            item("discoverScroll")->setProperty("contentY",item("discoverChartStage")->y()-18);
            state->barSize=item("discoverChartStage")->height();click(item("discoverMoreCharts"));
            QTimer::singleShot(90,window,[window,report]{window->grabWindow().save(report+".charts-midpoint.png");});return;
        }
        case 402: {
            auto* page=item("discoverPage");auto* grid=item("discoverChartsGrid");
            if(page->property("chartsProgress").toDouble()<.999&&++state->flowWait<10){--state->phase;return;}state->flowWait=0;
            state->checks["more_slides_catalog_into_same_region"]=page->property("allCharts").toBool()&&page->property("chartsProgress").toDouble()>.99&&qAbs(item("discoverAllCharts")->x())<1&&item("discoverChartPreviews")->x()<-100&&qAbs(item("discoverChartStage")->height()-state->barSize)<.1;
            state->checks["chart_grid_uses_two_rows"]=qAbs(grid->height()/grid->property("cellHeight").toDouble()-2)<.01;
            capture("charts");const auto point=grid->mapToScene({grid->width()/2,grid->height()/2});movePointer(point);
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-240),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);QCoreApplication::sendEvent(window,&wheel);return;
        }
        case 403: {
            state->checks["charts_wheel_browses_horizontally"]=item("discoverChartsGrid")->property("contentX").toDouble()>30;
            click(item("discoverChartsBack"));
            item("discoverScroll")->setProperty("contentY",item("discoverDailySection")->y()-18);
            auto* daily=item("discoverDailyTracks");const auto point=daily->mapToScene({daily->width()/2,80});movePointer(point);
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-240),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);QCoreApplication::sendEvent(window,&wheel);
            return;
        }
        case 404:
            state->checks["daily_tracks_wheel_scrolls_horizontally"]=item("discoverDailyTracks")->property("contentX").toDouble()>30;
            state->checks["back_restores_chart_previews"]=item("discoverPage")->property("chartsProgress").toDouble()<.01;
            capture("daily-history");
            player.search("Taylor Swift");shell->setProperty("currentRoute","discover");return;
        case 405: {
            auto* scroll=item("discoverScroll");scroll->setProperty("contentY",scroll->property("contentHeight").toDouble()-scroll->height());
            auto* pill=item("discoverHistoryPill");state->checks["history_uses_word_capsules"]=pill&&qAbs(pill->height()/2-pill->property("radius").toDouble())<.1;
            capture("history");click(item("discoverClearHistory"));return;
        }
        case 406:
            state->checks["clear_button_clears_history"]=player.searchHistory().isEmpty();
            settings.setValue("appearance.mode","Light");item("discoverScroll")->setProperty("contentY",0.);return;
        case 407:
            capture("light");click(item("discoverRecommendation"));
            QTimer::singleShot(120,window,[window,shell,report,state]{
                const auto progress=shell->property("collectionMorphProgress").toDouble();
                state->checks["recommended_playlist_animates_open"]=shell->property("collectionMorphActive").toBool()&&progress>0&&progress<1;
                window->grabWindow().save(report+".playlist-midpoint.png");
            });return;
        case 408:
            if(shell->property("collectionMorphActive").toBool()&&++state->flowWait<20){--state->phase;return;}state->flowWait=0;
            state->checks["recommended_playlist_reuses_loaded_cover"]=shell->property("collectionMorphSourceItem").value<QQuickItem*>()!=nullptr;
            QMetaObject::invokeMethod(shell,"closeCollection");return;
        case 409:
            if(shell->property("collectionMorphActive").toBool()&&++state->flowWait<20){--state->phase;return;}state->flowWait=0;
            state->checks["recommended_playlist_returns_to_discover"]=shell->property("currentRoute").toString()=="discover"&&qAbs(item("discoverScroll")->property("contentY").toDouble())<1;
            finish();return;
        case 380:
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("settingsOpen",false);shell->setProperty("playerCollapsed",false);
            shell->setProperty("currentRoute","library/albums");settings.setValue("appearance.albumLayout","Grid");settings.setValue("appearance.mode","Light");
            qInfo("MOSAIC_STAGE grid");return;
        case 381:
            if(++state->flowWait<7){--state->phase;return;}
            state->flowWait=0;state->measures["catalog_albums"]=player.albums().size();capture("grid-baseline");
            settings.setValue("appearance.albumLayout","Mosaic");qInfo("MOSAIC_STAGE wall");return;
        case 382: {
            if(++state->flowWait<7){--state->phase;return;}
            state->flowWait=0;auto* wall=item("albumMosaicPage");
            state->checks["mosaic_setting_creates_page"]=wall!=nullptr;
            if(!wall){finish();return;}
            state->checks["wall_fills_entire_window"]=qAbs(wall->width()-shell->property("width").toDouble())<1&&qAbs(wall->height()-shell->property("height").toDouble())<1;
            state->checks["sidebar_remains_translucent"]=item("sidebarSurface")->property("color").value<QColor>().alphaF()>.4&&item("sidebarSurface")->property("color").value<QColor>().alphaF()<.8;
            state->measures["normal_visible_tiles"]=wall->property("visibleTileCount").toInt();
            capture("wall");
            state->previewWidth=wall->property("panX").toDouble();state->barSize=wall->property("panY").toDouble();
            const QPointF start(window->width()*.68,window->height()*.5);
            movePointer(start);
            QMouseEvent press(QEvent::MouseButtonPress,start,start,window->mapToGlobal(start.toPoint()),Qt::LeftButton,Qt::LeftButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&press);
            for(int i=1;i<=8;++i){const QPointF p=start+QPointF(i*16,i*10);QMouseEvent move(QEvent::MouseMove,p,p,window->mapToGlobal(p.toPoint()),Qt::NoButton,Qt::LeftButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&move);}
            const QPointF end=start+QPointF(128,80);QMouseEvent release(QEvent::MouseButtonRelease,end,end,window->mapToGlobal(end.toPoint()),Qt::LeftButton,Qt::NoButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&release);return;
        }
        case 383: {
            auto* wall=item("albumMosaicPage");
            state->checks["drag_pans_both_axes"]=qAbs(wall->property("panX").toDouble()-state->previewWidth)>80&&qAbs(wall->property("panY").toDouble()-state->barSize)>40;
            state->checks["drag_does_not_open_album"]=!item("mosaicAlbumDetail")->isVisible();
            state->barSize=wall->property("panY").toDouble();
            const QPointF point(window->width()*.68,160);movePointer(point);
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-120),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);QCoreApplication::sendEvent(window,&wheel);return;
        }
        case 384: {
            auto* wall=item("albumMosaicPage");
            state->checks["wheel_moves_wall_vertically"]=wall->property("panY").toDouble()>state->barSize+30;
            qInfo("MOSAIC_STAGE selection");
            int best=-1;const auto albums=player.albums();
            for(int i=0;i<albums.size();++i)if(albums[i].toMap().value("title").toString()!="未知专辑"&&!albums[i].toMap().value("artist").toString().isEmpty()&&(best<0||albums[i].toMap().value("count").toInt()>albums[best].toMap().value("count").toInt()))best=i;
            if(best<0){state->checks["catalog_contains_scrollable_album"]=false;finish();return;}
            state->track=albums.value(best).toMap();state->flowPhase=best;
            const QRect pattern[]={{0,0,2,2},{2,0,2,1},{2,1,1,2},{3,1,1,1},{0,2,1,2},{1,2,1,1},{1,3,2,1},{3,2,1,2}};
            const int cx=best/8;const auto p=pattern[best%8];const double x=(cx*4+(cx%2 ? 4-p.x()-p.width():p.x()))*144.;
            wall->setProperty("panX",x+p.width()*72.-(window->width()+shell->property("sidebarWidth").toDouble())/2);
            wall->setProperty("panY",p.y()*144.+p.height()*72.-window->height()*.45);return;
        }
        case 385: {
            QQuickItem* target=nullptr;
            const auto visit=[&](auto&& self,QQuickItem* node)->void {if(!node)return;if(node->objectName()=="albumMosaicTile"&&node->property("albumIndex").toInt()==int(state->flowPhase)){const auto p=node->mapToScene({node->width()/2,node->height()/2});if(p.x()>shell->property("sidebarWidth").toDouble()&&p.x()<window->width()&&p.y()>58&&p.y()<window->height()-110)target=node;}for(auto* child:node->childItems())self(self,child);};
            visit(visit,item("albumMosaicPage"));state->checks["target_album_reachable"]=target!=nullptr;
            state->flow=target;settings.setValue("ui.motionEnabled",true);shell->setProperty("animationsEnabled",true);
            state->checks["animation_tiles_never_overlap"]=true;
            auto* samples=new QTimer(window);samples->setInterval(16);
            QPointer<QQuickItem> wall=item("albumMosaicPage");
            QObject::connect(samples,&QTimer::timeout,window,[wall,state,window,report]{
                if(!wall)return;
                const double progress=wall->property("expansion").toDouble();
                if(progress<=0||progress>=1)return;
                int n=state->measures.value("reflow_animation_samples").toInt();state->measures["reflow_animation_samples"]=n+1;
                if(n==5)window->grabWindow().save(report+".reflow-midpoint.png");
                QList<QRectF> rects;for(auto* tile:wall->childItems())if(tile->objectName()=="albumMosaicTile")rects.append(QRectF(tile->x(),tile->y(),tile->width(),tile->height()));
                for(int i=0;i<rects.size();++i)for(int j=i+1;j<rects.size();++j)if(rects[i].intersects(rects[j]))state->checks["animation_tiles_never_overlap"]=false;
            });
            samples->start();QTimer::singleShot(1000,samples,&QObject::deleteLater);
            click(target);return;
        }
        case 386: {
            auto* detail=item("mosaicAlbumDetail");auto* wall=item("albumMosaicPage");auto* list=item("mosaicAlbumTracks");
            if(wall->property("expansion").toDouble()<.999&&++state->flowWait<10){--state->phase;return;}
            state->flowWait=0;
            state->checks["click_expands_large_square"]=detail->isVisible()&&detail->width()>350&&qAbs(detail->width()-detail->height())<1;
            state->checks["details_stay_inside_original_tile"]=detail->parentItem()==state->flow;
            state->checks["sampled_real_reflow_animation"]=state->measures.value("reflow_animation_samples").toInt()>=4;
            bool movedNeighbor=false;
            for(auto* tile:wall->childItems())if(tile->objectName()=="albumMosaicTile"&&tile!=state->flow)
                movedNeighbor|=qAbs(tile->width()-tile->property("tileWidth").toDouble())>1||qAbs(tile->height()-tile->property("tileHeight").toDouble())>1;
            state->checks["neighbors_reflow_with_expansion"]=movedNeighbor;
            state->checks["album_tracks_are_scrollable"]=list->property("contentHeight").toDouble()>list->height();
            auto* bar=item("mosaicTracksScrollbar");
            state->checks["expanded_tile_has_no_scrollbar_line"]=bar&&!bar->isVisible()&&bar->width()==0;
            bool rowsFillWidth=true;
            for(auto* row:songRows())if(row->parentItem()==list->property("contentItem").value<QQuickItem*>())rowsFillWidth&=qAbs(row->width()-list->width())<.1;
            state->checks["expanded_song_rows_reclaim_scrollbar_gutter"]=rowsFillWidth;
            capture("selected");state->barSize=wall->property("panY").toDouble();
            const auto point=list->mapToScene({list->width()/2,list->height()/2});movePointer(point);
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-240),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);QCoreApplication::sendEvent(window,&wheel);return;
        }
        case 387: {
            auto* wall=item("albumMosaicPage");auto* list=item("mosaicAlbumTracks");
            state->checks["song_wheel_scrolls_only_songs"]=list->property("contentY").toDouble()>30&&qAbs(wall->property("panY").toDouble()-state->barSize)<.1;
            QQuickItem* target=nullptr;for(auto* row:songRows()){const auto p=row->mapToScene({row->width()/2,row->height()/2});if(p.y()>list->mapToScene({0,0}).y()+10&&p.y()<list->mapToScene({0,list->height()}).y()-10)target=row;}
            if(target){const auto p=target->mapToScene({target->width()/2,target->height()/2});for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}){QMouseEvent e(type,p,p,window->mapToGlobal(p.toPoint()),Qt::RightButton,type==QEvent::MouseButtonPress?Qt::RightButton:Qt::NoButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&e);}}return;
        }
        case 388:
            state->checks["song_right_click_opens_shared_menu"]=item("mosaicSongContextMenu")->property("opened").toBool();
            QMetaObject::invokeMethod(item("mosaicSongContextMenu"),"close");qInfo("MOSAIC_STAGE playback");click(item("mosaicPlayAll"));return;
        case 389:
            state->checks["play_all_uses_existing_queue"]=player.queueSongs().size()==state->track.value("count").toInt()&&player.currentTrack().value("album")==state->track.value("title");
            player.stop();QMetaObject::invokeMethod(item("albumMosaicPage"),"closeAlbum");state->flowWait=0;state->previewWidth=0;timer->setInterval(160);qInfo("MOSAIC_STAGE pan");return;
        case 390: {
            auto* wall=item("albumMosaicPage");state->previewWidth=qMax(state->previewWidth,double(wall->property("visibleTileCount").toInt()));
            if(wall->property("expansion").toDouble()>.001){--state->phase;return;}
            bool restored=true;for(auto* tile:wall->childItems())if(tile->objectName()=="albumMosaicTile")restored&=qAbs(tile->width()-tile->property("tileWidth").toDouble())<.1&&qAbs(tile->height()-tile->property("tileHeight").toDouble())<.1;
            state->checks["close_restores_plane_partition"]=restored;
            wall->setProperty("panX",(state->flowWait%2 ? -1 : 1)*state->flowWait*617.);
            wall->setProperty("panY",state->flowWait*337.);
            if(++state->flowWait<45){--state->phase;return;}
            state->measures["peak_tiles_during_45_far_pans"]=state->previewWidth;
            state->checks["wall_items_stay_bounded"]=state->previewWidth<130;
            timer->setInterval(450);window->showFullScreen();qInfo("MOSAIC_STAGE fullscreen");return;
        }
        case 391:
            state->measures["fullscreen_tiles"]=item("albumMosaicPage")->property("visibleTileCount").toInt();
            state->checks["fullscreen_stays_bounded"]=item("albumMosaicPage")->property("visibleTileCount").toInt()<220;
            capture("fullscreen");settings.setValue("appearance.mode","Dark");return;
        case 392:
            capture("dark");window->showNormal();settings.setValue("appearance.albumLayout","Grid");qInfo("MOSAIC_STAGE released");return;
        case 393:
            state->checks["leaving_mosaic_releases_wall"]=item("albumMosaicPage")==nullptr;
            settings.setValue("appearance.albumLayout","Mosaic");return;
        case 394:
            shell->setProperty("pageSearchQuery","__mosaic_no_match__");return;
        case 395:
            state->checks["empty_search_releases_cover_items"]=item("albumMosaicPage")->property("visibleTileCount").toInt()==0;
            capture("empty");shell->setProperty("pageSearchQuery","");finish();return;
        case 360:
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("settingsOpen",false);shell->setProperty("playerCollapsed",false);
            shell->setProperty("currentRoute","library/albums");player.setVolume(.42f);
            if(!player.songs().isEmpty()){player.clearQueue();player.enqueueTrack(player.songs().first().toMap());player.selectQueue(0,false);}
            settings.setValue("appearance.mode","Light");return;
        case 361:
            movePointer(item("floatingVolumeButton")->mapToScene({17,17}));return;
        case 362: {
            auto* capsule=item("floatingVolumeCapsule");auto* button=item("floatingVolumeButton");auto* material=item("floatingVolumeMaterial");
            state->checks["hover_opens_compact_volume"]=qAbs(capsule->height()-144)<.1;
            state->checks["volume_popup_matches_button"]=material->property("tint").value<QColor>()==button->property("surfaceColor").value<QColor>()&&material->property("softShadow").toBool();
            state->checks["volume_number_42"]=item("floatingVolumeValue")->property("text").toString()=="42";
            bool raised=true;for(const auto& name:{"floatingFavoriteButton","floatingModeButton","floatingQueueButton","floatingCollapseButton","floatingPreviousButton","floatingPlayPauseButton","floatingNextButton"})raised&=item(name)->property("raisedSurface").toBool()&&!item(name)->property("transparentSurface").toBool();
            state->checks["buttons_have_raised_surfaces"]=raised;
            capture("light-volume");click(button);return;
        }
        case 363:
            state->checks["single_click_mutes"]=qAbs(player.volume())<.001f&&item("floatingVolumeButton")->property("volumeLevel").toInt()==0;
            movePointer({window->width()/2.,100});return;
        case 364:
            state->checks["click_does_not_pin_volume"]=qAbs(item("floatingVolumeCapsule")->height()-34)<.1;
            click(item("floatingVolumeButton"));return;
        case 365: {
            state->checks["second_click_restores_volume"]=qAbs(player.volume()-.42f)<.005f;
            auto* button=item("floatingVolumeButton");const auto point=button->mapToScene({17,17});movePointer(point);
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,120),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);
            QCoreApplication::sendEvent(window,&wheel);return;
        }
        case 366: {
            state->checks["wheel_over_icon_adjusts_volume"]=qAbs(player.volume()-.46f)<.005f;
            auto* slider=item("floatingVolumeSlider");const auto point=slider->mapToScene({slider->width()/2,slider->height()*.25});
            movePointer(point);QMouseEvent press(QEvent::MouseButtonPress,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,Qt::LeftButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&press);
            state->measures["slider_pressed_at_start"]=slider->property("pressed").toBool();state->measures["volume_after_slider_press"]=player.volume();state->measures["capsule_after_slider_press"]=item("floatingVolumeCapsule")->height();
            const auto outside=slider->mapToScene({slider->width()+36,slider->height()+30});
            QMouseEvent move(QEvent::MouseMove,outside,outside,window->mapToGlobal(outside.toPoint()),Qt::NoButton,Qt::LeftButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&move);return;
        }
        case 367: {
            auto* slider=item("floatingVolumeSlider");state->checks["drag_keeps_volume_open"]=slider->property("pressed").toBool()&&qAbs(item("floatingVolumeCapsule")->height()-144)<.1;
            state->measures["slider_pressed_outside"]=slider->property("pressed").toBool();state->measures["capsule_while_dragging_outside"]=item("floatingVolumeCapsule")->height();
            const auto outside=slider->mapToScene({slider->width()+36,slider->height()+30});
            QMouseEvent release(QEvent::MouseButtonRelease,outside,outside,window->mapToGlobal(outside.toPoint()),Qt::LeftButton,Qt::NoButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&release);
            player.setVolume(.46f);click(item("topThemeButton"));
            movePointer(item("floatingVolumeButton")->mapToScene({17,17}));return;
        }
        case 368:
            state->checks["theme_toggle_updates_button_scheme"]=item("floatingPlayer")->property("darkMode").toBool()&&item("floatingModeButton")->property("surfaceColor").value<QColor>().lightnessF()<.5;
            state->checks["dark_volume_matches_buttons"]=item("floatingVolumeMaterial")->property("tint").value<QColor>()==item("floatingModeButton")->property("surfaceColor").value<QColor>();
            capture("dark-volume");movePointer({window->width()/2.,100});return;
        case 369:
            state->checks["leave_closes_volume"]=qAbs(item("floatingVolumeCapsule")->height()-34)<.1;
            finish();return;
        case 330:
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("settingsOpen",false);
            settings.setValue("appearance.albumLayout","Grid");shell->setProperty("currentRoute","library/albums");return;
        case 331: {
            int index=-1;const auto albums=player.albums();
            for(int i=0;i<albums.size();++i)if(albums[i].toMap().value("artist").toString().contains("Command and Conquer")){index=i;break;}
            state->checks["reported_album_present"]=index>=0;
            if(index<0){finish();return;}
            state->barSize=index;auto* grid=item("libraryAlbumGrid");
            QMetaObject::invokeMethod(grid,"positionViewAtIndex",Q_ARG(int,index),Q_ARG(int,1));return;
        }
        case 332: {
            auto* card=item("libraryAlbumCard"+QString::number(int(state->barSize)));
            auto* art=card?uiItem(card,"artworkTileImage"):nullptr;auto* source=art?uiItem(art,"coverSourceImage"):nullptr;
            ++state->flowWait;
            // A cold library shares one asynchronous cover-request lane. Wait
            // for this image, not a fixed delay that can sample pending work.
            if(state->flowWait<5||(source&&source->property("status").toInt()==2&&state->flowWait<45)){--state->phase;return;}
            if(!art||!source){state->checks["reported_artwork_present"]=false;finish();return;}
            state->checks["reported_artwork_ready"]=!art->property("missingArtwork").toBool();
            state->measures["source"]=source->property("source").toUrl().toString();
            state->measures["image_status"]=source->property("status").toInt();
            state->measures["implicit_width"]=source->implicitWidth();
            state->measures["status_round_"+QString::number(int(state->flowPhase))]=source->property("status").toInt();
            state->measures["width_round_"+QString::number(int(state->flowPhase))]=source->implicitWidth();
            const QImage frame=window->grabWindow();const auto rect=art->mapRectToScene(art->boundingRect());
            int colored=0;const auto ratio=frame.width()/double(window->width());
            for(int y=1;y<10;++y)for(int x=1;x<10;++x){
                const auto c=frame.pixelColor(qRound((rect.left()+rect.width()*x/10)*ratio),qRound((rect.top()+rect.height()*y/10)*ratio));
                if(qMax(c.red(),qMax(c.green(),c.blue()))-qMin(c.red(),qMin(c.green(),c.blue()))>70)++colored;
            }
            state->measures["colored_samples"]=colored;state->checks["reported_cover_pixels_visible"]=colored>12;
            state->checks["reported_cover_after_scroll_"+QString::number(int(state->flowPhase))]=colored>12;
            state->checks["grid_tile_size_round_"+QString::number(int(state->flowPhase))]=qAbs(art->width()-132)<.1;
            state->measures["columns_round_"+QString::number(int(state->flowPhase))]=qRound(item("libraryAlbumGrid")->width()/item("libraryAlbumGrid")->property("cellWidth").toDouble());
            capture("reported-cover-"+QString::number(int(state->flowPhase)));
            if(state->flowPhase++<4){QMetaObject::invokeMethod(item("libraryAlbumGrid"),"positionViewAtEnd");state->phase=334;return;}
            art->setProperty("source",QUrl("image://covers/F%3A%2Fplayer%2Flx-music-desktop-master%2FListenFree-desktop%2Fbuild%2Fcover-grid-ui%2Fmissing-folder%2Fmissing.flac"));state->flowWait=0;return;
        }
        case 333: {
            if(++state->flowWait<3){--state->phase;return;}
            auto* art=uiItem(item("libraryAlbumCard"+QString::number(int(state->barSize))),"artworkTileImage");
            auto* source=uiItem(art,"coverSourceImage");
            state->checks["failed_read_is_recognized_as_missing"]=art->property("missingArtwork").toBool();
            state->measures["missing_image_status"]=source->property("status").toInt();state->measures["missing_implicit_width"]=source->implicitWidth();
            const auto frame=window->grabWindow();const auto rect=art->mapRectToScene(art->boundingRect());const auto ratio=frame.width()/double(window->width());
            const auto top=frame.pixelColor(qRound(rect.center().x()*ratio),qRound((rect.top()+2)*ratio));
            const auto fill=frame.pixelColor(qRound(rect.center().x()*ratio),qRound((rect.top()+9)*ratio));
            state->checks["placeholder_fill_aligns_with_outline"]=top==fill;
            capture("missing-cover");finish();return;
        }
        case 334:
            if(int(state->flowPhase)%2)window->showFullScreen();else{window->showNormal();window->resize(1040,709);}
            return;
        case 335:
            QMetaObject::invokeMethod(item("libraryAlbumGrid"),"positionViewAtIndex",Q_ARG(int,int(state->barSize)),Q_ARG(int,1));state->flowWait=0;state->phase=332;return;
        case 300:
            window->showNormal();window->resize(1040,709);
            shell->setProperty("settingsOpen",false);shell->setProperty("nowPlayingOpen",false);shell->setProperty("sidebarCollapsed",false);
            settings.setValue("appearance.albumLayout","Flow");shell->setProperty("currentRoute","library/albums");return;
        case 301: {
            auto* nav=item("sidebarNav_library_albums");auto* flow=item("libraryAlbumFlow");
            auto* card=item("albumCard"+QString::number(flow->parentItem()->property("selectedAlbumIndex").toInt()));
            state->checks["normal_sidebar_rounded"]=nav->property("radius").toDouble()>0;
            state->previewWidth=card->width();state->barSize=nav->property("radius").toDouble();
            state->measures["normal_album_card"]=card->width();capture("normal-flow");window->showFullScreen();return;
        }
        case 302: {
            auto* nav=item("sidebarNav_library_albums");auto* flow=item("libraryAlbumFlow");
            auto* card=item("albumCard"+QString::number(flow->parentItem()->property("selectedAlbumIndex").toInt()));
            state->checks["fullscreen_sidebar_keeps_radius"]=nav->property("radius").toDouble()>0&&nav->property("radius").toDouble()==state->barSize;
            state->checks["fullscreen_flow_card_keeps_size"]=qAbs(card->width()-state->previewWidth)<.1;
            state->checks["fullscreen_flow_card_fits"]=card->mapToScene({0,card->height()}).y()<item("floatingPlayer")->y();
            state->measures["fullscreen_album_card"]=card->width();state->measures["fullscreen_sidebar_radius"]=nav->property("radius").toDouble();
            capture("fullscreen-flow");shell->setProperty("sidebarCollapsed",true);return;
        }
        case 303:
            state->checks["collapsed_fullscreen_sidebar_rounded"]=item("sidebarNav_library_albums")->property("radius").toDouble()>0;
            capture("collapsed");shell->setProperty("sidebarCollapsed",false);shell->setProperty("currentRoute","library/artists");return;
        case 304: case 305: case 306: {
            const QString name=state->phase==305?"libraryArtistGrid":state->phase==306?"myPlaylistGrid":"onlinePlaylistGrid";
            auto* grid=item(name);const auto bounds=grid->mapRectToScene(grid->boundingRect());
            state->checks[name+"_fills_available_height"]=qAbs(bounds.bottom()-window->height())<1;
            if(name=="libraryArtistGrid")state->checks[name+"_fixed_tiles_more_columns"]=grid->property("tileSize").toInt()==132&&grid->width()/grid->property("cellWidth").toDouble()>5;
            else state->checks[name+"_five_columns"]=qAbs(grid->width()/grid->property("cellWidth").toDouble()-5)<.01;
            state->checks[name+"_within_viewport"]=bounds.left()>=0&&bounds.right()<=window->width();
            if(state->phase==305)shell->setProperty("currentRoute","my-lists");
            else if(state->phase==306)shell->setProperty("currentRoute","playlists");
            else shell->setProperty("settingsOpen",true);
            return;
        }
        case 307:
            state->checks["settings_fills_window"]=qAbs(item("settingsPage")->mapToScene({0,item("settingsPage")->height()}).y()-window->height())<1;
            capture("fullscreen-settings");shell->setProperty("settingsOpen",false);shell->setProperty("currentRoute","library/albums");window->showNormal();window->resize(1040,709);return;
        case 308: {
            auto* flow=item("libraryAlbumFlow");auto* card=item("albumCard"+QString::number(flow->parentItem()->property("selectedAlbumIndex").toInt()));
            state->checks["restore_flow_card_size"]=qAbs(card->width()-state->previewWidth)<.1;
            state->checks["restore_sidebar_radius"]=item("sidebarNav_library_albums")->property("radius").toDouble()==state->barSize;
            capture("restored-flow");
            shell->setProperty("musicEditorTrack",QVariantMap{{"title",QStringLiteral("用于布局验证的较长歌曲标题")},{"artist",QStringLiteral("艺术家")}});
            shell->setProperty("musicEditorOpen",true);return;
        }
        case 309:
            state->previewWidth=item("musicEditorSurface")->width();state->barSize=item("musicEditorSurface")->height();
            window->showFullScreen();return;
        case 310: {
            auto* surface=item("musicEditorSurface");auto* content=item("musicEditorContent");auto* field=item("musicEditorArtist");
            state->checks["editor_adapts_to_fullscreen"]=surface->width()>state->previewWidth*1.1&&surface->height()>state->barSize*1.1;
            state->checks["editor_fits_fullscreen"]=surface->mapToScene({0,0}).x()>=24&&surface->mapToScene({0,surface->height()}).y()<=window->height()-24;
            state->checks["editor_fields_fill_resized_content"]=qAbs(field->mapToScene({field->width(),0}).x()-content->mapToScene({content->width()-16,0}).x())<1;
            capture("fullscreen-editor");shell->setProperty("musicEditorOpen",false);
            settings.setValue("appearance.albumLayout","Grid");shell->setProperty("currentRoute","library/albums");return;
        }
        case 311:
            click(item("libraryAlbumCard0"));return;
        case 312:
            if(shell->property("collectionMorphActive").toBool()){--state->phase;return;}
            state->checks["detail_artwork_adapts"]=item("playlistDetailArtwork")->width()>200;
            state->checks["detail_table_fits"]=item("playlistDetailTracks")->height()>200&&item("playlistDetailTracks")->mapToScene({0,item("playlistDetailTracks")->height()}).y()<window->height();
            capture("fullscreen-detail");QMetaObject::invokeMethod(shell,"closeCollection");return;
        case 313:
            if(shell->property("collectionMorphActive").toBool()){--state->phase;return;}
            settings.setValue("appearance.albumLayout","Flow");window->showNormal();window->resize(1920,800);return;
        case 314: {
            auto* flow=item("libraryAlbumFlow");auto* card=item("albumCard"+QString::number(flow->parentItem()->property("selectedAlbumIndex").toInt()));
            state->checks["ultrawide_flow_fits_height"]=card->mapToScene({0,card->height()}).y()<item("floatingPlayer")->y();
            capture("ultrawide-flow");finish();return;
        }
        case 280:
            window->showNormal();window->resize(1040,709);
            shell->setProperty("settingsOpen",false);shell->setProperty("animationsEnabled",false);
            shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.0);shell->setProperty("coverMorphProgress",1.0);return;
        case 281: case 282: case 283: case 284: case 285: case 286: case 287: {
            const int index=state->phase-282;
            const QString label=QStringList{"default","16-9","16-10","ultrawide","maximized","fullscreen","restored"}[index];
            auto* cover=item("nowPlayingArtwork");auto* play=item("nowPlayingPlayPauseButton");auto* volume=item("nowPlayingVolumeSlider");
            auto* lyrics=item("nowPlayingLyricsPanel");auto* action=item("nowPlayingMediaAction");auto* morph=item("playerMorphArtwork");
            if(!cover||!play||!volume||!lyrics||!action||!morph){state->checks["layout_controls_present"]=false;finish();return;}
            const auto art=cover->mapRectToScene(cover->boundingRect()), buttons=play->mapRectToScene(play->boundingRect());
            const auto bottom=volume->mapToScene({0,volume->height()}).y();
            const auto lyric=lyrics->mapRectToScene(lyrics->boundingRect());
            state->measures[label]=QJsonObject{{"width",window->width()},{"height",window->height()},{"cover",art.width()},{"cover_x",art.x()},{"cover_y",art.y()},{"play_button",buttons.width()},{"volume_bottom",bottom},{"lyrics_x",lyric.x()}};
            state->checks[label+"_square_cover"]=qAbs(art.width()-art.height())<.1;
            state->checks[label+"_controls_fit"]=art.top()>=40&&bottom<window->height()-38&&buttons.bottom()<bottom;
            state->checks[label+"_columns_separated"]=action->mapToScene({action->width(),0}).x()+24<lyric.left()&&lyric.width()>250;
            state->checks[label+"_play_centered"]=qAbs(buttons.center().x()-art.center().x())<6;
            state->checks[label+"_cover_morph_lands"]=qAbs(morph->mapToScene({0,0}).x()-art.x())<.5&&qAbs(morph->mapToScene({0,0}).y()-art.y())<.5&&qAbs(morph->width()-cover->width())<.5;
            if(index==0){state->previewWidth=art.width();state->barSize=buttons.width();window->resize(1600,900);}
            else if(index==1){state->checks["cover_grows_with_viewport"]=art.width()>state->previewWidth*1.2;state->checks["controls_scale_with_viewport"]=buttons.width()>state->barSize*1.12;window->resize(1600,1000);}
            else if(index==2){capture("16-10");window->resize(1920,800);}
            else if(index==3){capture("ultrawide");window->showMaximized();}
            else if(index==4){window->showFullScreen();}
            else if(index==5){capture("fullscreen");window->showNormal();window->resize(1040,709);}
            else {state->checks["restore_preserves_default_layout"]=qAbs(art.width()-state->previewWidth)<.1;capture("restored");finish();}
            return;
        }
        case 261: {
            auto* grid=item("libraryArtistGrid");auto* floating=item("floatingPlayer");
            state->checks["artist_content_reaches_under_glass"]=grid->mapToScene({0,grid->height()}).y()>=floating->mapToScene({0,floating->height()}).y();
            capture("artists");shell->setProperty("currentRoute","my-lists");return;
        }
        case 262: {
            auto* grid=item("myPlaylistGrid");auto* floating=item("floatingPlayer");
            state->checks["my_playlists_reach_under_glass"]=grid->mapToScene({0,grid->height()}).y()>=floating->mapToScene({0,floating->height()}).y();
            capture("my-playlists");shell->setProperty("currentRoute","playlists");return;
        }
        case 263: {
            auto* grid=item("onlinePlaylistGrid");auto* floating=item("floatingPlayer");
            state->checks["online_playlists_reach_under_glass"]=grid->mapToScene({0,grid->height()}).y()>=floating->mapToScene({0,floating->height()}).y();
            capture("online-playlists");finish();return;
        }
        case 250:
            shell->setProperty("currentRoute","library/songs");shell->setProperty("settingsOpen",false);
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("morphProgress",0.0);shell->setProperty("coverMorphProgress",0.0);
            shell->setProperty("playerCollapsed",false);shell->setProperty("animationsEnabled",true);settings.setValue("ui.motionEnabled",true);
            timer->setInterval(60);return;
        case 251:
            capture("island");QMetaObject::invokeMethod(shell,"openNowPlaying");return;
        case 252: {
            auto* cover=item("playerMorphArtwork");auto* surface=item("playerMorphSurface");auto* glass=item("floatingGlassMaterial");
            const auto progress=shell->property("coverMorphProgress").toDouble();
            // A newly loaded page may not have presented its first frame yet.
            if(progress<=0&&shell->property("morphAnimating").toBool()){--state->phase;return;}
            const auto target=item("nowPlayingArtwork")->mapToScene({0,0});
            const auto straight=cover->property("startX").toDouble()+(target.x()-cover->property("startX").toDouble())*progress;
            state->checks["cover_follows_shallow_arc"]=progress>0&&progress<1&&cover->x()-straight>1&&cover->x()-straight<=32;
            state->checks["shell_expands_from_island"]=surface->height()>item("floatingPlayer")->height()&&surface->height()<shell->property("height").toDouble();
            state->checks["shell_keeps_frosted_material"]=surface->property("frosted").toBool()&&!surface->property("opaqueBackdropBase").toBool()&&surface->property("tint")==glass->property("tint")&&surface->property("tintStrength")==glass->property("tintStrength")&&surface->property("backdropBlur")==glass->property("backdropBlur");
            capture("opening");const auto before=shell->property("morphProgress").toDouble();
            QMetaObject::invokeMethod(shell,"closeNowPlaying");
            state->checks["reverse_keeps_current_progress"]=shell->property("morphClosing").toBool()&&qAbs(shell->property("morphProgress").toDouble()-before)<.001;
            return;
        }
        case 253:
            if(shell->property("morphAnimating").toBool()){--state->phase;return;}
            state->checks["reverse_returns_to_island"]=!shell->property("nowPlayingOpen").toBool()&&qAbs(shell->property("coverMorphProgress").toDouble())<.001;
            shell->setProperty("playerCollapsed",true);state->flowWait=0;return;
        case 254:
            if(++state->flowWait<6){--state->phase;return;}
            QMetaObject::invokeMethod(shell,"openNowPlaying");return;
        case 255:
            if(shell->property("morphProgress").toDouble()<=0&&shell->property("morphAnimating").toBool()){--state->phase;return;}
            state->checks["collapsed_island_also_expands"]=item("floatingPlayer")->property("collapsed").toBool()&&item("playerMorphSurface")->height()>62&&shell->property("morphAnimating").toBool();
            capture("collapsed-opening");return;
        case 256: {
            if(shell->property("morphAnimating").toBool()){--state->phase;return;}
            auto* cover=item("playerMorphArtwork");auto* target=item("nowPlayingArtwork");
            state->checks["cover_lands_on_nowplaying_artwork"]=shell->property("nowPlayingOpen").toBool()&&QLineF(cover->mapToScene({0,0}),target->mapToScene({0,0})).length()<1&&qAbs(cover->width()-target->width())<1;
            state->checks["transition_surface_released"]=!item("playerMorphSurface")->isVisible();
            capture("expanded");QMetaObject::invokeMethod(shell,"closeNowPlaying");return;
        }
        case 257:
            if(shell->property("morphAnimating").toBool()){--state->phase;return;}
            state->checks["full_close_returns_cover"]=!shell->property("nowPlayingOpen").toBool()&&qAbs(shell->property("coverMorphProgress").toDouble())<.001;
            shell->setProperty("animationsEnabled",false);
            QMetaObject::invokeMethod(shell,"openNowPlaying");
            state->checks["disabled_motion_opens_immediately"]=!shell->property("morphAnimating").toBool()&&shell->property("nowPlayingOpen").toBool()&&shell->property("morphProgress").toDouble()==1;
            QMetaObject::invokeMethod(shell,"closeNowPlaying");
            state->checks["disabled_motion_closes_immediately"]=!shell->property("morphAnimating").toBool()&&!shell->property("nowPlayingOpen").toBool();
            finish();return;
        case 241:
            state->probe=new UiInputProbe(qobject_cast<QQuickItem*>(shell));state->probe->setSize({40,40});state->probe->setPosition({10,170});state->probe->setZ(200);
            click(item("playlistShareButton"));return;
        case 242: {
            capture("playlist-share");
            const auto point=state->probe->mapToScene({20,20});
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-120),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);
            QCoreApplication::sendEvent(window,&wheel);click(state->probe);return;
        }
        case 243:
            state->checks["playlist_popup_blocks_window_clicks"]=state->probe->presses==0;
            state->checks["playlist_popup_blocks_window_wheel"]=state->probe->wheels==0;
            state->checks["playlist_popup_outside_click_closes_only_popup"]=!item("playlistPage")->property("shareOpen").toBool() && shell->property("currentRoute")=="playlists";
            state->probe->deleteLater();state->probe=nullptr;
            click(item("playlistShareButton"));return;
        case 244: {
            state->checks["playlist_popup_reopens"]=item("playlistPage")->property("shareOpen").toBool();
            state->checks["playlist_popup_empty_link_disabled"]=!item("playlistShareSubmit")->isEnabled();
            auto* field=item("playlistShareLink");click(field);
            QKeyEvent input(QEvent::KeyPress,0,Qt::NoModifier,"https://example.test/playlist");QCoreApplication::sendEvent(window,&input);
            state->checks["playlist_popup_link_accepts_input"]=field->property("text")=="https://example.test/playlist" && item("playlistShareSubmit")->isEnabled();
            auto* tabs=item("playlistShareSources");
            const auto point=tabs->mapToScene({tabs->width()/2,tabs->height()/2});
            for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}) {
                QMouseEvent event(type,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,type==QEvent::MouseButtonPress?Qt::LeftButton:Qt::NoButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&event);
            }
            state->checks["playlist_popup_platform_selectable"]=item("playlistPage")->property("shareSourceIndex").toInt()==2;
            QKeyEvent escape(QEvent::KeyPress,Qt::Key_Escape,Qt::NoModifier);QCoreApplication::sendEvent(window,&escape);return;
        }
        case 245:
            state->checks["playlist_popup_escape_closes"]=!item("playlistPage")->property("shareOpen").toBool();
            state->checks["playlist_popup_controls_do_not_open_underlying_card"]=shell->property("selectedCollectionTitle")==state->npSource && shell->property("currentRoute")=="playlists" && !shell->property("collectionMorphActive").toBool();
            finish();return;
        case 220:
            shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.0);return;
        case 221:
            item("nowPlayingPage")->setProperty("motionSource",QUrl::fromLocalFile("F:/player/lx-music-desktop-master/ListenFree-desktop/build/portable/motion-freeze/red-blue.mp4"));return;
        case 222: {
            auto* movie=window->findChild<QObject*>("dynamicArtworkMediaPlayer");
            if(!movie || !movie->property("hasVideo").toBool()){--state->phase;return;}
            state->checks["dynamic_cover_autoplays_without_button"]=movie->property("playbackState").toInt()==1 && !item("dynamicArtworkToggle");
            state->previewWidth=movie->property("position").toDouble();return;
        }
        case 223: {
            auto* movie=window->findChild<QObject*>("dynamicArtworkMediaPlayer");
            state->checks["dynamic_cover_time_advances"]=movie && movie->property("position").toDouble()!=state->previewWidth;
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("morphProgress",0.0);return;
        }
        case 224:
            state->checks["dynamic_cover_released_on_leave"]=window->findChild<QObject*>("dynamicArtworkMediaPlayer")==nullptr;
            finish();return;
        case 1:
            state->npSource=item("nowPlayingBackground")->property("desiredSource");
            settings.setValue("background.type","Color");settings.setValue("background.color","#d1b7df");
            settings.setValue("background.blur",0);settings.setValue("background.mask",70);return;
        case 2:
            state->checks["nowplaying_background_isolated"]=item("nowPlayingBackground")->property("backgroundType")=="AutoCover"
                &&item("nowPlayingBackground")->property("desiredSource")==state->npSource;
            capture("nowplaying");
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("morphProgress",0.0);
            shell->setProperty("settingsOpen",true);settings.setValue("background.type","Image");
            settings.setValue("background.image","");settings.setValue("background.mask",0);settings.setValue("background.blur",56);return;
        case 3:
            state->checks["default_custom_image"]=!item("globalBackground")->property("desiredSource").toUrl().isEmpty();
            state->checks["blur_is_pixels"]=item("globalBackground")->property("blurRadius").toInt()==56;
            state->checks["mask_zero_is_clear"]=item("globalBackground")->property("mask").toDouble()==0;
            return;
        case 4:
            if(QCoreApplication::arguments().contains("--blur-only")) {
                capture("blur-56");settings.setValue("background.blur",192);state->phase=20;return;
            }
            capture("settings");item("settingsPage")->setProperty("selectedCategory",3);return;
        case 5:
            capture("appearance");settings.setValue("background.type","Color");
            QMetaObject::invokeMethod(item("settingsPage"),"handleAction",Q_ARG(QVariant,"background.chooseColor"));return;
        case 6:
            state->checks["palette_popup_open"]=item("colorPickerPalette")&&item("colorPickerPalette")->isVisible();
            capture("color-palette");click(item("colorPickerTab1"));return;
        case 7:
            state->checks["numeric_tab_open"]=item("colorPickerHex")&&item("colorPickerHex")->isVisible();
            if(auto* field=item("colorPickerHex")){field->setProperty("text","#5796cd");QMetaObject::invokeMethod(field,"editingFinished");}
            return;
        case 8:
            state->checks["hex_live_preview"]=QColor(settings.value("background.color").toString())==QColor("#5796cd");
            capture("color-numeric");
            state->probe=new UiInputProbe(item("settingsPage"));state->probe->setSize({40,40});state->probe->setPosition({10,80});state->probe->setZ(999);
            {
                const auto point=state->probe->mapToScene({20,20});
                QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-120),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);
                QCoreApplication::sendEvent(window,&wheel);click(state->probe);
            }
            settings.setValue("background.type","Image");shell->setProperty("darkMode",true);return;
        case 9:
            state->checks["color_popup_blocks_input"]=state->probe->presses==0&&state->probe->wheels==0&&!shell->findChild<QObject*>("backgroundColorPicker")->property("visible").toBool()&&shell->property("settingsOpen").toBool();
            state->probe->deleteLater();state->probe=nullptr;
            capture("settings-dark");shell->setProperty("darkMode",false);
            settings.setValue("background.type","AutoCover");item("settingsPage")->setProperty("selectedCategory",0);return;
        case 10:return;
        case 11:
            capture("settings-cover");
            QMetaObject::invokeMethod(shell->findChild<QObject*>("lyricsMatchPopup"),"match",Q_ARG(QVariant,(QVariantMap{{"title","Animals"},{"artist","Maroon 5"}})),Q_ARG(QVariant,true));return;
        case 12:
            if(player.lyricMatchBusy()){--state->phase;return;}
            state->checks["lyric_candidates_found"]=!player.lyricCandidates().isEmpty();
            click(item("lyricMatchCandidates"));return;
        case 13:
            if(player.lyricMatchBusy()){--state->phase;return;}
            state->checks["lyric_preview_loaded"]=!player.lyricPreviewLines().isEmpty();
            state->checks["real_feature_badges"]=!player.lyricCandidates().isEmpty()&&player.lyricCandidates().first().toMap().value("features").toStringList().contains("翻译");
            // grabWindow completes the initial layout/render before measuring scrolling.
            capture("lyrics");
            if(auto* body=item("lyricMatchPreviewLines"))state->previewWidth=body->width();
            if(auto* bar=item("lyricMatchPreviewScrollbar"))state->barSize=bar->property("size").toDouble();
            if(auto* preview=item("lyricMatchPreview")) {
                const auto point=preview->mapToScene({preview->width()/2,100});
                QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-1200),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);
                QCoreApplication::sendEvent(window,&wheel);
            }
            return;
        case 14:
            state->checks["preview_width_stable"]=item("lyricMatchPreviewLines")&&qAbs(item("lyricMatchPreviewLines")->width()-state->previewWidth)<.1;
            state->checks["scrollbar_size_stable"]=item("lyricMatchPreviewScrollbar")&&qAbs(item("lyricMatchPreviewScrollbar")->property("size").toDouble()-state->barSize)<.0001;
            state->checks["wheel_scrolls_preview"]=item("lyricMatchPreview")&&item("lyricMatchPreview")->property("contentY").toDouble()>0;
            capture("lyrics-scrolled");
            QMetaObject::invokeMethod(shell->findChild<QObject*>("lyricsMatchPopup"),"close");
            finish();return;
        case 120:
            shell->setProperty("settingsOpen",false);shell->setProperty("nowPlayingOpen",false);shell->setProperty("morphProgress",0.0);
            QMetaObject::invokeMethod(shell->findChild<QObject*>("lyricsMatchPopup"),"match",Q_ARG(QVariant,(QVariantMap{{"title","Animals"},{"artist","Maroon 5"}})),Q_ARG(QVariant,true));return;
        case 121: {
            if(player.lyricMatchBusy()){--state->phase;return;}
            state->checks["source_selector_removed"]=!item("lyricMatchSource");
            state->checks["tag_query_prefilled"]=item("lyricMatchQuery")->property("text")=="Animals Maroon 5";
            QSet<QString> sources;int previous=101,index=-1;bool sorted=true,labels=true;
            for(int i=0;i<player.lyricCandidates().size();++i) {
                const auto row=player.lyricCandidates()[i].toMap();
                sources.insert(row.value("lyricSource").toString());labels&=!row.value("sourceLabel").toString().isEmpty();
                const auto score=row.value("score").toInt();sorted&=score<=previous;previous=score;
                if(index<0&&row.value("lyricSource")=="lrclib")index=i;
            }
            state->measures["sources"]=QJsonArray::fromStringList(sources.values());
            state->measures["result_count"]=player.lyricCandidates().size();
            state->checks["combined_sources"]=sources.size()>=3;
            state->checks["combined_score_order"]=sorted&&!sources.isEmpty();
            state->checks["every_candidate_has_source_label"]=labels;
            if(index<0)index=0;
            shell->findChild<QObject*>("lyricsMatchPopup")->setProperty("selectedIndex",index);
            player.previewLyricMatch(index);return;
        }
        case 122: {
            if(player.lyricMatchBusy()){--state->phase;return;}
            state->checks["combined_candidate_preview_loaded"]=player.lyricPreviewLines().size()>10;
            capture("lyrics-unified");
            auto* preview=item("lyricMatchPreview");
            state->previewWidth=item("lyricMatchPreviewLines")->width();
            state->barSize=item("lyricMatchPreviewScrollbar")->property("size").toDouble();
            const auto point=preview->mapToScene({preview->width()/2,100});
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-360),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);
            QCoreApplication::sendEvent(window,&wheel);return;
        }
        case 123: {
            auto* preview=item("lyricMatchPreview");
            const auto offset=preview->property("contentY").toDouble();
            state->checks["wheel_scrolls_preview"]=offset>0;
            state->checks["preview_width_stable"]=qAbs(item("lyricMatchPreviewLines")->width()-state->previewWidth)<.1;
            state->checks["scrollbar_size_stable"]=qAbs(item("lyricMatchPreviewScrollbar")->property("size").toDouble()-state->barSize)<.0001;
            capture("lyrics-scrolled");
            const auto point=preview->mapToScene({preview->width()/2,100});
            // Real precision-scroll events include both deltas. Qt discards a
            // zero-angle ScrollUpdate following an accepted wheel as a duplicate.
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),QPoint(0,48),QPoint(0,120),Qt::NoButton,Qt::NoModifier,Qt::ScrollUpdate,false);
            QCoreApplication::sendEvent(window,&wheel);state->barSize=offset;
            auto* results=item("lyricMatchCandidates");const auto leftPoint=results->mapToScene({results->width()/2,120});
            QWheelEvent leftWheel(leftPoint,window->mapToGlobal(leftPoint.toPoint()),{},QPoint(0,-360),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);
            QCoreApplication::sendEvent(window,&leftWheel);return;
        }
        case 124:
            state->checks["touchpad_scrolls_preview_back"]=qAbs(item("lyricMatchPreview")->property("contentY").toDouble()-(state->barSize-48))<.1;
            state->checks["wheel_scrolls_candidates"]=item("lyricMatchCandidates")->property("contentY").toDouble()>0;
            QMetaObject::invokeMethod(shell->findChild<QObject*>("lyricsMatchPopup"),"close");
            QMetaObject::invokeMethod(shell->findChild<QObject*>("lyricsMatchPopup"),"match",Q_ARG(QVariant,(QVariantMap{{"localPath","C:/missing/Animals - Maroon 5.mp3"},{"title",""},{"artist",""}})),Q_ARG(QVariant,true));return;
        case 125:
            state->checks["filename_query_fallback"]=item("lyricMatchQuery")->property("text")=="Animals - Maroon 5";
            state->checks["new_search_clears_preview"]=player.lyricPreviewLines().isEmpty();
            QMetaObject::invokeMethod(shell->findChild<QObject*>("lyricsMatchPopup"),"close");return;
        case 126:
            state->checks["close_cancels_all_sources"]=!player.lyricMatchBusy()&&player.lyricCandidates().isEmpty();finish();return;
        case 100: {
            if(player.songs().isEmpty()){state->checks["isolated_fixture"]=false;finish();return;}
            state->track=player.songs().first().toMap();
            const auto path=QDir::fromNativeSeparators(state->track.value("localPath").toString());
            if(!path.contains("/build/metadata-ui/media/")){state->checks["isolated_fixture"]=false;finish();return;}
            state->checks["artist_index_repaired"]=!state->track.value("artist").toString().isEmpty();
            shell->setProperty("darkMode",false);
            state->measures["modified_before"]=QFileInfo(path).lastModified().toMSecsSinceEpoch();
            shell->setProperty("settingsOpen",false);shell->setProperty("nowPlayingOpen",false);shell->setProperty("morphProgress",0.0);
            QMetaObject::invokeMethod(shell,"openMusicEditor",Q_ARG(QVariant,state->track));return;
        }
        case 101:
            capture("editor");
            item("musicEditorTitle")->setProperty("text",QStringLiteral("手工保留的标题"));
            item("musicEditorArtist")->setProperty("text",QStringLiteral("待匹配艺术家"));
            item("musicEditorYear")->setProperty("text","2026");
            click(item("musicEditorMetadataButton"));return;
        case 102:
            state->checks["search_uses_filename"]=item("metadataMatchQuery")&&item("metadataMatchQuery")->property("text").toString()==QFileInfo(state->track.value("localPath").toString()).completeBaseName();
            if(QCoreApplication::arguments().contains("--metadata-query-only")) {
                state->checks["editor_draft_unchanged"]=item("musicEditorTitle")->property("text").toString()=="手工保留的标题";
                capture("filename-query");player.cancelMetadataMatch();finish();return;
            }
            item("metadataMatchQuery")->setProperty("text",QStringLiteral("桃花诺 邓紫棋"));click(item("metadataSearchButton"));return;
        case 103:
            if(player.metadataMatchBusy()){--state->phase;return;}
            state->checks["search_candidates_found"]=!player.metadataCandidates().isEmpty();
            if(player.metadataCandidates().isEmpty()){finish();return;}
            state->tracks=player.metadataCandidates();click(item("metadataMatchCandidates"));return;
        case 104:
            if(player.metadataArtwork().value("busy").toBool()){--state->phase;return;}
            state->checks["cover_preview_loaded"]=!player.metadataArtwork().value("url").toString().isEmpty();
            state->npSource=player.metadataArtwork().value("url");
            capture("preview-light");
            click(item("metadataField_title"));return;
        case 105:
            state->checks["title_can_be_excluded"]=!item("metadataField_title")->property("checked").toBool();
            click(item("metadataFillButton"));return;
        case 106:
            state->checks["cover_filled_into_draft"]=item("musicEditorArtwork")->property("source").toUrl()==state->npSource.toUrl();
            state->checks["fills_artist"]=item("musicEditorArtist")->property("text")==state->tracks.first().toMap().value("artist");
            state->checks["preserves_unchecked_title"]=item("musicEditorTitle")->property("text").toString()=="手工保留的标题";
            state->checks["preserves_other_fields"]=item("musicEditorYear")->property("text").toString()=="2026";
            state->checks["fill_does_not_write_file"]=QFileInfo(state->track.value("localPath").toString()).lastModified().toMSecsSinceEpoch()==state->measures["modified_before"].toInteger();
            capture("filled");shell->setProperty("darkMode",true);click(item("musicEditorMetadataButton"));return;
        case 107:
            item("metadataMatchQuery")->setProperty("text",QStringLiteral("桃花诺 邓紫棋"));click(item("metadataSearchButton"));return;
        case 108:
            if(player.metadataMatchBusy()){--state->phase;return;}
            click(item("metadataMatchCandidates"));return;
        case 109:
            if(player.metadataArtwork().value("busy").toBool()){--state->phase;return;}
            capture("preview-dark");click(item("metadataCancelButton"));return;
        case 110:
            state->checks["cancel_keeps_draft"]=item("musicEditorTitle")->property("text").toString()=="手工保留的标题";
            state->checks["cancel_stops_search"]=!player.metadataMatchBusy()&&player.metadataCandidates().isEmpty();
            click(item("musicEditorSaveButton"));return;
        case 111: {
            const auto tags=player.readTrackTags(state->track);
            state->checks["save_writes_tags"]=tags.value("title").toString()=="手工保留的标题"&&tags.value("artist")==state->tracks.first().toMap().value("artist")&&tags.value("year").toString()=="2026";
            state->checks["saved_list_keeps_artist"]=!player.songs().isEmpty()&&player.songs().first().toMap().value("artist")==tags.value("artist");
            state->checks["editor_closes_on_save"]=!shell->property("musicEditorOpen").toBool();
            TagLib::FileRef file(state->track.value("localPath").toString().toStdWString().c_str(),false);
            QFile imageFile(state->npSource.toUrl().toLocalFile());const auto expected=imageFile.open(QIODevice::ReadOnly)?imageFile.readAll():QByteArray{};
            bool embedded=false;
            for(const auto& picture:file.complexProperties("PICTURE")) {
                const auto bytes=picture["data"].toByteVector();
                if(picture["pictureType"].toString()=="Front Cover" && QByteArray(bytes.data(),int(bytes.size()))==expected)embedded=!expected.isEmpty();
            }
            state->checks["save_embeds_previewed_cover"]=embedded;
            finish();return;
        }
        case 130:
            if(player.albums().size()<3){state->checks["album_fixture"]=false;finish();return;}
            window->resize(1280,800);
            shell->setProperty("settingsOpen",false);shell->setProperty("nowPlayingOpen",false);
            shell->setProperty("currentRoute","library/albums");shell->setProperty("darkMode",false);
            shell->setProperty("animationsEnabled",true);settings.setValue("ui.motionEnabled",true);
            settings.setValue("background.type","AutoCover");settings.setValue("background.mask",0);settings.setValue("background.blur",36);
            player.clearQueue();player.enqueueTrack(player.songs().first().toMap());player.selectQueue(0,false);return;
        case 131:
            state->flow=item("albumCard1");
            if(!state->flow){state->checks["album_source_created"]=false;finish();return;}
            capture("album-before");click(state->flow);
            QTimer::singleShot(150,window,[window,shell,state,report] {
                auto* surface=uiItem(window->contentItem(),"collectionMorphSurface");
                const auto tint=surface?surface->property("tint").value<QColor>():QColor(Qt::yellow);
                state->checks["transition_uses_neutral_shell"]=tint.blueF()>=tint.redF() && tint.alphaF()<1;
                state->checks["primary_stays_visible_during_expand"]=state->flow&&state->flow->isVisible();
                window->grabWindow().save(report+".album-expanding.png");
            });return;
        case 132: {
            if(shell->property("collectionMorphActive").toBool()){--state->phase;return;}
            auto* panel=item("albumDetailSurface");
            state->checks["floating_album_window"]=panel&&panel->x()>=48&&panel->y()>=32&&panel->width()<panel->parentItem()->width()-95&&panel->height()<panel->parentItem()->height()-95;
            state->checks["primary_retained_but_disabled"]=state->flow&&state->flow->isVisible()&&!state->flow->isEnabled();
            capture("album-light");shell->setProperty("darkMode",true);return;
        }
        case 133:
            capture("album-dark");QMetaObject::invokeMethod(shell,"closeCollection");return;
        case 134:
            if(shell->property("collectionMorphActive").toBool()){--state->phase;return;}
            state->checks["album_returns_to_same_card"]=state->flow&&state->flow->isEnabled()&&state->flow->property("active").toBool()&&shell->property("currentRoute")=="library/albums";
            shell->setProperty("currentRoute","library/artists");
            QMetaObject::invokeMethod(shell,"openCollection",Q_ARG(QVariant,"Artist"),Q_ARG(QVariant,"Taylor Swift"),Q_ARG(QVariant,"#329bd3"));return;
        case 135:
            if(player.artistVisual().value("source")!="apple" || !item("artistSignature") || item("artistSignature")->property("status").toInt()!=1 || item("artistHeroArtwork")->property("status").toInt()!=1){--state->phase;return;}
            state->checks["official_taylor_hero"]=player.artistVisual().value("id")=="159260351"&&player.artistVisual().value("heroKind")=="centeredFullscreenBackground";
            state->checks["official_signature_visible"]=item("artistSignature")->isVisible()&&!item("artistNameFallback")->isVisible();
            state->checks["window_16_10"]=qAbs(double(window->width())/window->height()-1.6)<.01;
            capture("artist-expanded");item("artistScroll")->setProperty("contentY",900.0);return;
        case 136:
            state->checks["artist_compact_actions"]=qAbs(item("artistStickyHeader")->height()-64)<1&&item("artistPlayAllButton")->isVisible()&&item("artistOfficialPageButton")->isVisible();
            capture("artist-compact");
            QMetaObject::invokeMethod(shell,"openCollection",Q_ARG(QVariant,"Artist"),Q_ARG(QVariant,"Natalie Taylor"),Q_ARG(QVariant,"#329bd3"));return;
        case 137:
            if(player.artistVisual().value("name")!="Natalie Taylor" || player.artistVisual().value("source")!="apple"){--state->phase;return;}
            state->checks["artist_without_logo_keeps_name"]=item("artistNameFallback")->isVisible()&&!item("artistSignature")->isVisible();
            capture("artist-no-signature");finish();return;
        case 80:
            shell->setProperty("settingsOpen",false);shell->setProperty("nowPlayingOpen",false);
            shell->setProperty("playerCollapsed",false);shell->setProperty("morphProgress",0.0);
            player.setPlaybackMode("listLoop");player.setVolume(.50f);return;
        case 81:
            click(item("floatingModeButton"));return;
        case 82:
            state->checks["mode_single_click"]=player.playbackMode()=="singleLoop";
            click(item("floatingModeButton"));return;
        case 83:
            state->checks["mode_shuffle"]=player.playbackMode()=="shuffle";
            click(item("floatingModeButton"));return;
        case 84:
            state->checks["mode_stop_current"]=player.playbackMode()=="stopAfterCurrent";
            click(item("floatingModeButton"));return;
        case 85: {
            state->checks["mode_wraps_without_sequential"]=player.playbackMode()=="listLoop";
            if(auto* button=item("floatingVolumeButton")) {
                const auto point=button->mapToScene({button->width()/2,button->height()/2});
                QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,120),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);
                QCoreApplication::sendEvent(window,&wheel);
                QMouseEvent move(QEvent::MouseMove,point,point,window->mapToGlobal(point.toPoint()),Qt::NoButton,Qt::NoButton,Qt::NoModifier);QCoreApplication::sendEvent(window,&move);
            }
            return;
        }
        case 86:
            state->checks["volume_icon_wheel"]=qAbs(player.volume()-.54f)<.005f;
            state->checks["volume_number"]=item("floatingVolumeValue")&&item("floatingVolumeValue")->isVisible()&&item("floatingVolumeValue")->property("text").toString()=="54";
            capture("volume");player.setVolume(1.f);return;
        case 87:
            state->checks["volume_number_100"]=item("floatingVolumeValue")->property("text").toString()=="100";
            player.setVolume(0.f);return;
        case 88:
            state->checks["volume_number_0"]=item("floatingVolumeValue")->property("text").toString()=="0";
            player.setVolume(.5f);
            if(player.songs().isEmpty()){state->checks["fixture_track"]=false;finish();return;}
            player.playAll({player.songs().first()});return;
        case 89:
            if(player.state()!="Playing"||player.duration()<10000){--state->phase;return;}
            player.pause();return;
        case 90: {
            auto* bar=item("floatingProgressBar");
            if(!bar){state->checks["progress_present"]=false;finish();return;}
            state->flowPhase=player.position();
            auto point=bar->mapToScene({bar->width()*.25,bar->height()/2});
            QMouseEvent press(QEvent::MouseButtonPress,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,Qt::LeftButton,Qt::NoModifier);
            QCoreApplication::sendEvent(window,&press);
            point=bar->mapToScene({bar->width()*.60,bar->height()/2});
            QMouseEvent move(QEvent::MouseMove,point,point,window->mapToGlobal(point.toPoint()),Qt::NoButton,Qt::LeftButton,Qt::NoModifier);
            QCoreApplication::sendEvent(window,&move);return;
        }
        case 91: {
            auto* bar=item("floatingProgressBar");
            state->checks["seek_drag_previews_without_decoding"]=qAbs(player.position()-state->flowPhase)<250&&qAbs(bar->property("displayValue").toDouble()-.60)<.015;
            const auto point=bar->mapToScene({bar->width()*.60,bar->height()/2});
            QMouseEvent release(QEvent::MouseButtonRelease,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,Qt::NoButton,Qt::NoModifier);
            QCoreApplication::sendEvent(window,&release);return;
        }
        case 92:
            state->checks["seek_release_commits"]=qAbs(player.position()-player.duration()*.60)<1000;
            player.stop();shell->setProperty("settingsOpen",true);
            item("settingsPage")->setProperty("selectedCategory",1);return;
        case 93:
            state->checks["watch_toggle_visible"]=item("settingRow/library.autoWatch")&&item("settingRow/library.autoWatch")->isVisible();
            capture("watch-setting");finish();return;
        case 150:
            window->resize(1040,709);
            shell->setProperty("settingsOpen",false);shell->setProperty("nowPlayingOpen",false);
            shell->setProperty("currentRoute","my-lists");shell->setProperty("darkMode",false);
            shell->setProperty("animationsEnabled",true);settings.setValue("ui.motionEnabled",true);
            settings.setValue("background.type","AutoCover");settings.setValue("background.mask",0);settings.setValue("background.blur",56);
            player.clearQueue();player.enqueueTrack(player.songs().first().toMap());player.selectQueue(0,false);return;
        case 151:
            if(++state->flowWait<3){--state->phase;return;}
            state->checks["default_window_size"]=window->width()==1040&&window->height()==709;
            state->checks["miniplayer_fits_window"]=item("floatingPlayer")->x()+item("floatingPlayer")->width()<=window->width()-12;
            state->checks["reference_sigma_pixels"]=qAbs(item("globalBackground")->property("blurRadius").toDouble()-window->width()*.03)<.1;
            {
                const auto frame=window->grabWindow();
                state->checks["rounded_window_corners"]=frame.pixelColor(0,0).alpha()<10;
                int opaque=0;
                for(int y=frame.height()/20;y<frame.height();y+=frame.height()/10)
                    for(int x=frame.width()/20;x<frame.width();x+=frame.width()/10)
                        opaque+=frame.pixelColor(x,y).alpha()>240;
                state->checks["window_renders_opaque_content"]=opaque>=95;
            }
            state->checks["back_hidden_on_home"]=!item("globalBackButton")->isVisible();
            state->checks["search_compact"]=item("searchSuggestionCapsule")->width()==210&&item("searchSuggestionCapsule")->property("color").value<QColor>().alphaF()<.3;
            state->flow=item("myPlaylistGrid");
            state->checks["five_columns"]=state->flow&&qAbs(state->flow->width()/state->flow->property("cellWidth").toDouble()-5)<.01;
            state->checks["three_and_half_rows"]=state->flow&&qAbs(state->flow->height()/state->flow->property("cellHeight").toDouble()-3.5)<.05;
            capture("playlists-light");
            if(!item("myPlaylistCard3")){state->checks["playlist_fixture"]=false;finish();return;}
            click(item("myPlaylistCard3"));
            QTimer::singleShot(250,window,[window,shell,state,report] {
                state->checks["playlist_hero_in_flight"]=shell->property("collectionMorphActive").toBool();
                state->checks["no_playlist_expanding_shell"]=!uiItem(window->contentItem(),"collectionMorphSurface")->isVisible();
                window->grabWindow().save(report+".playlist-expanding.png");
            });return;
        case 152:
            if(shell->property("collectionMorphActive").toBool()){--state->phase;return;}
            state->npSource=shell->property("backgroundArtwork");
            state->checks["detail_background_uses_cover"]=state->npSource.toUrl()==shell->property("selectedCollectionArtwork").toUrl()&&!state->npSource.toUrl().isEmpty();
            state->checks["detail_back_visible"]=item("globalBackButton")->isVisible();
            capture("playlist-detail");
            player.enqueueTrack(player.songs()[1].toMap());player.selectQueue(1,false);return;
        case 153:
            state->checks["detail_background_survives_track_change"]=shell->property("backgroundArtwork")==state->npSource;
            QMetaObject::invokeMethod(shell,"closeCollection");return;
        case 154:
            if(shell->property("collectionMorphActive").toBool()){--state->phase;return;}
            state->checks["grid_instance_retained"]=state->flow&&state->flow==item("myPlaylistGrid")&&shell->property("currentRoute")=="my-lists";
            state->checks["home_background_returns_to_playing"]=shell->property("backgroundArtwork").toUrl()==player.currentTrack().value("artwork").toUrl();
            click(item("topThemeButton"));return;
        case 155:
            if(++state->flowWait<5){--state->phase;return;}
            capture("playlists-dark");
            state->checks["miniplayer_transparent"]=item("floatingPlayer")->property("backdrop").value<QQuickItem*>()!=nullptr;
            state->checks["theme_button_has_no_selected_ring"]=!item("topThemeButton")->property("selected").toBool()&&shell->property("darkMode").toBool();
            shell->setProperty("currentRoute","library/artists");return;
        case 156: {
            if(++state->flowWait<8){--state->phase;return;}
            capture("artists");
            state->checks["artist_gallery_square"]=item("libraryArtistCard0")&&!item("libraryArtistCard0")->property("portrait").toBool();
            int loaded=0;
            for(int i=0;i<15;++i)if(auto* card=item("libraryArtistCard"+QString::number(i)))
                if(auto* art=uiItem(card,"artworkTileImage"))loaded+=!art->property("missingArtwork").toBool();
            state->measures["loaded_artist_thumbnails"]=loaded;
            state->checks["artist_thumbnails_loaded"]=loaded>=3;
            QMetaObject::invokeMethod(shell,"openNowPlaying");
            QTimer::singleShot(250,window,[window,shell,state,report] {
                const auto page=shell->property("morphProgress").toDouble(), cover=shell->property("coverMorphProgress").toDouble();
                state->measures["nowplaying_page_progress_250ms"]=page;state->measures["nowplaying_cover_progress_250ms"]=cover;
                state->checks["separate_reference_curves"]=page>.2&&page<.8&&cover>page+.1;
                state->checks["one_cover_during_morph"]=uiItem(window->contentItem(),"nowPlayingArtwork")->opacity()==0
                    &&uiItem(window->contentItem(),"floatingArtwork")->opacity()==0;
                window->grabWindow().save(report+".nowplaying-expanding.png");
            });return;
        }
        case 157: {
            if(shell->property("morphAnimating").toBool()){--state->phase;return;}
            auto* info=item("nowPlayingMediaAction");auto* progress=item("nowPlayingProgressBar");
            state->checks["media_action_shifted_right"]=info&&progress&&qAbs(info->mapToScene({info->width(),0}).x()-progress->mapToScene({progress->width()+12,0}).x())<.5;
            capture("nowplaying");QMetaObject::invokeMethod(shell,"closeNowPlaying");return;
        }
        case 158:
            if(shell->property("morphAnimating").toBool()){--state->phase;return;}
            state->checks["nowplaying_returns"]=!shell->property("nowPlayingOpen").toBool();
            settings.setValue("background.autoBlurPx",70);
            state->checks["manual_blur_uses_pixels"]=item("globalBackground")->property("blurRadius").toInt()==70;
            settings.setValue("background.autoBlurPx",window->width()*.03);
            shell->setProperty("currentRoute","library/albums");return;
        case 159:
            click(item("albumCard1"));return;
        case 160: {
            if(shell->property("collectionMorphActive").toBool()){--state->phase;return;}
            capture("album-window");
            auto* album=item("albumDetailSurface");
            state->checks["album_fits_default_window"]=album&&album->mapToScene({0,album->height()}).y()<item("floatingPlayer")->y();
            shell->setProperty("currentRoute","my-lists");state->phase=161;return;
        }
        case 161:
            click(item("createPlaylistButton"));return;
        case 162:
            {
                const auto frame=window->grabWindow();
                state->checks["popup_preserves_window_rounding"]=frame.pixelColor(0,0).alpha()<10
                    &&frame.pixelColor(frame.width()/2,frame.height()/2).alpha()>240;
            }
            capture("playlist-create");
            shell->setProperty("settingsOpen",true);return;
        case 163:
            capture("settings");
            state->checks["settings_feedback"]=item("topSettingsButton")->property("selected").toBool();
            window->showMaximized();return;
        case 164:
            state->checks["maximized_has_square_corners"]=window->property("cornerRadius").toDouble()==0
                &&window->grabWindow().pixelColor(0,0).alpha()>240;
            window->showNormal();return;
        case 165:
            state->checks["restored_has_rounded_corners"]=window->property("cornerRadius").toDouble()==32
                &&window->grabWindow().pixelColor(0,0).alpha()<10;
            finish();return;
        case 180:
            if(player.songs().isEmpty()){state->checks["fixture_available"]=false;finish();return;}
            state->track=player.songs().first().toMap();
            shell->setProperty("settingsOpen",false);shell->setProperty("nowPlayingOpen",false);shell->setProperty("morphProgress",0.0);
            QMetaObject::invokeMethod(shell,"openCollection",Q_ARG(QVariant,"Artist"),Q_ARG(QVariant,state->track.value("artist")),Q_ARG(QVariant,"#6b747d"));return;
        case 181: {
            auto* scroll=item("artistScroll");auto* row=scroll?uiItem(scroll,"songRow"):nullptr;
            if(!row){--state->phase;return;}
            const auto y=row->mapToItem(scroll,0,row->height()/2).y();
            scroll->setProperty("contentY",scroll->property("contentY").toDouble()+y-scroll->height()/2);return;
        }
        case 182: {
            auto* row=uiItem(item("artistScroll"),"songRow");
            if(!row){state->checks["artist_row_present"]=false;finish();return;}
            state->track=mapProperty(row,"track");
            const auto point=row->mapToScene({row->width()/2,row->height()/2});
            for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}) {
                QMouseEvent event(type,point,point,window->mapToGlobal(point.toPoint()),Qt::RightButton,type==QEvent::MouseButtonPress?Qt::RightButton:Qt::NoButton,Qt::NoModifier);
                QCoreApplication::sendEvent(window,&event);
            }return;
        }
        case 183: {
            auto* menu=item("artistSongContextMenu");
            state->checks["artist_right_click_opens_menu"]=menu&&menu->property("opened").toBool();
            if(!state->checks["artist_right_click_opens_menu"].toBool()){capture("missing-menu");finish();return;}
            const auto context=mapProperty(menu,"contextData");
            state->checks["menu_targets_clicked_track"]=!state->track.value("localPath").toString().isEmpty()&&context.value("track").toMap().value("localPath")==state->track.value("localPath");
            auto* tableMenu=uiItem(item("playlistDetailTracks"),"songContextMenu");
            if(tableMenu)tableMenu->setProperty("contextData",context);
            const auto actions=menu->property("actions").value<QJSValue>().toVariant().toList();
            state->checks["same_actions_as_song_table"]=tableMenu&&actions.size()==10&&actions==tableMenu->property("actions").value<QJSValue>().toVariant().toList();
            bool localActions=true;int actionY=6,editY=6;
            for(const auto& value:actions) {
                const auto action=value.toMap();const auto command=action.value("command").toString();
                if(command=="download")localActions&=!action.value("enabled").toBool();
                if(QStringList{"edit_tags","show_in_explorer","delete_from_disk"}.contains(command))localActions&=action.value("enabled").toBool();
                if(command=="edit_tags")editY=actionY;
                actionY+=34+(action.value("separatorBefore").toBool()?7:0);
            }
            state->checks["local_action_availability"]=localActions;
            capture("artist-menu");
            auto* popup=menu->findChild<QObject*>("contextPopup");
            if(!popup){state->checks["popup_present"]=false;finish();return;}
            const QPointF point(popup->property("x").toDouble()+70,popup->property("y").toDouble()+editY+7+17);
            for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}) {
                QMouseEvent event(type,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,type==QEvent::MouseButtonPress?Qt::LeftButton:Qt::NoButton,Qt::NoModifier);
                QCoreApplication::sendEvent(window,&event);
            }return;
        }
        case 184:
            state->checks["edit_action_opens_clicked_track"]=shell->property("musicEditorOpen").toBool()
                &&mapProperty(shell,"musicEditorTrack").value("localPath")==state->track.value("localPath");
            capture("artist-editor");finish();return;
        case 190:
            if(player.songs().isEmpty()){state->checks["fixture_available"]=false;finish();return;}
            player.clearQueue();player.enqueueTrack(player.songs().first().toMap());player.selectQueue(0,false);
            shell->setProperty("settingsOpen",false);shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.0);return;
        case 191:
            item("nowPlayingPage")->setProperty("lyrics",QVariantList{});
            item("nowPlayingPage")->setProperty("motionSource",QUrl("file:///missing-artwork-fixture.mp4"));return;
        case 192: {
            auto* panel=item("nowPlayingLyricsPanel");
            state->checks["empty_lyric_fixture"]=panel&&panel->property("lineCount").toInt()==0;
            state->checks["no_dynamic_artwork_toggle"]=!item("dynamicArtworkToggle");
            const auto point=panel->mapToScene({panel->width()/2,panel->height()/2});
            for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}) {
                QMouseEvent event(type,point,point,window->mapToGlobal(point.toPoint()),Qt::RightButton,type==QEvent::MouseButtonPress?Qt::RightButton:Qt::NoButton,Qt::NoModifier);
                QCoreApplication::sendEvent(window,&event);
            }return;
        }
        case 193:
            state->checks["empty_lyrics_right_click_opens_menu"]=item("nowPlayingLyricsPanel")->property("menuOpen").toBool();
            capture("empty-lyrics-menu");click(item("lyricsContextMatchButton"));return;
        case 194: {
            auto* popup=shell->findChild<QObject*>("lyricsMatchPopup");
            state->checks["empty_lyrics_can_open_matching"]=popup&&popup->property("visible").toBool();
            capture("empty-lyrics-match");player.cancelLyricMatch();finish();return;
        }
        case 20: {
            capture("blur-192");
            auto* effect=uiItem(item("globalBackground"),"artworkBlurEffect");
            state->checks["blur_192_reaches_renderer"]=item("globalBackground")->property("blurRadius").toInt()==192
                &&effect&&effect->property("blurMax").toInt()==64&&effect->property("blurMultiplier").toDouble()==2.0
                &&effect->property("blur").toDouble()==1.0;
            settings.setValue("background.blur",0);return;
        }
        case 21:
            capture("blur-0");
            state->checks["blur_zero_disables_effect"]=!uiItem(item("globalBackground"),"artworkBlurEffect")->isVisible();
            settings.setValue("background.blur",56);finish();return;
        case 30:
            if(player.songs().size()<3){state->checks["three_fixture_tracks"]=false;finish();return;}
            state->tracks=player.songs().mid(0,3);
            settings.setValue("background.type",QCoreApplication::arguments().contains("--sidebar-cover")?"AutoCover":"Image");settings.setValue("background.image","");
            settings.setValue("background.mask",0);settings.setValue("window.transparencyEnabled",false);
            shell->setProperty("settingsOpen",false);shell->setProperty("currentRoute","library/songs");
            shell->setProperty("darkMode",false);shell->setProperty("nowPlayingOpen",false);
            player.setPlaybackMode("stopAfterCurrent");player.clearQueue();
            for(const auto& track:state->tracks)player.enqueueTrack(track.toMap());
            player.selectQueue(0);return;
        case 31:
            if(player.state()!="Playing"){--state->phase;return;}
            state->checks["library_model_marks_playing"]=followsPlayback();
            click(otherRow());return;
        case 32:
            state->checks["single_click_keeps_playing_marker"]=followsPlayback()&&player.currentTrackId()==state->tracks[0].toMap().value("trackId").toString();
            player.pause();
            // Filtering is the real library route from QAbstractItemModel to
            // array delegates; do not replace the table's production bindings.
            shell->setProperty("pageSearchQuery",state->tracks[0].toMap().value("title"));
            return;
        case 33:
            state->checks["array_rows_and_pause_keep_marker"]=player.state()=="Paused"&&followsPlayback()
                &&item("songTableList")&&item("songTableList")->isVisible();
            shell->setProperty("pageSearchQuery","");
            QMetaObject::invokeMethod(item("songTable"),"cycleSort",Q_ARG(QVariant,0));return;
        case 34:
            state->checks["sorting_keeps_track_identity"]=followsPlayback();
            player.selectQueue(1);return;
        case 35:
            if(player.state()!="Playing"){--state->phase;return;}
            state->checks["track_change_moves_marker"]=followsPlayback()&&player.currentTrackId()==state->tracks[1].toMap().value("trackId").toString();
            player.moveQueue(1,0);return;
        case 36:
            state->checks["queue_reorder_keeps_marker"]=followsPlayback()&&player.currentQueueIndex()==0;
            for(auto* row:songRows())if(row->property("current").toBool()) {
                for(auto* owner=row->parentItem();owner;owner=owner->parentItem())if(owner->property("contentY").isValid()) {
                    owner->setProperty("contentY",0.0);break;
                }
            }
            capture("sidebar-light");
            if(auto* surface=item("sidebarSurface"))state->checks["light_sidebar_translucent"]=surface->property("color").value<QColor>().alphaF()>0&&surface->property("color").value<QColor>().alphaF()<.2;
            else state->checks["light_sidebar_translucent"]=false;
            shell->setProperty("darkMode",true);return;
        case 37:
            capture("sidebar-dark");
            if(auto* surface=item("sidebarSurface"))state->checks["dark_sidebar_translucent"]=surface->property("color").value<QColor>().lightnessF()<.3&&surface->property("color").value<QColor>().alphaF()>0&&surface->property("color").value<QColor>().alphaF()<.2;
            else state->checks["dark_sidebar_translucent"]=false;
            shell->setProperty("sidebarCollapsed",true);return;
        case 38:
            state->checks["collapsed_surface_tracks_width"]=item("sidebarSurface")&&qAbs(item("sidebarSurface")->width()-shell->property("sidebarWidth").toDouble())<.1;
            capture("sidebar-collapsed");shell->setProperty("sidebarCollapsed",false);
            shell->setProperty("queueOpen",true);return;
        case 39:
            state->checks["queue_panel_marks_current"]=followsPlayback();
            for(auto* row:songRows())if(row->property("showRemove").toBool()&&!row->property("current").toBool()) {
                QMetaObject::invokeMethod(row,"contextRequested",Q_ARG(qreal,10.0),Q_ARG(qreal,20.0));break;
            }
            state->phase=44;return;
        case 44:
            state->checks["queue_context_does_not_leave_highlight"]=followsPlayback();
            shell->setProperty("queueOpen",false);shell->setProperty("darkMode",false);
            shell->setProperty("selectedCollectionRows",state->tracks);
            shell->setProperty("selectedCollectionTitle","列表状态验证");
            shell->setProperty("currentRoute","detail/album");state->phase=40;return;
        case 40:
            state->checks["album_marks_current"]=followsPlayback();
            shell->setProperty("currentRoute","detail/artist");return;
        case 41:
            state->checks["artist_marks_current"]=followsPlayback();
            if(auto* row=otherRow())QMetaObject::invokeMethod(row,"selectedRequested");
            return;
        case 42:
            state->checks["artist_click_keeps_marker"]=followsPlayback();
            player.clearQueue();return;
        case 43: {
            bool clear=true;for(auto* row:songRows())clear&=!row->property("current").toBool();
            state->checks["empty_queue_clears_markers"]=clear&&!songRows().isEmpty();
            finish();return;
        }
        case 50: {
            const auto args=QCoreApplication::arguments();const auto at=args.indexOf("--flow-track");
            const auto title=at>=0&&at+1<args.size()?args[at+1]:QString("AIZO");
            for(const auto& entry:player.songs())if(entry.toMap().value("title").toString().contains(title,Qt::CaseInsensitive)){state->track=entry.toMap();break;}
            if(state->track.isEmpty()){state->checks["flow_fixture_found"]=false;finish();return;}
            settings.setValue("nowPlaying.backgroundStyle","DynamicFlow");settings.setValue("nowPlaying.backgroundBlur",85);
            settings.setValue("ui.motionEnabled",true);shell->setProperty("animationsEnabled",true);
            player.setPlaybackMode("stopAfterCurrent");player.clearQueue();player.openTrack(state->track);
            shell->setProperty("settingsOpen",false);shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.0);
            return;
        }
        case 51: {
            if(player.state()!="Playing"||++state->flowWait<6){--state->phase;return;}
            const auto visit=[&](auto&& self,QQuickItem* node)->void {
                if(!node||!node->isVisible()||node->opacity()<.5)return;
                if(node->objectName()=="artworkFlowShader")state->flow=node;
                for(auto* child:node->childItems())self(self,child);
            };
            visit(visit,item("nowPlayingBackground"));
            if(!state->flow){--state->phase;return;}
            state->checks["flow_shader_loaded"]=state->flow->property("log").toString().isEmpty();
            state->flowGrab=item("nowPlayingBackground")->grabToImage(QSize(480,270));return;
        }
        case 52: {
            if(!state->flowGrab||state->flowGrab->image().isNull()){--state->phase;return;}
            state->flowFrame=state->flowGrab->image();state->flowFrame.save(report+".texture-0.png");
            double sum=0,squares=0;const auto& frame=state->flowFrame;
            for(int y=0;y<frame.height();++y)for(int x=0;x<frame.width();++x){const auto c=frame.pixelColor(x,y);const double v=.2126*c.red()+.7152*c.green()+.0722*c.blue();sum+=v;squares+=v*v;}
            const double n=frame.width()*frame.height();const double deviation=std::sqrt(std::max(0.0,squares/n-(sum/n)*(sum/n)));
            state->measures["texture_luminance_stddev_255"]=deviation;state->checks["flow_has_spatial_texture"]=deviation>4;
            state->flowWait=0;return;
        }
        case 53:
            if(++state->flowWait<14){--state->phase;return;}
            state->flowGrab=item("nowPlayingBackground")->grabToImage(QSize(480,270));return;
        case 54: {
            if(!state->flowGrab||state->flowGrab->image().isNull()){--state->phase;return;}
            const auto frame=state->flowGrab->image();frame.save(report+".texture-6s.png");double change=0;
            for(int y=0;y<frame.height();++y)for(int x=0;x<frame.width();++x){const auto a=frame.pixelColor(x,y),b=state->flowFrame.pixelColor(x,y);change+=qAbs(a.red()-b.red())+qAbs(a.green()-b.green())+qAbs(a.blue()-b.blue());}
            change/=frame.width()*frame.height()*3.0;
            state->measures["six_second_mean_rgb_change_255"]=change;state->checks["flow_visibly_moves"]=change>.4;
            capture("flow");player.pause();return;
        }
        case 55:state->flowPhase=state->flow->property("flowTime").toDouble();return;
        case 56:
            state->checks["flow_pauses"]=player.state()=="Paused"&&state->flow->property("flowTime").toDouble()==state->flowPhase;
            player.play();return;
        case 57: {
            const double phase=state->flow->property("flowTime").toDouble();
            state->checks["flow_resume_is_continuous"]=phase>state->flowPhase&&phase-state->flowPhase<.06;
            item("nowPlayingBackground")->setVisible(false);state->flowPhase=phase;return;
        }
        case 58:
            state->checks["hidden_flow_stops"]=state->flow->property("flowTime").toDouble()==state->flowPhase;
            item("nowPlayingBackground")->setVisible(true);shell->setProperty("animationsEnabled",false);return;
        case 59:state->flowPhase=state->flow->property("flowTime").toDouble();return;
        case 60:
            state->checks["reduced_motion_stops_flow"]=state->flow->property("flowTime").toDouble()==state->flowPhase;
            finish();return;
        }
    });
    timer->start();
}
