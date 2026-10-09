#pragma once
#include <QLinearGradient>
#include <QPainter>
#include <QTemporaryDir>

// Explicit native-window acceptance probe; requires an isolated --data-dir.
inline void runArtistBlendRegression(QApplication& app,QQuickWindow* window,QObject* shell,
    listenfree::qmlbridge::PortableSession& player,
    listenfree::qmlbridge::SettingsController& settings,const QString& report) {
    struct State { int phase=0,waits=0,round=0; QJsonObject checks,details; QString fallback; QVariantList gridArtists; QTemporaryDir temporary;
        QSet<QString> painted; int blankFrames=0,loadingFrames=0,retries=0,samples=0; double scrollBase=0;
        QString name=QCoreApplication::arguments().contains("--artist-wide") ? "5 Seconds Of Summer" : "Taylor Swift"; };
    auto state=std::make_shared<State>();
    auto* timer=new QTimer(&app);timer->setInterval(500);
    QObject::connect(timer,&QTimer::timeout,&app,[&,window,shell,state,timer,report] {
        const auto item=[&](const QString& name){
            if(name.startsWith("library")) {
                std::function<QQuickItem*(QQuickItem*)> visibleItem=[&](QQuickItem* root)->QQuickItem* {
                    if(root->objectName()==name&&root->isVisible())return root;
                    for(auto* child:root->childItems())if(auto* found=visibleItem(child))return found;
                    return nullptr;
                };
                return visibleItem(window->contentItem());
            }
            return uiItem(window->contentItem(),name);
        };
        const auto capture=[&](const QString& suffix){window->grabWindow().save(report+suffix+".png");};
        auto* background=item("artistBackdrop");auto* page=item("collectionPage");
        switch(state->phase++) {
        case 0: {
            window->setFlag(Qt::WindowTransparentForInput,true);
            window->setFlag(Qt::WindowDoesNotAcceptFocus,true);
            window->show();
            window->resize(QCoreApplication::arguments().contains("--artist-wide") ? 1600 : 1280,800);
            if(QCoreApplication::arguments().contains("--artist-scroll-flicker")) {
                shell->setProperty("currentRoute","library/artists");state->phase=40;return;
            }
            if(QCoreApplication::arguments().contains("--artist-grid-covers-only")) {
                shell->setProperty("currentRoute","library/artists");state->phase=20;return;
            }
            settings.setValue("ui.language","ZhCn");settings.setValue("background.type","Color");settings.setValue("background.color","#ff00ff");
            state->fallback=QFileInfo(report).absolutePath()+"/artist-fallback-fixture.png";
            QImage fallback(1200,800,QImage::Format_RGB32);QPainter painter(&fallback);
            QLinearGradient gradient(0,0,1200,800);gradient.setColorAt(0,QColor("#18566d"));gradient.setColorAt(.55,QColor("#5d9177"));gradient.setColorAt(1,QColor("#bb9366"));
            painter.fillRect(fallback.rect(),gradient);painter.end();fallback.save(state->fallback);
            QVariantList tracks;
            const QStringList albums{"Midnights","folklore","1989 (Taylor's Version)"};
            const QStringList titles{"Lavender Haze","Maroon","Anti-Hero","Snow On The Beach","the 1","cardigan","august","exile","Blank Space","Style","Out Of The Woods","Wildest Dreams"};
            for(int i=0;i<12;++i)tracks.append(QVariantMap{{"trackId",QString::number(i)},{"title",titles[i]},{"artist","Taylor Swift"},{"album",albums[i/4]},
                {"artwork",QUrl::fromLocalFile(state->fallback).toString()},{"localPath",QFileInfo("build/reported-media/sample.mp3").absoluteFilePath()}});
            shell->setProperty("selectedCollectionTitle",state->name);shell->setProperty("selectedCollectionRows",tracks);
            shell->setProperty("selectedCollectionArtwork",QUrl::fromLocalFile(state->fallback));
            if(QCoreApplication::arguments().contains("--artist-local-cover-only")) {
                const auto path=qEnvironmentVariable("LISTENFREE_TEST_ARTIST_TRACK",QFileInfo("build/reported-media/sample.mp3").absoluteFilePath());
                const auto cover="image://covers/"+QString::fromLatin1(QUrl::toPercentEncoding(path));
                auto first=tracks.first().toMap();first["localPath"]=path;first["artwork"]=cover;
                first["title"]="All My People";first["artist"]="Alexandra Stan、Manilla Maniacs";
                first["album"]="CLICHE (HUSH HUSH) – DELUXE EDITION";
                shell->setProperty("selectedCollectionRows",QVariantList{first});
                shell->setProperty("selectedCollectionTitle",first["artist"]);
                shell->setProperty("selectedCollectionArtwork",QUrl(cover));
                state->phase=9;
            }
            shell->setProperty("currentRoute","detail/artist");return;
        }
        case 1:
            if(!page && state->waits++<20){--state->phase;return;}
            if(QCoreApplication::arguments().contains("--artist-black-border-only")) {
                QImage padded(1600,400,QImage::Format_RGB32);padded.fill(Qt::black);
                QPainter painter(&padded);QLinearGradient gradient(480,80,1120,320);
                gradient.setColorAt(0,QColor("#2489a0"));gradient.setColorAt(1,QColor("#bb873f"));
                painter.fillRect(QRect(480,80,640,240),gradient);painter.end();
                state->fallback=QFileInfo(report).absolutePath()+"/artist-black-border-fixture.png";padded.save(state->fallback);
                if(background)background->setProperty("artwork",QUrl::fromLocalFile(state->fallback));
                state->waits=0;state->phase=30;return;
            }
            if(QCoreApplication::arguments().contains("--artist-missing-only")) {
                auto rows=shell->property("selectedCollectionRows").toList();
                for(auto& value:rows){auto row=value.toMap();row["artwork"]="";row["localPath"]="artist-regression-missing.mp3";value=row;}
                shell->setProperty("selectedCollectionRows",rows);
                shell->setProperty("selectedCollectionTitle","Aaron Smith、Luvli");
                shell->setProperty("selectedCollectionArtwork",QUrl("image://covers/artist-regression-missing.mp3"));
                state->phase=8;state->waits=0;return;
            }
            if((!background || !background->property("imageReady").toBool() || !item("artistPlayButton") || !item("artistAlbumSurface")) && state->waits++<20){--state->phase;return;}
            state->checks["fallback_ready"]=background && background->property("imageReady").toBool();
            state->checks["artist_ignores_global_fixed_color"]=item("globalBackground") && !item("globalBackground")->isVisible();
            state->checks["page_reaches_window_top"]=page && qAbs(page->mapToScene(QPointF{}).y())<1;
            state->checks["obsolete_buttons_removed"]=!item("artistBackButton")&&!item("artistOfficialPageButton")&&!item("artistPlayAllButton");
            state->checks["vector_play_button"]=item("artistPlayButton") && item("artistPlayButton")->property("kind")=="play";
            state->checks["album_inset"]=item("artistAlbumSurface") && item("artistAlbumSurface")->x()==28;
            state->checks["sidebar_has_no_flat_panel"]=item("sidebarSurface") && item("sidebarSurface")->property("color").value<QColor>().alpha()==0;
            capture("-fallback");state->waits=0;player.requestArtistVisual(state->name);return;
        case 2: {
            const auto visual=player.artistVisual();
            const bool ready=background && background->property("imageReady").toBool() && !visual.value("hero").toString().isEmpty()
                && background->property("displayedArtwork").toUrl()==QUrl(visual.value("hero").toString());
            if(!ready && state->waits++<90){--state->phase;return;}
            state->checks["late_match_updates_entire_canvas"]=ready;
            state->details["decodedAspect"]=background ? background->property("displayedAspect").toDouble() : 0;
            state->checks["original_image_aspect_preserved"]=background && page && qAbs(page->width()/page->property("artistExpandedHeight").toDouble()-background->property("displayedAspect").toDouble())<.001;
            state->details["provider"]=visual.value("source").toString();state->details["heroKind"]=visual.value("heroKind").toString();
            state->details["heroUrl"]=visual.value("hero").toString();
            state->details["artistId"]=visual.value("id").toString();return;
        }
        case 3:
            capture("-expanded");
            if(auto* button=item("artistPlayButton")) {
                const auto position=button->mapToScene({button->width()/2,button->height()/2});
                for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}) {
                    QMouseEvent event(type,position,position,window->mapToGlobal(position.toPoint()),Qt::LeftButton,
                        type==QEvent::MouseButtonPress?Qt::LeftButton:Qt::NoButton,Qt::NoModifier);
                    QCoreApplication::sendEvent(window,&event);
                }
            }
            state->checks["play_button_reaches_player"]=!player.queueSongs().isEmpty();player.stop();
            if(auto* button=item("topSettingsButton")) {
                const auto position=button->mapToScene({button->width()/2,button->height()/2});
                if(auto* traffic=item("topTrafficCluster")) {
                    const double delta=position.y()-traffic->mapToScene({traffic->width()/2,traffic->height()/2}).y();
                    state->details["toolbarCenterDelta"]=delta;
                    state->checks["toolbar_controls_centered_with_window_dots"]=qAbs(delta)<.1;
                }
                QMouseEvent event(QEvent::MouseMove,position,position,window->mapToGlobal(position.toPoint()),
                    Qt::NoButton,Qt::NoButton,Qt::NoModifier);
                QCoreApplication::sendEvent(window,&event);
            }
            return;
        case 4:
            capture("-toolbar-hover");
            if(auto* scroll=item("artistScroll"))scroll->setProperty("contentY",420);
            return;
        case 5:
            state->checks["scroll_drives_background_blend"]=background && background->property("collapse").toDouble()>.5;
            state->checks["sticky_actions_below_toolbar"]=item("artistPlayButton") && item("artistPlayButton")->mapToScene(QPointF{}).y()>=58;
            capture("-scrolled");window->resize(1000,720);shell->setProperty("sidebarCollapsed",true);return;
        case 6:
            state->checks["collapsed_sidebar_updates_projection"]=background && background->property("sidebarWidth").toInt()==76;
            capture("-compact");window->resize(1280,800);shell->setProperty("sidebarCollapsed",false);
            if(auto* scroll=item("artistScroll"))scroll->setProperty("contentY",-page->property("artistExpandedHeight").toDouble());
            if(background)background->setProperty("artwork",QUrl::fromLocalFile(state->fallback+".missing"));
            state->waits=0;return;
        case 7:
            if(background && background->property("displayedArtwork").toUrl()!=QUrl::fromLocalFile(state->fallback) && state->waits++<15){--state->phase;return;}
            state->checks["failed_image_returns_to_fallback"]=background && background->property("imageReady").toBool()
                && background->property("displayedArtwork").toUrl()==QUrl::fromLocalFile(state->fallback);
            // Real cover-provider failure: it returns a transparent 1x1 sentinel,
            // which must not become a square hero hiding all content below it.
            shell->setProperty("selectedCollectionTitle","Aaron Smith、Luvli");
            {
                auto rows=shell->property("selectedCollectionRows").toList();
                for(auto& value:rows){auto row=value.toMap();row["artwork"]="";row["localPath"]="artist-regression-missing.mp3";value=row;}
                shell->setProperty("selectedCollectionRows",rows);
            }
            shell->setProperty("selectedCollectionArtwork",QUrl("image://covers/artist-regression-missing.mp3"));
            if(background)background->setProperty("artwork",QUrl{});
            state->waits=0;return;
        case 8:
            if(state->waits++<3){--state->phase;return;}
            state->checks["missing_artwork_shows_default_cover"]=item("artistDefaultCover") && item("artistDefaultCover")->isVisible();
            state->checks["missing_artwork_keeps_content_in_view"]=item("artistPlayButton") && item("artistAlbumSurface")
                && item("artistPlayButton")->mapToScene(QPointF{}).y()<window->height()-120
                && item("artistAlbumSurface")->mapToScene(QPointF{}).y()<window->height()-160;
            state->details["missingArtworkHeroHeight"]=page ? page->property("artistExpandedHeight").toDouble() : 0;
            state->details["detailPagePresent"]=page!=nullptr;
            state->details["windowExposed"]=window->isExposed();
            capture("-missing");
            shell->setProperty("currentRoute","library/artists");state->phase=99;return;
        case 9:
            if(state->waits++<8){--state->phase;return;}
            state->checks["first_song_cover_decodes_for_background"]=background && background->property("imageReady").toBool();
            state->checks["fallback_cover_uses_song_art"]=item("artistDefaultCover") && item("artistDefaultCover")->isVisible()
                && !item("artistDefaultCover")->property("missingArtwork").toBool();
            state->checks["song_cover_blurred_background_ready"]=item("artistSongCoverBackground") && item("artistSongCoverBackground")->property("visualReady").toBool();
            state->checks["song_cover_keeps_compact_header"]=page && page->property("artistExpandedHeight").toDouble()<=320;
            capture("-song-cover");shell->setProperty("currentRoute","library/artists");state->phase=99;return;
        case 20: {
            auto* library=item("libraryArtistGrid")?item("libraryArtistGrid")->parentItem():nullptr;
            if(!library || !player.ready()){state->phase=20;return;}
            const QStringList names{"Rag'N'Bone Man","Reynard Silva","Richard Clayderman","The Kid LAROI"};
            CoverImageProvider provider;
            for(const auto& value:player.artists()) {
                const auto row=value.toMap();if(!names.contains(row.value("name").toString())&&!row.value("name").toString().startsWith("The Kid LAROI"))continue;
                const auto url=row.value("artwork").toString();
                const auto decoded=provider.requestImage(url.mid(15),nullptr,QSize(320,320));
                const auto key=QString::number(state->gridArtists.size());
                state->details["artist_"+key]=row.value("name").toString();
                state->details["source_"+key]=url;
                state->details["decode_width_"+key]=decoded.width();
                decoded.save(report+"-decoded-"+key+".png");
                state->gridArtists.append(row);
            }
            state->checks["reported_artists_found"]=state->gridArtists.size()>=4;
            QVariantList repeated;for(int i=0;i<30;++i)repeated.append(state->gridArtists);
            library->setProperty("catalog",QVariantMap{{"artists",repeated}});
            QMetaObject::invokeMethod(item("libraryArtistGrid"),"positionViewAtBeginning");state->waits=0;return;
        }
        case 21: {
            if(state->waits++<5){--state->phase;return;}
            const QImage frame=window->grabWindow();const double ratio=double(frame.width())/window->width();
            for(int i=0;i<state->gridArtists.size();++i) {
                auto* art=uiItem(item("libraryArtistCard"+QString::number(i)),"artworkTileImage");
                auto* source=art?uiItem(art,"coverSourceImage"):nullptr;
                const auto key=QString::number(state->round)+"_"+QString::number(i);
                state->details["status_"+key]=source?source->property("status").toInt():-1;
                state->details["displayed_source_"+key]=source?source->property("source").toUrl().toString():QString{};
                state->details["missing_"+key]=!art||art->property("missingArtwork").toBool();
                int lo=255,hi=0;
                if(art)for(int y=2;y<9;++y)for(int x=2;x<9;++x){
                    const auto p=art->mapToScene({art->width()*x/10,art->height()*y/10});
                    const auto c=frame.pixelColor(qRound(p.x()*ratio),qRound(p.y()*ratio));
                    lo=qMin(lo,qGray(c.rgb()));hi=qMax(hi,qGray(c.rgb()));
                }
                state->details["pixel_range_"+key]=hi-lo;
                state->checks["cover_drawn_"+key]=source&&source->property("status").toInt()==1&&hi-lo>30;
            }
            capture("-grid-"+QString::number(state->round));
            if(++state->round>=3){
                auto* art=uiItem(item("libraryArtistCard0"),"artworkTileImage");
                if(art)art->setProperty("source",QUrl("image://covers/"+QString::fromLatin1(QUrl::toPercentEncoding(state->temporary.filePath("recovering.mp3")))));
                state->phase=24;return;
            }
            QMetaObject::invokeMethod(item("libraryArtistGrid"),"positionViewAtEnd");return;
        }
        case 22:
            QMetaObject::invokeMethod(item("libraryArtistGrid"),"positionViewAtBeginning");state->waits=0;state->phase=21;return;
        case 24: {
            auto* art=uiItem(item("libraryArtistCard0"),"artworkTileImage");
            state->checks["temporary_read_failure_shows_placeholder"]=art&&art->property("missingArtwork").toBool();
            state->checks["recovered_fixture_created"]=QFile::copy(QFileInfo("build/reported-media/sample.mp3").absoluteFilePath(),state->temporary.filePath("recovering.mp3"));
            state->waits=0;return;
        }
        case 25: {
            if(state->waits++<6){--state->phase;return;}
            auto* art=uiItem(item("libraryArtistCard0"),"artworkTileImage");
            state->checks["transient_missing_cover_recovers_without_navigation"]=art&&!art->property("missingArtwork").toBool();
            capture("-recovered");state->phase=99;return;
        }
        case 30: {
            if(state->waits++<6){--state->phase;return;}
            const auto frame=window->grabWindow();
            const auto c=frame.pixelColor(frame.width()*99/100,frame.height()*3/4);
            state->details["extension_color"]=c.name();
            state->checks["black_padding_does_not_blacken_extension"]=qMax(c.red(),qMax(c.green(),c.blue()))>45 && qMax(c.red(),qMax(c.green(),c.blue()))-qMin(c.red(),qMin(c.green(),c.blue()))>15;
            state->checks["padded_hero_original_aspect"]=background&&qAbs(background->property("displayedAspect").toDouble()-4)<.01
                &&page&&qAbs(page->width()/page->property("artistExpandedHeight").toDouble()-4)<.01;
            capture("-padded");
            QImage black(800,400,QImage::Format_RGB32);black.fill(Qt::black);
            state->fallback=QFileInfo(report).absolutePath()+"/artist-black-fixture.png";black.save(state->fallback);
            if(background)background->setProperty("artwork",QUrl::fromLocalFile(state->fallback));
            state->waits=0;return;
        }
        case 31: {
            if(state->waits++<5){--state->phase;return;}
            const auto frame=window->grabWindow();const auto c=frame.pixelColor(frame.width()*99/100,frame.height()*3/4);
            state->checks["truly_black_art_stays_neutral"]=qMax(c.red(),qMax(c.green(),c.blue()))<10;
            capture("-black");shell->setProperty("currentRoute","library/artists");state->phase=99;return;
        }
        case 40: {
            auto* grid=item("libraryArtistGrid");
            if(!grid||!player.ready()){--state->phase;return;}
            QMetaObject::invokeMethod(grid,"positionViewAtIndex",Q_ARG(int,180),Q_ARG(int,1));
            state->waits=0;return;
        }
        case 41:
            if(state->waits++<5){--state->phase;return;}
            state->scrollBase=item("libraryArtistGrid")->property("contentY").toDouble();
            timer->setInterval(16);state->waits=0;return;
        case 42: {
            auto* grid=item("libraryArtistGrid");
            const auto frame=window->grabWindow();const double ratio=double(frame.width())/window->width();
            const auto viewRect=grid->mapRectToScene(grid->boundingRect());
            std::function<void(QQuickItem*)> inspect=[&](QQuickItem* root) {
                if(root->objectName()=="artworkTileImage"&&root->isVisible()) {
                    const auto rect=root->mapRectToScene(root->boundingRect());
                    if(!viewRect.contains(rect)||rect.bottom()>window->height()-110)return;
                    auto* source=uiItem(root,"coverSourceImage");if(!source)return;
                    const auto url=source->property("source").toUrl().toString();
                    int lo=255,hi=0;
                    for(int y=2;y<9;++y)for(int x=2;x<9;++x){
                        const auto c=frame.pixelColor(qRound((rect.left()+rect.width()*x/10)*ratio),qRound((rect.top()+rect.height()*y/10)*ratio));
                        lo=qMin(lo,qGray(c.rgb()));hi=qMax(hi,qGray(c.rgb()));
                    }
                    const bool ready=!root->property("missingArtwork").toBool();
                    if(state->painted.contains(url)) {
                        ++state->samples;
                        if(!ready)++state->loadingFrames;
                        else if(hi-lo<12){
                            if(state->blankFrames++==0){capture("-first-blank");state->details["blankSource"]=url;}
                        }
                        if(root->property("recoveryAttempt").toInt()>0)++state->retries;
                    }
                    if(ready&&hi-lo>60)state->painted.insert(url);
                }
                for(auto* child:root->childItems())inspect(child);
            };inspect(grid);
            grid->setProperty("contentY",state->scrollBase+500*std::sin(state->waits*.10));
            if(++state->waits<180){--state->phase;return;}
            state->details["painted_samples"]=state->samples;
            state->details["ready_but_blank"]=state->blankFrames;
            state->details["previously_painted_loading"]=state->loadingFrames;
            state->details["previously_painted_retrying"]=state->retries;
            state->checks["loaded_covers_do_not_flash_blank"]=state->samples>500&&state->blankFrames==0;
            state->checks["loaded_covers_do_not_retry"]=state->retries==0;
            state->checks["loaded_covers_do_not_reenter_loading"]=state->loadingFrames==0;
            state->phase=99;return;
        }
        default:
            state->checks["leaving_artist_restores_background"]=!item("artistBackdrop") && item("globalBackground") && item("globalBackground")->isVisible();
            QFile file(report);if(file.open(QIODevice::WriteOnly))file.write(QJsonDocument(QJsonObject{{"checks",state->checks},{"details",state->details}}).toJson());
            timer->stop();app.quit();return;
        }
    });
    timer->start();
}
