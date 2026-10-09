#include "qmlbridge/collection_service.h"
#include "app/shortcut_service.h"
#include <windows.h>
#include <QJSValue>
#pragma once
#include "qmlbridge/portable_session.h"
#include <QApplication>
#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMouseEvent>
#include <QWheelEvent>
#include <QKeyEvent>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <memory>

class UiInputProbe : public QQuickItem {
public:
    explicit UiInputProbe(QQuickItem* parent):QQuickItem(parent){setAcceptedMouseButtons(Qt::AllButtons);setAcceptHoverEvents(true);}
    int presses=0, wheels=0;
protected:
    void mousePressEvent(QMouseEvent* e) override { ++presses; e->accept(); }
    void mouseReleaseEvent(QMouseEvent* e) override { e->accept(); }
    void wheelEvent(QWheelEvent* e) override { ++wheels; e->accept(); }
};
inline QQuickItem* uiItem(QQuickItem* root, const QString& name) {
    if (root->objectName() == name) return root;
    for (auto* child : root->childItems()) if (auto* found = uiItem(child, name)) return found;
    return nullptr;
}
inline QQuickItem* uiSongRowForPath(QQuickItem* root, const QString& path) {
    if (!root) return nullptr;
    if (root->objectName() == "songRow") {
        const auto value = root->property("track");
        const auto track = value.canConvert<QJSValue>() ? value.value<QJSValue>().toVariant().toMap() : value.toMap();
        if (track.value("localPath").toString() == path) return root;
    }
    for (auto* child : root->childItems()) if (auto* found = uiSongRowForPath(child, path)) return found;
    return nullptr;
}
inline void uiCollectLibraryPages(QQuickItem* root, QList<QQuickItem*>& pages) {
    if (!root) return;
    if (root->objectName() == QStringLiteral("libraryPage")) pages.append(root);
    for (auto* child : root->childItems()) uiCollectLibraryPages(child, pages);
}
inline qsizetype uiQmlListSize(const QVariant& value) {
    return value.canConvert<QJSValue>() ? value.value<QJSValue>().toVariant().toList().size()
                                        : value.toList().size();
}
inline void runUiRegression(QApplication& app, QQuickWindow* window, QObject* shell,
                            listenfree::qmlbridge::PortableSession& player, listenfree::qmlbridge::SettingsController& settings, listenfree::qmlbridge::CollectionService& collections, listenfree::qmlbridge::SourceController& sources, const QString& report) {
    struct State { int phase=0, ticks=0, detailWait=0, themeWait=0; QString listId; qsizetype count=0; double flowTime=0; QImage background; QJsonObject checks, measures; QPointer<QQuickItem> pressed; QPointer<UiInputProbe> probe; qint64 pausedPosition=0; QPointF point; QVariantMap song; QVariantList fixtureRows; };
    auto state=std::make_shared<State>();
    if (app.arguments().contains("--check-next")) state->phase=-3;
    if (app.arguments().contains("--check-shortcuts")) state->phase=100;
    if (app.arguments().contains("--check-collection-scroll-theme")) state->phase=200;
    if (app.arguments().contains("--check-play-action")) state->phase=300;
    if (app.arguments().contains("--check-library-sections")) state->phase=400;
    auto* timer=new QTimer(&app); timer->setInterval(350);
    const auto item=[window](const QString& name) { return uiItem(window->contentItem(), name); };
    const auto mouse=[window](QEvent::Type type, QPointF point, Qt::MouseButton button, Qt::MouseButtons buttons) {
        QMouseEvent event(type,point,point,window->mapToGlobal(point.toPoint()),button,buttons,Qt::NoModifier);
        static ulong timestamp=1; event.setTimestamp(timestamp+=20); QCoreApplication::sendEvent(window,&event);
    };
    const auto click=[mouse](QPointF point) { mouse(QEvent::MouseButtonPress,point,Qt::LeftButton,Qt::LeftButton); mouse(QEvent::MouseButtonRelease,point,Qt::LeftButton,Qt::NoButton); };
    QObject::connect(timer,&QTimer::timeout,&app,[&,state,timer,item,mouse,click,report,window,shell] {
        state->measures["phase"]=state->phase;
        { QFile progress(report); if(progress.open(QIODevice::WriteOnly)) { auto data=state->checks; data["measurements"]=state->measures; progress.write(QJsonDocument(data).toJson()); } }
        if (++state->ticks>400) { app.exit(8); return; }
        switch(state->phase++) {
        case 400: {
            if (!player.ready() && ++state->count<200) { --state->phase; return; }
            state->checks["library_catalog_ready"]=player.ready();
            if (!player.ready()) { state->phase=405; return; }
            state->measures["expected_songs"]=player.songs().size();
            state->measures["expected_albums"]=player.albums().size();
            state->measures["expected_artists"]=player.artists().size();
            state->checks["library_backend_song_model_matches_catalog"]=
                player.tracksModel()->rowCount()==player.songs().size();
            window->resize(1040,709);window->show();
            settings.setValue("ui.animations",false);
            shell->setProperty("settingsOpen",false);
            shell->setProperty("nowPlayingOpen",false);
            shell->setProperty("albumLayoutMode",QStringLiteral("Flow"));
            shell->setProperty("navigationFilters",QVariantMap{});
            shell->setProperty("pageSearchQuery",QString{});
            shell->setProperty("currentRoute",QStringLiteral("library/songs"));
            state->count=0;
            return;
        }
        case 401: case 402: case 403: case 404: {
            const int currentPhase=state->phase-1;
            const auto route=currentPhase==402 ? QStringLiteral("library/albums")
                            : currentPhase==403 ? QStringLiteral("library/artists")
                                                : QStringLiteral("library/songs");
            const auto section=route.section('/',1);
            const auto sectionProperty=section.toUtf8();
            auto* cache=item("navigationStateCache");
            QList<QQuickItem*> pages;
            uiCollectLibraryPages(window->contentItem(),pages);
            QQuickItem* active=nullptr;
            int visibleCount=0, cachedCount=0;
            bool cachedCollectionsEmpty=true;
            for (auto* page:pages) {
                bool visible=true;
                for (auto* ancestor=page;ancestor;ancestor=ancestor->parentItem())
                    visible &= ancestor->isVisible();
                if (visible) { ++visibleCount; active=page; }
                else {
                    ++cachedCount;
                    cachedCollectionsEmpty &= uiQmlListSize(page->property("albums"))==0
                        && uiQmlListSize(page->property("artists"))==0;
                }
            }
            const bool displayed=cache && cache->property("displayedRoute").toString()==route;
            const bool routeReady=displayed && active && visibleCount==1
                && active->property("routeKey").toString()==route
                && active->property("section").toString()==section;
            if ((!routeReady || (currentPhase!=401 && cachedCount<1)) && ++state->count<40) {
                --state->phase;return;
            }
            const auto name=currentPhase==404 ? QStringLiteral("songs_return") : section;
            state->checks[name+"_route_visible"]=routeReady;
            state->checks[name+"_cached_collections_empty"]=cachedCollectionsEmpty;
            if (currentPhase!=401) state->checks[name+"_has_cached_page"]=cachedCount>=1;
            state->measures[name+"_cached_pages"]=cachedCount;
            if (section==QStringLiteral("songs")) {
                const auto modelValue=active ? active->property("displayTracksModel") : QVariant{};
                auto* model=modelValue.value<QObject*>();
                if (!model && modelValue.canConvert<QJSValue>()) model=modelValue.value<QJSValue>().toQObject();
                state->checks[name+"_uses_backend_model"]=active && active->property("usingTracksModel").toBool()
                    && model && uiQmlListSize(active->property("songs"))==0;
                state->checks[name+"_count_matches_catalog"]=model
                    && model->property("count").toInt()==state->measures.value("expected_songs").toInt();
                state->measures[name+"_visible_count"]=model ? model->property("count").toInt() : -1;
            } else {
                const auto count=active ? uiQmlListSize(active->property(sectionProperty.constData())) : qsizetype(-1);
                state->checks[name+"_count_matches_catalog"]=count==state->measures.value(
                    section==QStringLiteral("albums") ? "expected_albums" : "expected_artists").toInt();
                state->checks[name+"_other_collection_empty"]=active
                    && uiQmlListSize(active->property(section==QStringLiteral("albums") ? "artists" : "albums"))==0;
                state->measures[name+"_visible_count"]=count;
            }
            state->count=0;
            if (currentPhase==401) shell->setProperty("currentRoute",QStringLiteral("library/albums"));
            if (currentPhase==402) shell->setProperty("currentRoute",QStringLiteral("library/artists"));
            if (currentPhase==403) shell->setProperty("currentRoute",QStringLiteral("library/songs"));
            return;
        }
        case 405: {
            timer->stop();
            bool passed=true;
            for (const auto& check:state->checks) passed &= check.toBool();
            state->checks["passed"]=passed;
            state->checks["measurements"]=state->measures;
            QFile output(report);
            if (output.open(QIODevice::WriteOnly)) output.write(QJsonDocument(state->checks).toJson());
            app.exit(passed?0:7);
            return;
        }
        case 300: {
            if (!player.ready()) { --state->phase; return; }
            window->resize(1040,709);window->show();
            settings.setValue("ui.animations",false);
            settings.setValue("playback.playActionBehavior","ReplaceCurrentList");
            const QDir dataDir(qApp->property("listenfreeDataDir").toString());
            constexpr quint32 sampleRate=8000, seconds=8;
            const QByteArray pcm(sampleRate*seconds*2,'\0');
            QByteArray wave;
            QDataStream stream(&wave,QIODevice::WriteOnly);stream.setByteOrder(QDataStream::LittleEndian);
            stream.writeRawData("RIFF",4);stream << quint32(36+pcm.size());
            stream.writeRawData("WAVEfmt ",8);stream << quint32(16) << quint16(1) << quint16(1) << sampleRate;
            stream << quint32(sampleRate*2) << quint16(2) << quint16(16);
            stream.writeRawData("data",4);stream << quint32(pcm.size());stream.writeRawData(pcm.constData(),int(pcm.size()));
            QVariantMap outside;
            bool filesReady=true;
            for(int i=0;i<4;++i) {
                const auto path=dataDir.filePath(QString("play-action-%1.wav").arg(i));
                QFile file(path);
                filesReady &= file.open(QIODevice::WriteOnly) && file.write(wave)==wave.size();
                const QVariantMap row{{"trackId",QString("play-action-%1").arg(i)},
                    {"title",QString("播放行为验收 %1").arg(i)},
                    {"artist","ListenFree"},{"durationMs",seconds*1000},{"duration","00:08"},
                    {"source","Local"},{"localPath",path}};
                if(i==0) outside=row; else state->fixtureRows.append(row);
            }
            state->checks["play_action_fixture_files_created"]=filesReady;
            if(!filesReady){state->phase=89;return;}
            state->listId=collections.create("__play_action_fixture__",state->fixtureRows);
            state->checks["play_action_fixture_playlist_created"]=!state->listId.isEmpty();
            if(state->listId.isEmpty()){state->phase=89;return;}
            state->song=state->fixtureRows.at(1).toMap();
            player.clearQueue();player.enqueueTrack(outside);
            shell->setProperty("settingsOpen",false);shell->setProperty("nowPlayingOpen",false);
            shell->setProperty("currentRoute","my-lists");
            QMetaObject::invokeMethod(shell,"openCollection",Q_ARG(QVariant,QVariant("Playlist")),
                Q_ARG(QVariant,QVariant("__play_action_fixture__")),Q_ARG(QVariant,QVariant(QColor("#8192a2"))));
            return;
        }
        case 301: {
            auto* table=item("playlistDetailTracks");
            const auto value=table?table->property("displayRows"):QVariant{};
            const auto rows=value.canConvert<QJSValue>()?value.value<QJSValue>().toVariant().toList():value.toList();
            if((!table || !table->isVisible() || rows.size()!=state->fixtureRows.size()) && ++state->count<20) { --state->phase; return; }
            bool same=table && table->isVisible() && rows.size()==state->fixtureRows.size();
            for(int i=0;same && i<rows.size();++i)
                same=rows.at(i).toMap().value("localPath")==state->fixtureRows.at(i).toMap().value("localPath");
            state->checks["play_action_visible_list_is_fixture"]=same;
            state->checks["play_action_initial_queue_is_other_song"]=player.queueSongs().size()==1 &&
                player.queueSongs().first().toMap().value("localPath")!=state->song.value("localPath");
            if(!same){state->phase=303;return;}
            state->pressed=uiSongRowForPath(table,state->song.value("localPath").toString());
            state->checks["play_action_selected_row_visible"]=state->pressed && state->pressed->isVisible();
            if(!state->pressed){state->phase=303;return;}
            auto* button=uiItem(state->pressed,"songRowPlay");
            if(button) mouse(QEvent::MouseMove,button->mapToScene({button->width()/2,button->height()/2}),Qt::NoButton,Qt::NoButton);
            return;
        }
        case 302: {
            auto* row=state->pressed.data();auto* button=row?uiItem(row,"songRowPlay"):nullptr;
            if(button && !button->isVisible() && ++state->count<25) {
                mouse(QEvent::MouseMove,button->mapToScene({button->width()/2,button->height()/2}),Qt::NoButton,Qt::NoButton);
                --state->phase;return;
            }
            state->checks["play_action_play_button_visible"]=button && button->isVisible();
            if(button && button->isVisible()) click(button->mapToScene({button->width()/2,button->height()/2}));
            state->count=0;return;
        }
        case 303: {
            if(player.state()!="Playing" && ++state->count<15){--state->phase;return;}
            const auto queue=player.queueSongs();
            bool replaced=queue.size()==state->fixtureRows.size();
            for(int i=0;replaced && i<queue.size();++i)
                replaced=queue.at(i).toMap().value("localPath")==state->fixtureRows.at(i).toMap().value("localPath");
            state->checks["play_action_replaces_queue_with_visible_list"]=replaced;
            state->checks["play_action_starts_selected_song"]=player.currentQueueIndex()==1 &&
                player.currentTrack().value("localPath")==state->song.value("localPath") && player.state()=="Playing";
            state->measures["play_action_queue_count"]=queue.size();
            state->measures["play_action_state"]=player.state();
            collections.toggleTrackLiked(state->song);
            state->phase=320;return;
        }
        case 320: {
            auto* row=uiSongRowForPath(item("playlistDetailTracks"),state->song.value("localPath").toString());
            auto* floating=item("floatingPlayer");
            state->checks["favorite_membership_updates_row_and_player"]=row && row->property("liked").toBool() &&
                floating && floating->property("favorite").toBool();
            collections.toggleTrackLiked(state->song);
            state->phase=321;return;
        }
        case 321: {
            auto* row=uiSongRowForPath(item("playlistDetailTracks"),state->song.value("localPath").toString());
            auto* floating=item("floatingPlayer");
            state->checks["unfavorite_membership_updates_row_and_player"]=row && !row->property("liked").toBool() &&
                floating && !floating->property("favorite").toBool();
            QMetaObject::invokeMethod(shell,"openNowPlaying");
            state->count=0;state->phase=304;return;
        }
        case 304: {
            auto* star=item("nowPlayingFavoriteButton");
            if((!shell->property("nowPlayingOpen").toBool() || !star || !star->isVisible()) && ++state->count<15) {
                --state->phase;return;
            }
            auto* media=item("nowPlayingMediaAction");
            state->checks["nowplaying_star_left_of_media_action"]=star && media && star->isVisible() &&
                star->parentItem()==media->parentItem() && star->x()<media->x();
            if(star)click(star->mapToScene({star->width()/2,star->height()/2}));
            return;
        }
        case 305: {
            auto* menu=item("nowPlayingFavoriteMenu");
            const auto value=menu?menu->property("actions"):QVariant{};
            const auto actions=value.canConvert<QJSValue>()?value.value<QJSValue>().toVariant().toList():value.toList();
            bool header=false,existing=false,create=false;
            for(const auto& actionValue:actions) {
                const auto action=actionValue.toMap();
                header|=action.value("enabled")==false && action.value("label").toString().contains(QStringLiteral("我的收藏"));
                existing|=action.value("command").toString()==QStringLiteral("list:")+state->listId;
                create|=action.value("command").toString()==QStringLiteral("create");
            }
            state->checks["nowplaying_favorite_menu_opens"]=menu && menu->property("opened").toBool();
            state->checks["nowplaying_favorite_menu_has_lists_and_create"]=header && existing && create;
            if(menu && create) {
                menu->setProperty("opened",false);
                QMetaObject::invokeMethod(menu,"commandTriggered",Q_ARG(QString,QStringLiteral("create")),
                    Q_ARG(QVariant,QVariant(player.currentTrack())));
            }
            return;
        }
        case 306: {
            state->checks["nowplaying_favorite_create_uses_shared_dialog"]=shell->property("addPlaylistOpen").toBool() &&
                shell->property("addPlaylistCreateOnly").toBool();
            shell->setProperty("addPlaylistOpen",false);
            auto* theme=item("nowPlayingThemeButton");
            if(theme)click(theme->mapToScene({theme->width()/2,theme->height()/2}));
            return;
        }
        case 307: {
            auto* theme=item("nowPlayingThemeButton");
            auto* top=item("topThemeButton");
            state->checks["theme_buttons_have_no_selected_ring"]=shell->property("darkMode").toBool() &&
                theme && theme->property("kind").toString()==QStringLiteral("moon") &&
                !theme->property("selected").toBool() && top && !top->property("selected").toBool();
            player.stop();player.clearQueue();
            shell->setProperty("nowPlayingOpen",false);
            player.tracksModel()->setRows(state->fixtureRows);
            shell->setProperty("currentRoute","library/songs");
            if(auto* search=item("globalSearchInput"))search->setProperty("text",QStringLiteral("播放行为验收 2"));
            state->count=0;return;
        }
        case 308: {
            auto* table=item("songTable");
            auto* backend=item("songTableBackendList");
            auto* legacy=item("songTableList");
            if((!table || !backend || !backend->isVisible() || backend->property("count").toInt()!=1)
                && ++state->count<20){--state->phase;return;}
            state->checks["filtered_songs_use_backend_model"]=table && backend && legacy &&
                backend->isVisible() && !legacy->isVisible() && backend->property("count").toInt()==1;
            const auto retained=shell->property("selectedCollectionRows");
            state->checks["leaving_detail_releases_song_rows"]=(retained.canConvert<QJSValue>()
                ? retained.value<QJSValue>().toVariant().toList() : retained.toList()).isEmpty();
            state->checks["leaving_detail_releases_backend_snapshot"]=collections.detail().isEmpty() && !collections.detailBusy();
            state->pressed=uiSongRowForPath(table,state->fixtureRows.at(1).toMap().value("localPath").toString());
            state->checks["filtered_song_row_matches_query"]=state->pressed && state->pressed->isVisible();
            if(auto* row=state->pressed.data())if(auto* button=uiItem(row,"songRowPlay"))
                mouse(QEvent::MouseMove,button->mapToScene({button->width()/2,button->height()/2}),Qt::NoButton,Qt::NoButton);
            state->count=0;return;
        }
        case 309: {
            auto* row=state->pressed.data();auto* button=row?uiItem(row,"songRowPlay"):nullptr;
            if(button && !button->isVisible() && ++state->count<20){
                mouse(QEvent::MouseMove,button->mapToScene({button->width()/2,button->height()/2}),Qt::NoButton,Qt::NoButton);
                --state->phase;return;
            }
            state->checks["filtered_song_play_button_visible"]=button && button->isVisible();
            if(button && button->isVisible())click(button->mapToScene({button->width()/2,button->height()/2}));
            state->count=0;return;
        }
        case 310: {
            if(player.state()!="Playing" && ++state->count<15){--state->phase;return;}
            const auto queue=player.queueSongs();
            state->checks["filtered_current_list_replaces_queue"]=queue.size()==1 &&
                queue.first().toMap().value("localPath")==state->fixtureRows.at(1).toMap().value("localPath") &&
                player.currentQueueIndex()==0 && player.state()=="Playing";
            player.stop();player.tracksModel()->setRows({});collections.remove(state->listId);
            if(auto* search=item("globalSearchInput"))search->setProperty("text",QString{});
            state->phase=89;return;
        }
        case 200: {
            if(!player.ready()){--state->phase;return;}
            player.stop();window->resize(1040,709);
            window->setFlag(Qt::WindowDoesNotAcceptFocus,true);window->show();
            settings.setValue("ui.animations",false);
            settings.setValue("background.type","Color");settings.setValue("background.color","#18202a");
            settings.setValue("list.rememberScrollPosition",true);
            settings.setValue("scroll.collection.Playlist.__scroll_fixture__",0);
            QVariantList rows;
            for(int i=0;i<100;++i)rows.append(QVariantMap{{"source","fixture"},{"rid",QString::number(i)},
                {"title",QStringLiteral("滚动验证 %1").arg(i+1)},{"artist","ListenFree"},{"duration","03:00"}});
            state->listId=collections.create("__scroll_fixture__",rows);
            shell->setProperty("settingsOpen",false);shell->setProperty("nowPlayingOpen",false);
            shell->setProperty("currentRoute","my-lists");
            QMetaObject::invokeMethod(shell,"openCollection",Q_ARG(QVariant,QVariant("Playlist")),
                Q_ARG(QVariant,QVariant("__scroll_fixture__")),Q_ARG(QVariant,QVariant(QColor("#8192a2"))));return;
        }
        case 201: case 204: {
            auto* table=item("playlistDetailTracks");
            auto* list=table?uiItem(table,"songTableList"):nullptr;
            if((!list || !list->property("count").toInt() || table->property("scrollRestorePending").toBool())
                && ++state->detailWait<20){--state->phase;return;}
            state->detailWait=0;
            if(!list || !list->property("count").toInt() || table->property("scrollRestorePending").toBool()){
                state->checks["playlist_detail_available"]=false;state->phase=89;return;
            }
            list->setProperty("contentY",1400);return;
        }
        case 202: case 205: {
            auto* table=item("playlistDetailTracks");auto* list=uiItem(table,"songTableList");
            state->flowTime=list->property("contentY").toDouble();
            const auto rows=collections.detail().value("tracks").toList();state->count=rows.size();
            QMetaObject::invokeMethod(table,"commandRequested",Q_ARG(QString,QString("remove_from_playlist")),
                Q_ARG(QVariant,rows.at(25)),Q_ARG(int,25),Q_ARG(QVariant,QVariant{}));return;
        }
        case 203: case 206: {
            auto* list=uiItem(item("playlistDetailTracks"),"songTableList");
            const QString mode=state->phase==204?"remember_on":"remember_off";
            const double offset=list->property("contentY").toDouble();
            state->checks["remove_keeps_scroll_"+mode]=qAbs(offset-state->flowTime)<1;
            state->checks["remove_updates_tracks_"+mode]=collections.detail().value("tracks").toList().size()==state->count-1;
            state->measures["offset_after_"+mode]=offset;
            if(state->phase==204){settings.setValue("list.rememberScrollPosition",false);return;}
            window->grabWindow().save(report+".removal.png");
            settings.setValue("list.rememberScrollPosition",true);
            shell->setProperty("currentRoute","my-lists");shell->setProperty("darkMode",false);return;
        }
        case 207: case 208: {
            auto* tabs=item("myFavoritesTabs");
            const QColor color=tabs&&!tabs->childItems().isEmpty()?tabs->childItems().first()->property("color").value<QColor>():QColor();
            const bool light=state->phase==208;
            const bool ready=color.isValid() && (light
                ? color.red()>220 && color.green()>220 && color.blue()>220 && color.alpha()>120
                : color.lightness()<140);
            if(!ready && ++state->themeWait<15){--state->phase;return;}
            state->themeWait=0;
            state->checks[light?"light_tab_white_on_dark_artwork":"dark_tab_charcoal"]=color.isValid() &&
                (light?(color.red()>220 && color.green()>220 && color.blue()>220 && color.alpha()>120):color.lightness()<140);
            state->measures[light?"light_tab_color":"dark_tab_color"]=color.name(QColor::HexArgb);
            if(light){window->grabWindow().save(report+".light-dark-artwork.png");shell->setProperty("darkMode",true);return;}
            window->grabWindow().save(report+".dark.png");return;
        }
        case 209: case 210: {
            auto* nav=item("sidebarNav_radio");QQuickItem* glyph=nullptr;
            if(nav)for(auto* child:nav->childItems())if(child->property("kind")=="radio"){glyph=child;break;}
            int matching=0;QImage shot=window->grabWindow();
            if(glyph){
                const auto rect=glyph->mapRectToScene(glyph->boundingRect());const double scale=shot.width()/double(window->width());
                const auto crop=shot.copy(QRectF(rect.topLeft()*scale,rect.size()*scale).toAlignedRect());
                const QColor expected=glyph->property("glyphColor").value<QColor>();
                for(int y=0;y<crop.height();++y)for(int x=0;x<crop.width();++x){const auto c=crop.pixelColor(x,y);
                    if(qAbs(c.red()-expected.red())+qAbs(c.green()-expected.green())+qAbs(c.blue()-expected.blue())<60)++matching;}
            }
            const bool dark=state->phase==210;
            state->checks[dark?"radio_dark_theme_tint":"radio_light_theme_tint"]=matching>20;
            state->measures[dark?"radio_dark_matching_pixels":"radio_light_matching_pixels"]=matching;
            if(dark){settings.setValue("background.color","#e8eef4");shell->setProperty("darkMode",false);return;}
            shot.save(report+".light.png");
            settings.setValue("scroll.collection.Playlist.__scroll_fixture__",620);
            QMetaObject::invokeMethod(shell,"openCollection",Q_ARG(QVariant,QVariant("Playlist")),
                Q_ARG(QVariant,QVariant("__scroll_fixture__")),Q_ARG(QVariant,QVariant(QColor("#8192a2"))));return;
        }
        case 211: {
            auto* table=item("playlistDetailTracks");auto* list=table?uiItem(table,"songTableList"):nullptr;
            state->checks["reopen_restores_saved_scroll"]=list && qAbs(list->property("contentY").toDouble()-620)<1;
            collections.remove(state->listId);state->phase=89;return;
        }
        case 100: {
            if(!player.ready()) { --state->phase;return; }
            shell->setProperty("settingsOpen",true);player.stop();return;
        }
        case 101: {
            item("settingsPage")->setProperty("selectedCategory",7);return;
        }
        case 102: {
            auto* row=item("settingRow/shortcuts.application.playPause");
            click(row->mapToScene({row->width()-65,25}));return;
        }
        case 103: {
            auto* service=qApp->findChild<listenfree::ShortcutService*>("shortcutService");
            state->checks["shortcut_click_starts_capture"]=service && service->recordingKey()=="shortcuts.application.playPause";
            state->checks["shortcut_capture_prompt"]=item("shortcutBindingLabel/shortcuts.application.playPause")->property("text").toString()=="请按下你要设置的按键";
            window->grabWindow().save(report+".recording.png");
            QKeyEvent key(QEvent::KeyPress,Qt::Key_F8,Qt::ControlModifier);QApplication::sendEvent(window,&key);
            return;
        }
        case 104: {
            auto* service=qApp->findChild<listenfree::ShortcutService*>("shortcutService");
            state->checks["shortcut_capture_updates_label"]=item("shortcutBindingLabel/shortcuts.application.playPause")->property("text").toString()=="Ctrl+F8";
            state->checks["shortcut_capture_does_not_play"]=player.state()!="Playing" && service->recordingKey().isEmpty();
            auto* row=item("settingRow/shortcuts.application.next");click(row->mapToScene({row->width()-65,25}));
            QKeyEvent key(QEvent::KeyPress,Qt::Key_F8,Qt::ControlModifier);QApplication::sendEvent(window,&key);return;
        }
        case 105: {
            auto* service=qApp->findChild<listenfree::ShortcutService*>("shortcutService");
            state->checks["shortcut_conflict_points_to_existing_row"]=service->conflictKey()=="shortcuts.application.playPause" && service->binding("shortcuts.application.next")=="Ctrl+Right";
            window->grabWindow().save(report+".conflict.png");
            QKeyEvent escape(QEvent::KeyPress,Qt::Key_Escape,Qt::NoModifier);QApplication::sendEvent(window,&escape);
            auto* row=item("settingRow/shortcuts.application.playPause");click(row->mapToScene({row->width()-12,25}));return;
        }
        case 106: {
            auto* service=qApp->findChild<listenfree::ShortcutService*>("shortcutService");
            state->checks["shortcut_clear_button"]=service->binding("shortcuts.application.playPause").isEmpty() && item("shortcutBindingLabel/shortcuts.application.playPause")->property("text").toString()=="未设置";
            auto* row=item("settingRow/shortcuts.resetDefaults");click(row->mapToScene({row->width()-35,25}));return;
        }
        case 107: {
            auto* dialog=item("shortcutResetDialog");
            state->checks["shortcut_reset_requires_confirmation"]=dialog && dialog->property("open").toBool();
            QMetaObject::invokeMethod(dialog,"rejected");return;
        }
        case 108: {
            auto* service=qApp->findChild<listenfree::ShortcutService*>("shortcutService");
            state->checks["shortcut_reset_cancel_keeps_binding"]=service->binding("shortcuts.application.playPause").isEmpty();
            auto* row=item("settingRow/shortcuts.resetDefaults");click(row->mapToScene({row->width()-35,25}));
            QMetaObject::invokeMethod(item("shortcutResetDialog"),"accepted",Q_ARG(int,0));return;
        }
        case 109: {
            auto* service=qApp->findChild<listenfree::ShortcutService*>("shortcutService");
            state->checks["shortcut_reset_restores_label"]=item("shortcutBindingLabel/shortcuts.application.playPause")->property("text").toString()=="Ctrl+F5";
            service->setBinding("shortcuts.application.focusSearch","F7");
            QKeyEvent override(QEvent::ShortcutOverride,Qt::Key_F7,Qt::NoModifier);QApplication::sendEvent(window,&override);
            QKeyEvent key(QEvent::KeyPress,Qt::Key_F7,Qt::NoModifier);QApplication::sendEvent(window,&key);return;
        }
        case 110: {
            state->checks["shortcut_focus_search_connected"]=window->activeFocusItem() && window->activeFocusItem()->property("inputMethodComposing").isValid();
            auto* service=qApp->findChild<listenfree::ShortcutService*>("shortcutService");
            service->setEnabled("global",false);
            const auto defaults=service->defaults();
            for(auto it=defaults.cbegin();it!=defaults.cend();++it)if(it.key().startsWith("shortcuts.global."))service->setBinding(it.key(),"");
            service->setBinding("shortcuts.global.playPause","Ctrl+Alt+F10");
            const bool reserved=RegisterHotKey(nullptr,0x6a16,MOD_CONTROL|MOD_ALT,VK_F10);
            state->checks["shortcut_ui_conflict_fixture_registered"]=reserved;
            auto* control=item("settingSwitch/shortcuts.global.enabled");click(control->mapToScene({control->width()/2,control->height()/2}));
            if(reserved)UnregisterHotKey(nullptr,0x6a16);
            return;
        }
        case 111: {
            auto* service=qApp->findChild<listenfree::ShortcutService*>("shortcutService");
            state->checks["shortcut_global_switch_rolls_back_on_failure"]=!service->enabled("global") && !item("settingSwitch/shortcuts.global.enabled")->property("checked").toBool();
            state->checks["shortcut_global_registration_error_visible"]=!service->error().isEmpty();
            window->grabWindow().save(report+".global-conflict.png");
            service->beginCapture("shortcuts.application.next");
            shell->setProperty("settingsOpen",false);return;
        }
        case 112: {
            auto* service=qApp->findChild<listenfree::ShortcutService*>("shortcutService");
            state->checks["shortcut_leave_settings_cancels_capture"]=service->recordingKey().isEmpty();
            service->resetGroup("global");
            shell->setProperty("settingsOpen",true);state->phase=89;return;
        }
        case -3: {
            if(!player.ready() || player.songs().size()<3) { --state->phase; return; }
            QVariantList longSongs; for(const auto& row:player.songs()) if(row.toMap().value("durationMs").toLongLong()>60000 && longSongs.size()<3) longSongs.append(row);
            player.playAll(longSongs);
            shell->setProperty("nowPlayingOpen", true);
            shell->setProperty("morphProgress", 1.0);
            return;
        }
        case -2: {
            if(player.position()<1000) { --state->phase; return; }
            auto* button=item("nowPlayingNextButton");
            click(button->mapToScene({button->width()/2,button->height()/2}));
            return;
        }
        case -1: {
            if(player.currentQueueIndex()!=1 || player.position()<500) { --state->phase; return; }
            state->song=player.currentTrack(); state->flowTime=player.position(); state->count=0;
            state->phase=40; return;
        }
        case 40: {
            const bool stable=player.currentTrack().value("entryId")==state->song.value("entryId") && player.position()+100>=state->flowTime;
            state->measures["position"]=player.position(); state->measures["previous_position"]=state->flowTime;
            state->flowTime=player.position(); ++state->count;
            if(stable && state->count<35) { --state->phase; return; }
            state->checks["next_continues_without_restart"]=stable && player.position()>10000;
            state->checks["passed"]=state->checks["next_continues_without_restart"];
            state->checks["measurements"]=state->measures;
            QFile f(report);if(f.open(QIODevice::WriteOnly))f.write(QJsonDocument(state->checks).toJson());
            player.stop(); timer->stop(); app.exit(stable?0:7);return;
        }
        case 0:
            if(!player.ready()) { --state->phase; return; }
            for(const auto& row:player.songs()) if(row.toMap().value("title")=="AIZO") state->song=row.toMap();
            if(state->song.isEmpty()) { app.exit(9); return; }
            player.clearQueue(); player.enqueueTrack(state->song);
            for(const auto& row:player.songs()) { if(player.queueSongs().size()>=12)break;player.enqueueTrack(row.toMap()); }
            shell->setProperty("sidebarCollapsed",false); shell->setProperty("playerCollapsed",true); return;
        case 1: {
            auto* cover=item("floatingArtwork");
            // Check the settled shape, not an intermediate frame of the fold.
            if(cover && qAbs(cover->width()-46)>.05) { --state->phase; return; }
            auto* list=item("sidebarQueue");
            state->checks["list_reaches_bottom"]=list && list->mapToScene({0,list->height()}).y()>=window->height()-14;
            state->measures["cover_width"]=cover->width(); state->measures["cover_radius"]=cover->property("cornerRadius").toDouble();
            state->checks["collapsed_cover_is_circle"]=cover && qAbs(cover->property("cornerRadius").toDouble()-cover->width()/2)<0.5;
            auto* input=item("globalSearchInput"); click(input->mapToScene({40,10})); return;
        }
        case 2: click({1000,120}); return;
        case 3: {
            state->checks["search_blurs_outside"]=!item("globalSearchInput")->hasActiveFocus();
            state->pressed=item("sidebarQueueRow0"); state->point=state->pressed->mapToScene({20,20});
            mouse(QEvent::MouseButtonPress,state->point,Qt::LeftButton,Qt::LeftButton); return;
        }
        case 4:
            state->checks["press_keeps_row_instance"]=state->pressed && item("sidebarQueueRow0")==state->pressed;
            mouse(QEvent::MouseMove,state->point+QPointF(60,15),Qt::NoButton,Qt::LeftButton); return;
        case 5: mouse(QEvent::MouseMove,state->point+QPointF(90,20),Qt::NoButton,Qt::LeftButton); return;
        case 6:
            mouse(QEvent::MouseButtonRelease,state->point+QPointF(90,20),Qt::LeftButton,Qt::NoButton);
            state->checks["drag_release_does_not_offset_row"]=qAbs(item("sidebarQueueRow0")->x())<.5;
            shell->setProperty("sidebarCollapsed",true); return;
        case 7:
            shell->setProperty("sidebarCollapsed",false);
            mouse(QEvent::MouseMove,item("sidebarQueueRow0")->mapToScene({24,20}),Qt::NoButton,Qt::NoButton);return;
        case 8: {
            auto* row=item("sidebarQueueRow0");
            state->checks["row_alignment_after_drag_fold"]=row && qAbs(row->x())<0.5;
            state->checks["sidebar_delete_button"]=item("sidebarQueueRemove0")!=nullptr;
            window->grabWindow().save(report+".sidebar.png");
            state->count=player.queueSongs().size();
            if(auto* remove=item("sidebarQueueRemove0")) click(remove->mapToScene({13,13}));
            player.selectQueue(0,true); player.setVolume(.41f);
            shell->setProperty("nowPlayingOpen",true); shell->setProperty("morphProgress",1.0); return;
        }
        case 9: {
            state->checks["sidebar_delete_changes_backend"]=player.queueSongs().size()==state->count-1;
            if (app.arguments().contains("--check-sidebar-queue")) {
                bool passed=true;
                for(const auto& name:{"list_reaches_bottom","press_keeps_row_instance",
                                      "drag_release_does_not_offset_row","row_alignment_after_drag_fold",
                                      "sidebar_delete_button","sidebar_delete_changes_backend"})
                    passed &= state->checks.value(name).toBool();
                state->checks["passed"]=passed;
                state->checks["measurements"]=state->measures;
                QFile output(report);
                if(output.open(QIODevice::WriteOnly))output.write(QJsonDocument(state->checks).toJson());
                player.stop();timer->stop();app.exit(passed?0:7);return;
            }
            const QStringList names={"nowPlayingShuffleButton","nowPlayingPreviousButton","nowPlayingPlayPauseButton","nowPlayingNextButton","nowPlayingRepeatButton"};
            double low=1e9,high=-1e9;
            for(const auto& name:names) { auto* button=item(name); const auto y=button->mapToScene({0,button->height()/2}).y(); low=qMin(low,y); high=qMax(high,y); }
            state->checks["controls_share_centerline"]=(high-low)<0.5;
            auto* volume=item("nowPlayingVolumeSlider");
            mouse(QEvent::MouseButtonPress,volume->mapToScene({volume->width()*.25,volume->height()/2}),Qt::LeftButton,Qt::LeftButton);
            mouse(QEvent::MouseMove,volume->mapToScene({volume->width()*.5,volume->height()/2}),Qt::NoButton,Qt::LeftButton);
            mouse(QEvent::MouseMove,volume->mapToScene({volume->width()*.75,volume->height()/2}),Qt::NoButton,Qt::LeftButton);
            mouse(QEvent::MouseButtonRelease,volume->mapToScene({volume->width()*.75,volume->height()/2}),Qt::LeftButton,Qt::NoButton); return;
        }
        case 10: {
            state->checks["volume_pointer_changes_backend"]=qAbs(player.volume()-.75)<.04;
            auto* progress=item("nowPlayingProgressBar");
            mouse(QEvent::MouseButtonPress,progress->mapToScene({progress->width()*.25,progress->height()/2}),Qt::LeftButton,Qt::LeftButton);
            mouse(QEvent::MouseMove,progress->mapToScene({progress->width()*.5,progress->height()/2}),Qt::NoButton,Qt::LeftButton);
            mouse(QEvent::MouseButtonRelease,progress->mapToScene({progress->width()*.5,progress->height()/2}),Qt::LeftButton,Qt::NoButton); return;
        }
        case 11:
            state->checks["seek_pointer_changes_backend"]=player.duration()>0 && player.position()>player.duration()*45/100;
            window->grabWindow().save(report+".playing.png");
            player.stop(); shell->setProperty("nowPlayingOpen",false); shell->setProperty("morphProgress",0.0);
            QMetaObject::invokeMethod(shell,"openCollection",Q_ARG(QVariant,QVariant("Album")),Q_ARG(QVariant,state->song.value("album")),Q_ARG(QVariant,QVariant("#2d8fca"))); return;
        case 12: {
            auto* page=item("collectionPage");
            state->measures["collection_artwork"]=page->property("artworkSource").toUrl().toString();
            state->measures["expected_artwork"]=state->song.value("artwork").toString();
            state->checks["collection_uses_real_artwork"]=page && page->property("artworkSource").toUrl()==QUrl(state->song.value("artwork").toString());
            state->checks["collection_uses_real_count"]=page && page->property("subtitle").toString()==state->song.value("artist").toString()+QStringLiteral(" · %1 首歌曲").arg(page->property("trackCount").toInt());
            window->grabWindow().save(report+".album.png");
            shell->setProperty("queueOpen",true); return;
        }
        case 13: {
            if (shell->property("queueProgress").toDouble() < .999) { --state->phase; return; }
            state->checks["queue_delete_button"]=item("queueRemove0")!=nullptr;
            state->count=player.queueSongs().size();
            if(auto* remove=item("queueRemove0")) click(remove->mapToScene({14,14}));
            return;
        }
        case 14: {
            state->checks["queue_delete_changes_backend"]=player.queueSongs().size()==state->count-1;
            shell->setProperty("queueOpen",false);
            item("globalSearchInput")->setProperty("text", "AIZO");
            shell->setProperty("settingsOpen",true); return;
        }
        case 15:
            state->checks["settings_search_starts_separate"]=item("globalSearchInput")->property("text").toString().isEmpty();
            item("globalSearchInput")->setProperty("text",QStringLiteral("输出设备")); return;
        case 16: {
            auto* settingsPage=item("settingsPage");
            state->checks["settings_search_selects_matching_category"]=settingsPage && settingsPage->property("selectedCategory").toInt()==2;
            state->checks["settings_search_filters_categories"]=item("settingsCategory2")->isVisible() && !item("settingsCategory0")->isVisible();
            state->checks["settings_search_filters_rows"]=item("settingRow/audio.outputDeviceId") && item("settingRow/audio.outputDeviceId")->isVisible()
                && (!item("settingRow/playback.autoPlayOnLaunch") || !item("settingRow/playback.autoPlayOnLaunch")->isVisible());
            item("globalSearchInput")->forceActiveFocus();
            QKeyEvent enter(QEvent::KeyPress,Qt::Key_Return,Qt::NoModifier);
            QCoreApplication::sendEvent(window,&enter);
            window->grabWindow().save(report+".settings-search.png"); return;
        }
        case 17:
            state->checks["settings_enter_does_not_search_music"]=shell->property("settingsOpen").toBool() && shell->property("currentRoute").toString().startsWith("detail/");
            item("globalSearchInput")->setProperty("text",QStringLiteral("根本不存在的设置 qwerty")); return;
        case 18:
            state->checks["settings_search_empty_state"]=item("settingsPage")->property("selectedCategory").toInt()==-1
                && !item("settingsCategory2")->isVisible();
            item("globalSearchInput")->setProperty("text",QStringLiteral("刷新率")); return;
        case 19:
            state->checks["settings_search_custom_section"]=item("settingsPage")->property("selectedCategory").toInt()==0
                && !item("settingsCategory2")->isVisible()
                && (!item("settingRow/ui.fontFamily") || !item("settingRow/ui.fontFamily")->isVisible());
            item("globalSearchInput")->setProperty("text", ""); return;
        case 20:
            state->checks["settings_clear_restores_categories"]=item("settingsCategory0")->isVisible() && item("settingsCategory10")->isVisible();
            shell->setProperty("settingsOpen",false); return;
        case 21: {
            state->checks["settings_exit_restores_music_draft"]=item("globalSearchInput")->property("text").toString()=="AIZO";
            player.selectQueue(0,true);
            shell->setProperty("nowPlayingOpen",true); shell->setProperty("morphProgress",1.0);
            settings.setValue("nowPlaying.backgroundStyle","SolidMaterial"); return;
        }
        case 22: {
            state->checks["embedded_local_lyrics"]=player.lyrics().size()>5;
            state->checks["solid_background_mode"]=item("nowPlayingBackground")->property("mode").toString()=="SolidMaterial";
            player.seek(70000);
            window->grabWindow().save(report+".solid-lyrics.png");
            settings.setValue("nowPlaying.backgroundStyle","BlurredArtwork");
            settings.setValue("nowPlaying.backgroundBlur",0); return;
        }
        case 23:
            state->checks["blur_zero_setting_reaches_background"]=item("nowPlayingBackground")->property("blurAmount").toDouble()==0;
            state->background=window->grabWindow(); state->background.save(report+".blur-zero.png");
            settings.setValue("nowPlaying.backgroundBlur",100); return;
        case 24: {
            auto* page=item("nowPlayingPage");auto* loader=page->parentItem();
            auto* probe=new UiInputProbe(loader->parentItem());probe->setZ(loader->z()-.1);probe->setSize(loader->size());
            for(const auto& point:QList<QPointF>{{page->width()*.2,page->height()*.8},{page->width()*.5,page->height()*.95},{page->width()*.1,page->height()*.2}}) {
                const auto scene=page->mapToScene(point);
                mouse(QEvent::MouseButtonPress,scene,Qt::RightButton,Qt::RightButton);mouse(QEvent::MouseButtonRelease,scene,Qt::RightButton,Qt::NoButton);
                QWheelEvent wheel(scene,window->mapToGlobal(scene.toPoint()),{},QPoint(0,-120),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);QCoreApplication::sendEvent(window,&wheel);
            }
            state->checks["nowplaying_blocks_background_right_click"]=probe->presses==0;
            state->checks["nowplaying_blocks_background_wheel"]=probe->wheels==0;
            delete probe;
            const auto current=window->grabWindow(); current.save(report+".blur-full.png");
            state->checks["blur_slider_changes_rendering"]=current!=state->background;
            settings.setValue("nowPlaying.backgroundStyle","DynamicFlow"); return;
        }
        case 25: {
            auto* shader=item("artworkFlowShader");
            state->checks["flow_shader_loaded"]=shader && shader->property("log").toString().isEmpty();
            state->flowTime=item("nowPlayingBackground")->property("flowTime").toDouble(); return;
        }
        case 26:
            state->checks["flow_moves_when_playing"]=item("nowPlayingBackground")->property("flowTime").toDouble()>state->flowTime;
            window->grabWindow().save(report+".flow.png"); player.pause(); return;
        case 27:
            state->flowTime=item("nowPlayingBackground")->property("flowTime").toDouble(); return;
        case 28:
            state->checks["flow_stops_when_paused"]=item("nowPlayingBackground")->property("flowTime").toDouble()==state->flowTime;
            state->checks["local_comments_enabled"]=item("nowPlayingCommentsButton")->isEnabled();
            click(item("nowPlayingCommentsButton")->mapToScene({15,15})); return;
        case 29:
            if (qAbs(item("nowPlayingLyricDoor")->property("angle").toDouble()-180)>.01) { --state->phase; return; }
            state->checks["comments_flips_same_region"]=item("nowPlayingCommentsPanel")->isVisible() && item("nowPlayingLyricDoor")->property("angle").toDouble()==180;
            window->grabWindow().save(report+".comments-flip.png");
            click(item("nowPlayingCommentsButton")->mapToScene({15,15})); return;
        case 30: {
            if (qAbs(item("nowPlayingLyricDoor")->property("angle").toDouble())>.01) { --state->phase; return; }
            state->checks["comments_flips_back"]=qAbs(item("nowPlayingLyricDoor")->property("angle").toDouble())<.01;
            player.stop();
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("morphProgress",0.0);
            shell->setProperty("currentRoute","my-lists");
            state->listId=collections.create("界面验收歌单",{state->song});return;
        }
        case 31: {
            state->checks["my_lists_real_model"]=item("myListsPage") && item("myListsPage")->property("playlistCount").toInt() == collections.playlists().size();
            window->grabWindow().save(report+".my-lists.png");
            settings.setValue("download.enabled",true);shell->setProperty("downloadsOpen",true);return;
        }
        case 32: {
            auto* panel=item("downloadPanel");
            if(panel && qAbs(panel->x()-(window->width()-450))>.1){--state->phase;return;}
            state->checks["download_right_panel"]=panel && panel->isVisible() && qAbs(panel->x()-(window->width()-450))<.1;
            window->grabWindow().save(report+".downloads.png");shell->setProperty("downloadsOpen",false);
            settings.setValue("window.transparencyEnabled",false);return;
        }
        case 33: {
            shell->setProperty("sidebarCollapsed",false);
            window->grabWindow().save(report+".opaque.png");settings.setValue("window.transparencyEnabled",true);return;
        }
        case 34: {
            const auto capture=window->grabWindow();capture.save(report+".transparent.png");
            const auto scale=capture.width()/double(window->width());
            state->measures["sidebar_alpha"]=capture.pixelColor(int(4*scale),int(400*scale)).alpha();
            state->measures["content_alpha"]=capture.pixelColor(int(500*scale),int(70*scale)).alpha();
            state->checks["output_devices_enumerated"]=!player.outputDevices().isEmpty();
            collections.remove(state->listId);shell->setProperty("currentRoute","discover");collections.refresh();return;
        }
        case 35: {
            if(collections.busy()){--state->phase;return;}
            state->checks["discover_has_real_cards"]=!collections.recommendations().isEmpty()&&!collections.charts().isEmpty();
            if (state->measures.value("cover_wait_ticks").toInt()<8) {state->measures["cover_wait_ticks"]=state->measures.value("cover_wait_ticks").toInt()+1;--state->phase;return;}
            window->grabWindow().save(report+".discover.png");
            shell->setProperty("settingsOpen",false);shell->setProperty("currentRoute","library/songs");click(item("globalSearchInput")->mapToScene({30,14}));
            item("globalSearchInput")->setProperty("text","AIZO");return;
        }
        case 36: {
            auto* capsule=item("searchSuggestionCapsule");
            if(capsule->height()<75 || qAbs(capsule->width()-342)>.5 || !item("searchSuggestionRow0")){--state->phase;return;}
            state->checks["suggestions_extend_integrated_field"]=capsule->height()>60 && qAbs(capsule->width()-342)<.5;
            auto* icon=item("integratedSearchIcon");
            state->checks["search_icon_stays_integrated"]=icon && icon->isVisible() && icon->mapToScene({0,0}).x()<capsule->mapToScene({33,0}).x();
            window->grabWindow().save(report+".suggestions.png");
            auto* row=item("searchSuggestionRow0");
            state->measures["suggestion_expected"]=row->property("modelData").toString();
            click(row->mapToScene({20,row->height()/2}));return;
        }
        case 37: {
            state->checks["suggestion_below_header_is_clickable"]=shell->property("currentRoute").toString()=="library/songs"
                && shell->property("pageSearchQuery").toString()==state->measures.value("suggestion_expected").toString();
            shell->setProperty("currentRoute","discover");
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("450444")));
            state->checks["suggestions_close_on_selection"]=!item("globalSearchInput")->hasActiveFocus();
            const auto script=qEnvironmentVariable("LISTENFREE_TEST_XINGHAI","E:/下载/v260507/xinghai-music-sourcev2.3.12.js");
            state->checks["xinghai_imported"]=sources.importLocalFile(script);return;
        }
        case 38: {
            if(!shell->property("sourceUpdateOpen").toBool()){--state->phase;return;}
            state->checks["xinghai_actual_update_dialog"]=!shell->property("sourceUpdateLog").toString().isEmpty()&&item("sourceUpdateDialog")->isVisible();
            window->grabWindow().save(report+".source-update.png");shell->setProperty("sourceUpdateOpen",false);
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("morphProgress",0.0);shell->setProperty("playerCollapsed",true);
            state->phase=41;return;
        }
        case 41: {
            auto* floating=item("floatingPlayer");
            state->probe=new UiInputProbe(floating->parentItem());state->probe->setZ(floating->z()-.5);
            state->probe->setSize(QSizeF(window->width(),window->height()));
            auto* button=item("floatingCollapsedPlayPauseButton");click(button->mapToScene({button->width()/2,button->height()/2}));return;
        }
        case 42: {
            state->checks["miniplayer_blocks_underlying_click"]=state->probe->presses==0;
            shell->setProperty("queueOpen",true);return;
        }
        case 43: {
            if(shell->property("queueProgress").toDouble()<.999){--state->phase;return;}
            const QPointF point(window->width()-150,window->height()-100);
            QWheelEvent wheel(point,window->mapToGlobal(point.toPoint()),{},QPoint(0,-1200),Qt::NoButton,Qt::NoModifier,Qt::NoScrollPhase,false);
            QCoreApplication::sendEvent(window,&wheel);
            state->checks["queue_blocks_wheel_at_bounds"]=state->probe->wheels==0;
            state->probe->deleteLater();shell->setProperty("queueOpen",false);shell->setProperty("playerCollapsed",true);
            shell->setProperty("currentRoute","search");return;
        }
        case 44: {
            auto* table=item("songTable");
            if(!table){state->checks["context_menu_toolbar_closes"]=false;state->phase=47;return;}
            const auto p=table->mapToScene({65,65});mouse(QEvent::MouseButtonPress,p,Qt::RightButton,Qt::RightButton);mouse(QEvent::MouseButtonRelease,p,Qt::RightButton,Qt::NoButton);return;
        }
        case 45: {
            auto* menu=window->findChild<QObject*>("contextPopup");
            state->checks["context_menu_opened_above_page"]=menu && menu->property("visible").toBool();
            if(auto* toolbar=item("searchPlatformToolbar"))click(toolbar->mapToScene({110,20}));return;
        }
        case 46: {
            auto* menu=window->findChild<QObject*>("contextPopup");
            state->checks["context_menu_toolbar_closes"]=!menu || !menu->property("visible").toBool();return;
        }
        case 47: {
            player.openTrack(state->song);shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.0);return;
        }
        case 48: {
            if(player.position()<500){--state->phase;return;}player.seek(15000);player.pause();return;
        }
        case 49: {
            if(player.state()!="Paused"){--state->phase;return;}
            const int settling=state->measures.value("pause_settling_ticks").toInt();
            if(settling<4){state->measures["pause_settling_ticks"]=settling+1;--state->phase;return;}
            state->pausedPosition=player.position();
            const auto lyricIndex=player.currentLyricIndex();
            state->checks["top_bar_lyric_follows_seek"]=lyricIndex>=0 && item("topBarCurrentLyric")->property("text").toString()==player.lyrics().value(lyricIndex).toMap().value("text").toString();
            auto* row=item("lyricRow"+QString::number(player.currentLyricIndex()));
            if(!row){--state->phase;return;}
            const auto p=row->mapToScene({row->width()/2,row->height()/2});mouse(QEvent::MouseButtonPress,p,Qt::RightButton,Qt::RightButton);mouse(QEvent::MouseButtonRelease,p,Qt::RightButton,Qt::NoButton);return;
        }
        case 50: {
            window->grabWindow().save(report+".lyric-menu.png");
            if(auto* option=item("lyricOptionLeft"))click(option->mapToScene({option->width()/2,option->height()/2}));
            else state->checks["lyric_layout_menu_opened"]=false;
            return;
        }
        case 51: {
            state->measures["lyric_position_before"]=state->pausedPosition;state->measures["lyric_position_after"]=player.position();state->measures["lyric_player_state"]=player.state();state->measures["lyric_alignment"]=settings.value("lyrics.alignment").toString();
            state->checks["lyric_layout_does_not_seek"]=player.position()==state->pausedPosition && settings.value("lyrics.alignment").toString()=="Left";
            state->checks["immersive_entry_preserved"]=item("nowPlayingImmersiveButton")!=nullptr;
            player.stop();
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("morphProgress",0.0);shell->setProperty("currentRoute","library/albums");return;
        }
        case 52: {
            auto* card=item("albumCard1");
            if(card)click(card->mapToScene({card->width()/2,card->height()/2}));return;
        }
        case 53: {
            if(shell->property("collectionMorphActive").toBool()){--state->phase;return;}
            auto* surface=item("albumDetailSurface");
            state->checks["album_card_opens_inset_detail"]=shell->property("currentRoute").toString()=="detail/album" && surface && surface->x()>0 && surface->width()<surface->parentItem()->width();
            window->grabWindow().save(report+".album-detail.png");
            if(surface)click(surface->parentItem()->mapToScene({5,5}));return;
        }
        case 54: {
            if(shell->property("collectionMorphActive").toBool()){--state->phase;return;}
            state->checks["album_outside_reverses_to_library"]=shell->property("currentRoute").toString()=="library/albums";
            QMetaObject::invokeMethod(shell,"openCollection",Q_ARG(QVariant,QVariant("Artist")),Q_ARG(QVariant,QVariant(QStringLiteral("周杰伦"))),Q_ARG(QVariant,QVariant("#2d8fca")));return;
        }
        case 55: {
            auto* photo=item("artistPhotoLoader");
            auto* hero=item("artistHeroArtwork");
            const int waits=state->measures["artist_photo_waits"].toInt();
            const bool photoReady=photo && hero && photo->property("status").toInt()==1 && hero->property("status").toInt()==1 && hero->property("source")==photo->property("source");
            if(!photoReady && waits<70){state->measures["artist_photo_waits"]=waits+1;--state->phase;return;}
            state->checks["artist_photo_actually_loaded"]=photoReady;
            auto* artist=item("artistScroll");
            state->checks["artist_grouped_album_sections"]=item("collectionPage")->property("albumSections").value<QJSValue>().toVariant().toList().size()>1;
            window->grabWindow().save(report+".artist-hero.png");if(artist)artist->setProperty("contentY",320);return;
        }
        case 56: {
            state->checks["artist_sticky_header"]=item("artistStickyHeader") && item("artistStickyHeader")->opacity()>.99;
            window->grabWindow().save(report+".artist-sticky.png");
            QMetaObject::invokeMethod(shell,"chooseDownload",Q_ARG(QVariant,QVariant(QVariantList{QVariantMap{{"source","kw"},{"rid","450444"},{"title","下载规格验证"}}})));
            return;
        }
        case 57: {
            state->checks["download_quality_popup"]=item("downloadSpecificationOptions") && (!shell->property("downloadSpecifications").toList().isEmpty() || !shell->property("downloadSpecifications").value<QJSValue>().toVariant().toList().isEmpty());
            auto specs=shell->property("downloadSpecifications").toList();
            if(specs.isEmpty())specs=shell->property("downloadSpecifications").value<QJSValue>().toVariant().toList();
            bool commonOnly=!specs.isEmpty();for(const auto& v:specs)commonOnly &= QStringList{"128k","192k","320k","flac"}.contains(v.toMap().value("value").toString());
            state->checks["download_only_common_mp3_flac"]=commonOnly;
            window->grabWindow().save(report+".download-quality.png");
            QKeyEvent escape(QEvent::KeyPress,Qt::Key_Escape,Qt::NoModifier);QCoreApplication::sendEvent(window,&escape);
            const auto url=qEnvironmentVariable("LISTENFREE_TEST_MOTION_URL");
            if(url.isEmpty()){state->phase=63;return;}
            shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.0);state->listId=url;return;
        }
        case 58: {
            settings.setValue("nowPlaying.backgroundStyle","BlurredArtwork");
            if(auto* page=item("nowPlayingPage"))page->setProperty("motionSource",state->listId);
            return;
        }
        case 59: {
            auto* movie=window->findChild<QObject*>("dynamicArtworkMediaPlayer");
            if(!movie || !movie->property("hasVideo").toBool() || movie->property("position").toLongLong()<1000){--state->phase;return;}
            state->checks["dynamic_cover_no_toggle"]=!item("dynamicArtworkToggle");
            return;
        }
        case 60: {
            auto* movie=window->findChild<QObject*>("dynamicArtworkMediaPlayer");
            state->checks["dynamic_background_uses_video"]=item("backgroundMotionSample") && item("nowPlayingBackground")->property("motionTexture").value<QQuickItem*>()!=nullptr;
            state->measures["dynamic_background_mode"]=item("nowPlayingBackground")->property("mode").toString();
            state->measures["dynamic_sample_exists"]=item("backgroundMotionSample")!=nullptr;
            state->checks["dynamic_background_shares_one_player"]=window->findChildren<QObject*>("dynamicArtworkMediaPlayer").size()==1;
            state->checks["dynamic_cover_autoplays"]=movie && movie->property("playbackState").toInt()==1;
            state->pausedPosition=movie?movie->property("position").toLongLong():0;
            window->grabWindow().save(report+".dynamic-background.png");return;
        }
        case 61: {
            auto* movie=window->findChild<QObject*>("dynamicArtworkMediaPlayer");
            state->checks["dynamic_cover_advances"]=movie && movie->property("position").toLongLong()!=state->pausedPosition;
            return;
        }
        case 62: {
            auto* movie=window->findChild<QObject*>("dynamicArtworkMediaPlayer");
            state->checks["dynamic_cover_keeps_playing"]=movie && movie->property("playbackState").toInt()==1;
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("morphProgress",0.0);return;
        }
        case 63: {
            if(!qEnvironmentVariable("LISTENFREE_TEST_MOTION_URL").isEmpty())state->checks["dynamic_cover_released_on_leave"]=window->findChild<QObject*>("dynamicArtworkMediaPlayer")==nullptr;
            shell->setProperty("nowPlayingOpen",false);shell->setProperty("morphProgress",0.0);
            shell->setProperty("currentRoute","library/songs");
            state->measures["online_query_before_local"]=player.lastQuery();
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("__no_local_match_7391__")));
            return;
        }
        case 64: {
            state->checks["local_empty_stays_local"]=shell->property("currentRoute").toString()=="library/songs"
                && item("localSearchEmpty") && item("localSearchEmpty")->isVisible();
            state->checks["local_search_has_no_platform_toolbar"]=!item("searchPlatformToolbar");
            state->checks["local_search_never_calls_online"]=player.lastQuery()==state->measures.value("online_query_before_local").toString();
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("AIZO")));return;
        }
        case 65: {
            const auto list=[](QVariant v) { return v.canConvert<QJSValue>() ? v.value<QJSValue>().toVariant().toList() : v.toList(); };
            auto* page=item("libraryPage");
            QVariantList rows;
            const auto modelValue=page ? page->property("displayTracksModel") : QVariant{};
            auto* visibleModel=modelValue.value<QObject*>();
            if (!visibleModel && modelValue.canConvert<QJSValue>()) visibleModel=modelValue.value<QJSValue>().toQObject();
            if (visibleModel) QMetaObject::invokeMethod(visibleModel,"snapshotRows",Q_RETURN_ARG(QVariantList,rows));
            else if (page) rows=list(page->property("songs"));
            auto* thumbnail=item("songRowCover");
            state->checks["local_row_thumbnail_loaded"]=thumbnail && !thumbnail->property("missingArtwork").toBool() && thumbnail->property("sourcePixelSize").toInt()<=128;
            state->checks["local_song_search_matches_metadata"]=!rows.isEmpty();
            bool localOnly=!rows.isEmpty();for(const auto& row:rows)localOnly &= !row.toMap().value("localPath").toString().isEmpty();
            state->checks["local_results_contain_only_local_songs"]=localOnly;
            shell->setProperty("currentRoute","library/albums");return;
        }
        case 66: {
            state->checks["route_change_clears_search_scope"]=item("globalSearchInput")->property("text").toString().isEmpty()
                && shell->property("pageSearchQuery").toString().isEmpty();
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("AIZO")));return;
        }
        case 67: {
            const auto list=[](QVariant v) { return v.canConvert<QJSValue>() ? v.value<QJSValue>().toVariant().toList() : v.toList(); };
            auto* page=item("libraryPage");const auto rows=page?list(page->property("albums")):QVariantList{};
            bool exact=!rows.isEmpty();for(const auto& row:rows)exact &= row.toMap().value("title").toString().contains("AIZO",Qt::CaseInsensitive);
            state->checks["album_search_filters_album_titles"]=exact;
            shell->setProperty("currentRoute","library/artists");
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("King Gnu")));return;
        }
        case 68: {
            const auto list=[](QVariant v) { return v.canConvert<QJSValue>() ? v.value<QJSValue>().toVariant().toList() : v.toList(); };
            auto* page=item("libraryPage");const auto rows=page?list(page->property("artists")):QVariantList{};
            bool exact=!rows.isEmpty();for(const auto& row:rows)exact &= row.toMap().value("name").toString().contains("King Gnu",Qt::CaseInsensitive);
            state->checks["artist_search_filters_artist_names"]=exact;
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("__no_artist_7391__")));return;
        }
        case 69: {
            state->checks["artist_search_empty_stays_local"]=shell->property("currentRoute").toString()=="library/artists"
                && item("localSearchEmpty") && item("localSearchEmpty")->isVisible() && !item("searchPlatformToolbar");
            shell->setProperty("currentRoute","playlists");
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("__no_playlist_7391__")));return;
        }
        case 70: {
            const auto value=item("playlistPage")->property("filteredPlaylists");
            const auto rows=value.canConvert<QJSValue>()?value.value<QJSValue>().toVariant().toList():value.toList();
            state->checks["playlist_search_keeps_content_scope"]=shell->property("currentRoute").toString()=="playlists" && rows.isEmpty()
                && player.lastQuery()==state->measures.value("online_query_before_local").toString();
            state->listId=collections.create("__scope_playlist_7391__",{state->song});
            shell->setProperty("currentRoute","my-lists");
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("__scope_playlist_7391__")));return;
        }
        case 71: {
            const auto value=item("myListsPage")->property("visiblePlaylists");
            const auto rows=value.canConvert<QJSValue>()?value.value<QJSValue>().toVariant().toList():value.toList();
            state->checks["my_lists_search_filters_playlist_rows"]=rows.size()==1 && shell->property("currentRoute").toString()=="my-lists";
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("__missing_own_playlist_7391__")));return;
        }
        case 72: {
            const auto value=item("myListsPage")->property("visiblePlaylists");
            const auto rows=value.canConvert<QJSValue>()?value.value<QJSValue>().toVariant().toList():value.toList();
            state->checks["my_lists_search_can_be_empty"]=rows.isEmpty();collections.remove(state->listId);
            shell->setProperty("currentRoute","library/albums");
            QMetaObject::invokeMethod(shell,"openCollection",Q_ARG(QVariant,QVariant("Album")),Q_ARG(QVariant,state->song.value("album")),Q_ARG(QVariant,QVariant("#2d8fca")));
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,state->song.value("title")));return;
        }
        case 73: {
            const auto value=item("collectionPage")->property("visibleRows");
            const auto rows=value.canConvert<QJSValue>()?value.value<QJSValue>().toVariant().toList():value.toList();
            bool scoped=!rows.isEmpty();for(const auto& row:rows)scoped &= row.toMap().value("album")==state->song.value("album");
            state->checks["collection_search_stays_within_album"]=scoped && shell->property("currentRoute").toString()=="detail/album";
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("__missing_album_song_7391__")));return;
        }
        case 74: {
            const auto value=item("collectionPage")->property("visibleRows");
            const auto rows=value.canConvert<QJSValue>()?value.value<QJSValue>().toVariant().toList():value.toList();
            state->checks["collection_search_empty_never_falls_back"]=rows.isEmpty() && !item("searchPlatformToolbar")
                && player.lastQuery()==state->measures.value("online_query_before_local").toString();
            shell->setProperty("sidebarCollapsed",false);shell->setProperty("darkMode",false);
            shell->setProperty("currentRoute","library/songs");
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("AIZO")));
            return;
        }
        case 75: {
            auto* row=item("songRow");
            if(!row || !row->isVisible()){--state->phase;return;}
            state->pressed=row;
            state->checks["shared_song_row_has_cover_and_actions"]=uiItem(row,"songRowCover") && uiItem(row,"songRowDownload") && uiItem(row,"songRowFavorite") && uiItem(row,"songRowNext");
            auto* title=uiItem(row,"songRowTitle");auto* actions=uiItem(row,"songRowActions");auto* album=uiItem(row,"songRowAlbum");
            state->checks["song_row_column_order"]=title && actions && album && title->x()<actions->x() && actions->x()<album->x();
            state->measures["row_title_width"]=title?title->width():-1;
            mouse(QEvent::MouseMove,{1000,100},Qt::NoButton,Qt::NoButton);
            QVariantMap initial;for(const auto& value:player.songs())if(value.toMap().value("localPath").toString().endsWith(".mp3",Qt::CaseInsensitive) && value.toMap().value("durationMs").toLongLong()>60000){initial=value.toMap();break;}
            player.playAll({initial,state->song});return;
        }
        case 76: {
            if(player.state()!="Playing" || player.position()<600){--state->phase;return;}
            player.pause();state->pausedPosition=player.position();state->measures["row_initial_track"]=player.currentTrackId();state->count=player.queueSongs().size();
            auto* row=state->pressed.data();
            state->checks["song_row_idle_shows_number"]=row && uiItem(row,"songRowNumber")->isVisible() && !uiItem(row,"songRowPlay")->isVisible();
            state->measures["liked_before"]=collections.isTrackLiked(state->song);
            if(row)mouse(QEvent::MouseMove,row->mapToScene({row->width()/2,row->height()/2}),Qt::NoButton,Qt::NoButton);
            return;
        }
        case 77: {
            if(player.state()!="Paused"){--state->phase;return;}
            // Qmmp commits pause asynchronously; compare subsequent row
            // actions with its settled position, not the pause request time.
            state->pausedPosition=player.position();
            auto* row=state->pressed.data();
            if(row && !row->property("hovered").toBool()){mouse(QEvent::MouseMove,row->mapToScene({row->width()/2,row->height()/2}),Qt::NoButton,Qt::NoButton);--state->phase;return;}
            state->checks["song_row_hover_replaces_number_with_play"]=row && uiItem(row,"songRowPlay")->isVisible() && !uiItem(row,"songRowNumber")->isVisible();
            state->checks["song_row_hover_keeps_layout"]=row && uiItem(row,"songRowTitle")->width()==state->measures["row_title_width"].toDouble();
            state->checks["local_row_download_disabled"]=row && !uiItem(row,"songRowDownload")->isEnabled();
            if(row){auto* b=uiItem(row,"songRowFavorite");click(b->mapToScene({b->width()/2,b->height()/2}));}
            return;
        }
        case 78: {
            state->checks["row_favorite_changes_persisted_state"]=collections.isTrackLiked(state->song)!=state->measures["liked_before"].toBool();
            state->checks["row_favorite_does_not_play"]=player.state()=="Paused" && player.position()==state->pausedPosition && player.queueSongs().size()==state->count;
            if(auto* row=state->pressed.data()){auto* b=uiItem(row,"songRowNext");click(b->mapToScene({b->width()/2,b->height()/2}));}
            return;
        }
        case 79: {
            const auto queue=player.queueSongs();
            state->checks["row_next_inserts_immediately_after_current"]=queue.size()==state->count && queue.value(player.currentQueueIndex()+1).toMap().value("trackId")==state->song.value("trackId");
            state->checks["row_next_does_not_start_or_seek"]=player.state()=="Paused" && player.position()==state->pausedPosition && player.currentTrackId()==state->measures["row_initial_track"].toString();
            window->grabWindow().save(report+".song-row-light.png");
            shell->setProperty("darkMode",true);return;
        }
        case 80: {
            window->grabWindow().save(report+".song-row-dark.png");
            if(auto* row=state->pressed.data()){auto* b=uiItem(row,"songRowPlay");click(b->mapToScene({b->width()/2,b->height()/2}));}
            return;
        }
        case 81: {
            if(player.state()!="Playing" || player.position()<600){--state->phase;return;}
            state->checks["row_number_play_starts_selected_song"]=player.currentTrackId()==state->song.value("trackId").toString();
            player.stop();shell->setProperty("darkMode",false);shell->setProperty("playerCollapsed",true);
            shell->setProperty("currentRoute","discover");
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("https://www.kuwo.cn/play_detail/450444")));return;
        }
        case 82: {
            if(player.busy() || player.searchResults().isEmpty()){--state->phase;return;}
            auto* row=item("songRow");
            if(!row || !row->isVisible()){--state->phase;return;}
            state->pressed=row;mouse(QEvent::MouseMove,row->mapToScene({row->width()/2,row->height()/2}),Qt::NoButton,Qt::NoButton);
            return;
        }
        case 83: {
            // Artwork hydration can replace a result delegate between ticks.
            // Hover the current row just as a pointer approaching it would.
            auto* row=item("songRow");
            if(!row || !row->property("hovered").toBool()){if(row)mouse(QEvent::MouseMove,row->mapToScene({row->width()/2,row->height()/2}),Qt::NoButton,Qt::NoButton);--state->phase;return;}
            auto* b=uiItem(row,"songRowDownload");state->checks["online_row_download_enabled"]=b && b->isEnabled();if(b)click(b->mapToScene({b->width()/2,b->height()/2}));
            return;
        }
        case 84: {
            state->checks["row_download_opens_quality_picker"]=item("downloadSpecificationOptions") && item("downloadSpecificationOptions")->isVisible();
            QKeyEvent escape(QEvent::KeyPress,Qt::Key_Escape,Qt::NoModifier);QCoreApplication::sendEvent(window,&escape);
            auto* mini=item("floatingPlayer");
            state->checks["capsule_is_compact_166"]=mini && qAbs(mini->width()-166)<.1 && qAbs(mini->height()-62)<.1;
            state->checks["sidebar_has_panel_toggle_glyph"]=item("sidebarToggleGlyph") && item("sidebarToggleGlyph")->property("kind")=="sidebar";
            return;
        }
        case 85: {
            if(!state->measures.contains("sidebar_toggle_sent")){
                state->measures["sidebar_toggle_sent"]=true;
                if(auto* b=item("sidebarToggle"))click(b->mapToScene({20,b->height()/2}));
                --state->phase;return;
            }
            state->checks["sidebar_toggle_collapses_navigation"]=shell->property("sidebarCollapsed").toBool();
            if(auto* b=item("sidebarToggle"))click(b->mapToScene({20,b->height()/2}));
            auto keep=player.songs().first().toMap();keep["title"]="__keep_original_playlist_row__";
            auto remove=state->song;remove["title"]="__remove_filtered_playlist_row__";
            state->song=remove;state->listId=collections.create("__filtered_delete_list__",{keep,remove});
            shell->setProperty("currentRoute","my-lists");
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("__remove_filtered_playlist_row__")));return;
        }
        case 86: {
            auto* page=item("myListsPage");const auto value=page->property("selectedPlaylist");const auto selected=value.canConvert<QJSValue>()?value.value<QJSValue>().toVariant().toMap():value.toMap();
            state->checks["my_lists_filter_selects_matching_detail"]=selected.value("id")==state->listId;
            auto* table=uiItem(page,"songTable");
            state->checks["filtered_delete_uses_row_command"]=table && QMetaObject::invokeMethod(table,"commandRequested",Q_ARG(QString,QString("remove_from_playlist")),Q_ARG(QVariant,QVariant(state->song)),Q_ARG(int,0));
            return;
        }
        case 87: {
            QVariantList rows;for(const auto& v:collections.playlists())if(v.toMap().value("id")==state->listId)rows=v.toMap().value("tracks").toList();
            state->checks["filtered_delete_preserves_unmatched_song"]=rows.size()==1 && rows.first().toMap().value("title")=="__keep_original_playlist_row__";
            auto* page=item("myListsPage");
            const auto selected=page->property("selectedPlaylist");
            state->checks["my_lists_empty_filter_clears_detail"]=selected.canConvert<QJSValue>()?selected.value<QJSValue>().isNull():selected.isNull();
            QMetaObject::invokeMethod(shell,"runSearch",Q_ARG(QVariant,QVariant("")));return;
        }
        case 88: {
            const auto value=item("myListsPage")->property("selectedPlaylist");const auto selected=value.canConvert<QJSValue>()?value.value<QJSValue>().toVariant().toMap():value.toMap();
            state->checks["clearing_filter_restores_playlist_selection"]=selected.value("id")==state->listId;
            collections.remove(state->listId);
            shell->setProperty("currentRoute","library/songs");
            return;
        }
        case 89: {
            player.clearQueue();
            state->checks["top_bar_no_demo_when_empty"]=item("topBarCurrentLyric")->property("text").toString().isEmpty();
            timer->stop(); bool passed=true; for(auto v:state->checks) passed &= v.toBool();
            state->checks["passed"]=passed;
            state->checks["measurements"]=state->measures;
            QFile file(report); if(file.open(QIODevice::WriteOnly)) file.write(QJsonDocument(state->checks).toJson());
            window->grabWindow().save(report+".png"); app.exit(passed?0:7); return;
        }
        }
    });
    timer->start();
}
