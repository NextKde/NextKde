#pragma once
#include <QApplication>
#include <QElapsedTimer>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickItem>
#include <QQuickWindow>
#include <QQmlProperty>
#include <QQmlComponent>
#include <QQmlContext>
#include <QVideoFrame>
#include <QJSValue>
#include <QPointer>
#include <QSet>
#include <QMutex>
#include <QLibrary>
#include <QMouseEvent>
#include <memory>
#include <QtQuick/private/qquickitem_p.h>

inline QQuickItem* auditItem(QQuickItem* root,const QString& name){
    if(root->objectName()==name)return root;
    for(auto* child:root->childItems())if(auto* found=auditItem(child,name))return found;
    return nullptr;
}
inline QVariant auditVariant(const QVariant& v){return v.canConvert<QJSValue>()?v.value<QJSValue>().toVariant():v;}
// An unattended diagnostic window must not turn incidental user input into
// a different workload. This filter is opt-in and absent from the product.
class AuditInputGuard final : public QObject {
public:
    using QObject::QObject;
    bool eventFilter(QObject*,QEvent* event) override {
        if(!event->spontaneous())return false;
        switch(event->type()){
        case QEvent::MouseButtonPress:case QEvent::MouseButtonRelease:case QEvent::MouseButtonDblClick:
        case QEvent::MouseMove:case QEvent::Wheel:case QEvent::KeyPress:case QEvent::KeyRelease:
        case QEvent::ShortcutOverride:case QEvent::TouchBegin:case QEvent::TouchUpdate:case QEvent::TouchEnd:return true;
        default:return false;
        }
    }
};
inline QQuickItem* auditVisibleItem(QQuickItem* root,const QString& name,const QByteArray& type={}){
    if(root->isVisible() && (name.isEmpty() || root->objectName()==name)
        && (type.isEmpty() || root->inherits(type.constData())))return root;
    for(auto* child:root->childItems())if(auto* found=auditVisibleItem(child,name,type))return found;
    return nullptr;
}
inline void runImmersiveMemoryProbe(QApplication& app,QQuickWindow* window,QObject* shell,
    listenfree::qmlbridge::PortableSession& player,listenfree::qmlbridge::SettingsController& settings,
    listenfree::qmlbridge::ImmersiveController& service,listenfree::qmlbridge::SourceController& sources,
    listenfree::qmlbridge::CollectionService& collections,const QStringList& args){
    const int input=args.indexOf("--audit-config");
    if(input<0||input+1>=args.size()||!args.contains("--data-dir")){app.exit(9);return;}
    QFile configFile(args[input+1]);if(!configFile.open(QIODevice::ReadOnly)){app.exit(9);return;}
    const auto config=QJsonDocument::fromJson(configFile.readAll()).object();
    if(config.value("decoderCpus").toInt()>0) {
        // Qt's FFmpeg 7 runtime is separate from the Qmmp/FFmpeg 9 audio DLLs.
        static QLibrary avutil(QCoreApplication::applicationDirPath()+"/avutil-59.dll");
        avutil.setLoadHints(QLibrary::PreventUnloadHint);
        const auto force=reinterpret_cast<void(*)(int)>(avutil.resolve("av_cpu_force_count"));
        const auto count=reinterpret_cast<int(*)()>(avutil.resolve("av_cpu_count"));
        if(!force || !count){app.exit(14);return;}
        const int before=count();force(config.value("decoderCpus").toInt());
        qInfo()<<"PERF_DECODER_CPU_COUNT"<<before<<count();
    }
    if(config["ignoreUserInput"].toBool())app.installEventFilter(new AuditInputGuard(&app));
    const QString report=config["report"].toString();
    struct State{int next=0,frames=0,resolved=0,resolveErrors=0,downloadChanges=0,downloadRowChanges=0;double editorActionMs=0;QString stage;QElapsedTimer total,stageClock,frameClock;QVector<double> frameTimes;QMutex renderMutex;QPointer<QObject> lyricFixture;};
    auto state=std::make_shared<State>();state->total.start();state->frameClock.start();
    auto* downloads=qobject_cast<listenfree::qmlbridge::DownloadService*>(qmlEngine(shell)->rootContext()->contextProperty("backendDownloads").value<QObject*>());
    if(downloads){
        QObject::connect(downloads,&listenfree::qmlbridge::DownloadService::changed,&app,[state]{++state->downloadChanges;});
        if(auto* model=qobject_cast<QAbstractItemModel*>(downloads))
            QObject::connect(model,&QAbstractItemModel::dataChanged,&app,[state]{++state->downloadRowChanges;});
    }
    // Synthetic data crosses the same QML controller interface as normal previews.
    // This optional fixture measures UI ownership, not network/provider memory.
    if(config["lyricPreviewFixture"].toBool()){
        QQmlComponent fixture(qmlEngine(shell));
        fixture.setData(R"qml(import QtQuick
QtObject {
 property var lyricCandidates: []
 property var lyricMatchSources: []
 property var lyricPreviewLines: []
 property string lyricPreview: ""
 property bool lyricMatchBusy: false
 property string lyricMatchError: ""
 function cancelLyricMatch() { lyricMatchBusy=false }
 function releaseLyricMatch() { cancelLyricMatch();lyricCandidates=[];lyricMatchSources=[];lyricPreviewLines=[];lyricPreview="" }
 function previewLyricMatch(index) {}
})qml",QUrl());
        state->lyricFixture=fixture.create();
        if(!state->lyricFixture){qCritical()<<fixture.errors();app.exit(11);return;}
        state->lyricFixture->setParent(shell);
        shell->findChild<QObject*>("lyricsMatchPopup")->setProperty("controller",QVariant::fromValue(state->lyricFixture.data()));
    }
    QObject::connect(&sources,&listenfree::qmlbridge::SourceController::resolutionFinished,&app,
        [state](const QString&,const QString&,const QString& action,const QVariantMap&,const QString& error){
            if(action=="musicUrl"){if(error.isEmpty())++state->resolved;else ++state->resolveErrors;}
        });
    auto* timer=new QTimer(&app);timer->setSingleShot(true);
    QObject::connect(window,&QQuickWindow::afterRendering,&app,[state]{QMutexLocker lock(&state->renderMutex);++state->frames;state->frameTimes.append(state->frameClock.nsecsElapsed()/1e6);state->frameClock.restart();},Qt::DirectConnection);
    const auto snapshot=[&,window,shell,state,downloads,report,inspectObjects=config.value("inspectObjects").toBool(true)](QString label){
        QVector<double> frameTimes;int frames=0;
        {QMutexLocker lock(&state->renderMutex);frameTimes=state->frameTimes;frames=state->frames;}
        auto* page=auditItem(window->contentItem(),"nowPlayingPage");
        auto* stage=auditItem(window->contentItem(),"immersiveStage");
        auto* pv=auditItem(window->contentItem(),"immersivePv");
        auto* disc=auditItem(window->contentItem(),"immersiveDiscQueue");
        auto* editor=auditItem(window->contentItem(),"musicEditorDialog");
        const auto countItems=[](auto&& self,QQuickItem* item)->int{
            if(!item)return 0;
            int count=1;for(auto* child:item->childItems())count+=self(self,child);return count;
        };
        auto* matchPopup=shell->findChild<QObject*>("lyricsMatchPopup");
        auto* matchPreview=matchPopup?matchPopup->findChild<QQuickItem*>("lyricMatchPreview"):nullptr;
        auto* downloadPanel=auditItem(window->contentItem(),"downloadPanel");
        QQuickItem* downloadList=nullptr;
        if(downloadPanel)for(auto* child:downloadPanel->childItems())if(child->inherits("QQuickListView"))downloadList=child;
        QJsonObject row{{"stage",state->stage},{"label",label},{"elapsedMs",state->total.elapsed()},
            {"downloadsOpen",shell->property("downloadsOpen").toBool()},
            {"downloadItems",countItems(countItems,downloadPanel)},
            {"downloadViewRows",downloadList?downloadList->property("count").toInt():0},
            {"downloadContentY",downloadList?downloadList->property("contentY").toDouble():0},
            {"downloadChanges",state->downloadChanges},{"downloadRowChanges",state->downloadRowChanges},
            {"lyricMatchVisible",matchPopup && matchPopup->property("visible").toBool()},
            {"lyricPreviewItems",countItems(countItems,matchPreview)},
            {"lyricPreviewRows",state->lyricFixture?auditVariant(state->lyricFixture->property("lyricPreviewLines")).toList().size():player.lyricPreviewLines().size()},
            {"lyricPreviewCharacters",state->lyricFixture?state->lyricFixture->property("lyricPreview").toString().size():player.lyricPreview().size()},
            {"editorOpen",shell->property("musicEditorOpen").toBool()},
            {"editorControlsLoaded",editor && auditItem(editor,"musicEditorContent")!=nullptr},
            {"editorItems",countItems(countItems,editor)},{"editorActionMs",state->editorActionMs},
            {"windowExposed",window->isExposed()},{"windowVisible",window->isVisible()},{"width",window->width()},{"height",window->height()},{"dpr",window->devicePixelRatio()},
            {"playback",player.state()},{"positionMs",player.position()},{"durationMs",player.duration()},
            {"trackPath",player.currentTrack().value("localPath").toString()},
            {"trackTitle",player.currentTrack().value("title").toString()},
            {"trackId",player.currentTrackId()},{"trackSource",player.currentTrack().value("source").toString()},
            {"mediaFormat",player.mediaFormat()},{"searchResults",player.searchResults().size()},
            {"playbackError",!player.errorMessage().isEmpty()},{"queueCount",player.queueSongs().size()},
            {"sourceHostState",sources.hostState()},{"activeSource",sources.activeId()},
            {"musicUrlSucceeded",state->resolved},{"musicUrlErrors",state->resolveErrors},
            {"nativeLyricLines",player.lyrics().size()},{"catalogReady",player.ready()},
            {"catalogRows",player.songs().size()},{"catalogModelRows",player.tracksModel()->rowCount()},
            {"catalogAlbums",player.albums().size()},{"catalogArtists",player.artists().size()},
            {"collectionDetailRows",collections.detail().value("tracks").toList().size()},
            {"collectionDetailBusy",collections.detailBusy()},
            {"immersive",bool(stage)},{"serviceActive",service.active()},{"sampling",service.sampling()},
            {"videoPlayer",service.videoPlayer()!=nullptr || service.nativeVideoPlayer()!=nullptr},{"videoReady",service.videoReady()},
            {"videoError",service.error()},{"videoTitle",service.videoTitle()},
            {"biliAuthenticated",QCoreApplication::instance()->property("auditBiliAuthenticated").toBool()},
            {"candidates",service.candidates().size()},{"frameCount",frames},{"stageMs",state->stageClock.elapsed()}};
        // Full snapshots are confined to stage boundaries, never the periodic sampler.
        if(downloads && label=="end"){
            const auto tasks=downloads->tasks();row["downloadStoredRows"]=tasks.size();
            if(!tasks.isEmpty()){
                const auto first=tasks.first().toMap();row["downloadFirstState"]=first.value("state").toString();
                row["downloadFirstBytes"]=QJsonValue::fromVariant(first.value("received"));
            }
        }
        QJsonArray sourceStatus;
        for(const auto& value:sources.sources()){
            const auto entry=value.toMap();
            sourceStatus.append(QJsonObject{{"id",entry.value("id").toString()},{"hostReady",entry.value("hostReady").toBool()}});
        }
        row["sources"]=sourceStatus;
        if(page){row["lyricLines"]=auditVariant(page->property("lyrics")).toList().size();row["playerStyle"]=page->property("overflowStyle").toBool()?"overflow":"classic";}
        if(stage)for(const auto& key:{"pvStyle","backgroundMode","visualization","exposed"})row[key]=QJsonValue::fromVariant(stage->property(key));
        if(pv){row["lyricPosition"]=pv->property("renderPosition").toDouble();row["lyricIndex"]=pv->property("lineIndex").toInt();}
        if(disc){row["discSectors"]=disc->property("loadedSectorCount").toInt();row["discRows"]=disc->property("trackCount").toInt();}
        if(service.videoPlayer()){
            auto* video=service.videoPlayer();row["videoDuration"]=video->duration();row["videoPosition"]=video->position();row["videoState"]=video->playbackState();row["videoMediaStatus"]=video->mediaStatus();
            if(video->videoSink()){const auto frame=video->videoSink()->videoFrame();row["videoWidth"]=frame.width();row["videoHeight"]=frame.height();row["videoHandleType"]=int(frame.handleType());row["videoPixelFormat"]=int(frame.pixelFormat());row["videoFrameTimeMs"]=frame.startTime()/1000;}
        }
        if(auto* video=service.nativeVideoPlayer()) {
            row["nativeVideo"]=true;row["videoDuration"]=video->duration();row["videoPosition"]=video->position();
            row["videoQueuedFrames"]=video->queuedFrames();row["videoPresentedFrames"]=qint64(video->presentedFrames());
            if(service.videoSink()) {
                const auto frame=service.videoSink()->videoFrame();row["videoWidth"]=frame.width();row["videoHeight"]=frame.height();
                row["videoHandleType"]=int(frame.handleType());row["videoPixelFormat"]=int(frame.pixelFormat());
                row["videoFrameTimeMs"]=frame.startTime()/1000;
            }
        }
        if(inspectObjects) {
        QJsonObject counts,scopes;QJsonArray layers,textures;QSet<QObject*> visited;
        const auto scopeOf=[&](QQuickItem* item){for(auto* p=item;p;p=p->parentItem()){if(p==disc)return QString("disc");if(p==stage)return QString("immersive");if(p==page)return QString("nowplayingUnderlay");}return QString("shell");};
        const auto count=[&](QString key,QString scope){counts[key]=counts[key].toInt()+1;auto c=scopes[scope].toObject();c[key]=c[key].toInt()+1;scopes[scope]=c;};
        // Inspect already-created QObject layers; reading Item.layer on every
        // item would itself allocate layer objects and contaminate the result.
        const auto objects=[&](auto&& self,QObject* obj)->void{
            if(visited.contains(obj))return;visited.insert(obj);
            const QByteArray type=obj->metaObject()->className();auto* item=qobject_cast<QQuickItem*>(obj);
            auto* owner=item?item:qobject_cast<QQuickItem*>(obj->parent());QString scope=scopeOf(owner);
            if(item){count("items",scope);if(!item->isVisible())count("hiddenItems",scope);}
            if(type.startsWith("QQuickImage"))count("images",scope);
            if(obj->objectName()=="mosaicCoverImage"){
                count("mosaicImages",scope);
                if(obj->property("status").toInt()!=1)count("mosaicImagesNotReady",scope);
            }
            if(type.startsWith("QQuickText")){count("texts",scope);if(obj->property("renderType").toInt()==2)count("curveTexts",scope);}
            if(type.startsWith("QQuickMultiEffect")){
                count("multiEffects",scope);
                if(scope=="immersive" && obj->property("blurEnabled").toBool()
                    && obj->property("blur").toDouble()==0
                    && (!obj->property("shadowEnabled").toBool() || obj->property("shadowOpacity").toDouble()==0))
                    count("zeroContributionBlur",scope);
            }
            if(type.startsWith("QQuickShaderEffectSource")){
                count("shaderSources",scope);const auto size=obj->property("textureSize").toSize();
                textures.append(QJsonObject{{"scope",scope},{"name",obj->objectName()},{"w",size.width()},{"h",size.height()},
                    {"live",obj->property("live").toBool()},{"visible",item&&item->isVisible()},{"hasSource",obj->property("sourceItem").value<QObject*>()!=nullptr}});
            }
            if(item){
                const auto* priv=QQuickItemPrivate::get(item);
                auto* existingLayer=priv->extra.isAllocated()?priv->extra->layer:nullptr;
                if(existingLayer){
                auto* obj=existingLayer;
                auto* owner=item;
                count("layerObjects",scope);const bool enabled=obj->property("enabled").toBool();if(enabled)count("enabledLayers",scope);
                if(enabled&&owner){const auto size=obj->property("textureSize").toSize();layers.append(QJsonObject{{"scope",scope},{"ownerType",owner->metaObject()->className()},
                    {"ownerName",owner->objectName()},{"visible",owner->isVisible()},{"opacity",owner->opacity()},
                    {"itemW",owner->width()},{"itemH",owner->height()},{"textureW",size.width()},{"textureH",size.height()}});}
            }
            }
            for(auto* child:obj->children())self(self,child);
            if(item)for(auto* child:item->childItems())self(self,child);
        };objects(objects,window);
        row["counts"]=counts;row["scopes"]=scopes;row["layers"]=layers;row["shaderTextures"]=textures;
        QJsonArray pages, views, backgrounds;
        for(auto* obj:visited)if(obj->property("frontIsA").isValid() && obj->property("frontOpacity").isValid()){
            QJsonObject group{{"name",obj->objectName()},{"type",obj->metaObject()->className()},
                {"opacity",obj->property("frontOpacity").toDouble()}};QJsonArray layers;
            if(auto* item=qobject_cast<QQuickItem*>(obj))for(auto* child:item->childItems())if(child->property("artwork").isValid())
                layers.append(QJsonObject{{"source",child->property("artwork").toUrl().toString()},
                    {"ready",child->property("ready").toBool() || child->property("visualReady").toBool()},
                    {"items",child->childItems().size()}});
            group["layers"]=layers;backgrounds.append(group);
        }
        row["backgrounds"]=backgrounds;
        for(auto* obj:visited)if(obj->property("routeKey").isValid() && obj->inherits("QQuickLoader")){
            auto* item=obj->property("item").value<QObject*>();
            QJsonObject entry{{"route",obj->property("routeKey").toString()},{"loaded",bool(item)},
                {"visible",obj->property("visible").toBool()}};
            if(item)for(const auto* key:{"selectedAlbumIndex","allCharts","collectionTab","selectedCategory","selectedMode","selectedFilter"})
                if(item->property(key).isValid())entry[key]=QJsonValue::fromVariant(item->property(key));
            pages.append(entry);
        }
        row["navigationPages"]=pages;
        for(auto* obj:visited)if(auto* item=qobject_cast<QQuickItem*>(obj); item && item->isVisible()
            && (item->inherits("QQuickFlickable") || item->objectName()=="songTable")){
            QJsonObject view{{"name",item->objectName()},{"type",item->metaObject()->className()}};
            for(const auto* key:{"contentX","contentY","contentHeight","contentWidth","height","width","count","sortColumn","sortOrder"})
                if(item->property(key).isValid())view[key]=QJsonValue::fromVariant(item->property(key));
            views.append(view);
        }
        row["visibleViews"]=views;
        }
        if(!frameTimes.isEmpty())row["firstFrameMs"]=frameTimes.first();
        if(frameTimes.size()>10){auto times=frameTimes;std::sort(times.begin(),times.end());row["frameIntervalP50Ms"]=times[times.size()/2];row["frameIntervalP95Ms"]=times[qMin(times.size()-1,qsizetype(times.size()*.95))];row["frameIntervalP99Ms"]=times[qMin(times.size()-1,qsizetype(times.size()*.99))];row["frameIntervalMaxMs"]=times.last();}
        QFile f(report);if(f.open(QIODevice::ReadWrite)){const auto size=f.size();if(size>0){f.seek(size-2);f.write(",\n");}else f.write("[\n");f.write(QJsonDocument(row).toJson(QJsonDocument::Compact));f.write("\n]");}
    };
    auto* periodic=new QTimer(&app);periodic->setInterval(5000);
    QObject::connect(periodic,&QTimer::timeout,&app,[snapshot]{snapshot("sample");});
    QObject::connect(timer,&QTimer::timeout,&app,[&,window,shell,config,report,state,downloads,timer,periodic,snapshot]{
        if(!state->stage.isEmpty())snapshot("end");
        const auto steps=config["steps"].toArray();
        if(state->next>=steps.size()){
            periodic->stop();state->stage="finished";snapshot("finished");
            QFile marker(report+".stage");if(marker.open(QIODevice::WriteOnly))marker.write("finished");
            app.exit(0);return;
        }
        const auto step=steps[state->next++].toObject();state->stage=step["name"].toString();state->stageClock.restart();
        {QMutexLocker lock(&state->renderMutex);state->frames=0;state->frameTimes.clear();state->frameClock.restart();}
        QFile marker(report+".stage");if(marker.open(QIODevice::WriteOnly))marker.write(state->stage.toUtf8());
        qInfo().noquote()<<"PERF_STAGE"<<state->stage;
        auto* page=auditItem(window->contentItem(),"nowPlayingPage");auto* stage=auditItem(window->contentItem(),"immersiveStage");
        const QString action=step["action"].toString();
        if(step.contains("expectedCatalogRows") && (!player.ready() || player.songs().size()!=step["expectedCatalogRows"].toInt()
                || player.tracksModel()->rowCount()!=step["expectedCatalogRows"].toInt())){
            qCritical()<<"AUDIT workload mismatch: catalog"<<player.songs().size()<<"expected"<<step["expectedCatalogRows"].toInt();
            snapshot("workload-failed");app.exit(10);return;
        }
        if(step.contains("expectedLyricLines") && player.lyrics().size()!=step["expectedLyricLines"].toInt()){
            qCritical()<<"AUDIT workload mismatch: lyrics"<<player.lyrics().size()<<"expected"<<step["expectedLyricLines"].toInt();
            snapshot("workload-failed");app.exit(10);return;
        }
        if(action=="setup"){
            window->setFlag(Qt::WindowStaysOnTopHint,config["foreground"].toBool());window->showNormal();window->setPosition(80,60);window->raise();window->requestActivate();window->resize(config["width"].toInt(1066),config["height"].toInt(709));
            settings.setValue("nowPlaying.playerStyle","Classic");settings.setValue("immersive.lyricStyle","fume");settings.setValue("immersive.background","blur");settings.setValue("immersive.visualization","none");
            settings.setValue("appearance.dynamicArtworkEnabled",false);shell->setProperty("currentRoute","library/songs");
            // Opening a local track already starts playback. Calling play()
            // again during decoder startup can restart the same source.
            // This profile is an isolated copy. Start from a deterministic empty
            // queue instead of resuming the user's persisted decoder position.
            player.clearQueue();
            if(!config["url"].toString().isEmpty())player.openUrl(QUrl(config["url"].toString()));
            else if(!config["track"].toString().isEmpty())player.openLocal(config["track"].toString());
        }else if(action=="nowplaying"){
            shell->setProperty("animationsEnabled",false);shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.);shell->setProperty("coverMorphProgress",1.);shell->setProperty("animationsEnabled",true);
        }else if(action=="enter"){
            if(step.contains("style"))settings.setValue("immersive.lyricStyle",step["style"].toString());
            if(page)page->setProperty("immersiveActive",true);
        }else if(action=="leave"){if(page)page->setProperty("immersiveActive",false);}
        else if(action=="mini"){QMetaObject::invokeMethod(shell,"navigateBack");}
        else if(action=="style"){if(stage)stage->setProperty("pvStyle",step["value"].toString());}
        else if(action=="visual"){if(stage)stage->setProperty("visualization",step["value"].toString());}
        else if(action=="background"){
            if(stage){stage->setProperty("backgroundMode",step["value"].toString());QMetaObject::invokeMethod(stage,"cancelAutoMatch");}
            if(step.contains("video"))service.openLocalVideo(QUrl::fromLocalFile(step["video"].toString()));
        }else if(action=="pause"){player.pause();}
        else if(action=="play"){player.play();}
        else if(action=="queue"){
            QMetaObject::invokeMethod(shell,"openQueue",Q_ARG(QVariant,QVariant(true)));
            QTimer::singleShot(100,&app,[&,window]{if(auto* disc=auditItem(window->contentItem(),"immersiveDiscQueue")){
                disc->setProperty("sourceModel",QVariant::fromValue(static_cast<QObject*>(nullptr)));disc->setProperty("rows",player.songs());
                disc->setProperty("currentIndex",qMin(100,int(player.songs().size())-1));
            }});
        }else if(action=="queueScroll"){
            if(auto* disc=auditItem(window->contentItem(),"immersiveDiscQueue"))QMetaObject::invokeMethod(disc,"step",Q_ARG(QVariant,step["value"].toInt(10)));
        }else if(action=="queueClose"){QMetaObject::invokeMethod(shell,"closeQueue");}
        else if(action=="popup"){
            if(stage)if(auto* panel=stage->property(step["value"].toString()=="sources"?"sourcesPanel":"settingsPanel").value<QObject*>())QMetaObject::invokeMethod(panel,"open");
        }else if(action=="popupClose"){QMetaObject::invokeMethod(shell,"navigateBack");}
        else if(action=="resize"){window->showNormal();window->resize(step["width"].toInt(),step["height"].toInt());}
        else if(action=="fullscreen"){window->showFullScreen();}
        else if(action=="route"){shell->setProperty("currentRoute",step["value"].toString());}
        else if(action=="setting"){settings.setValue(step["key"].toString(),step["value"].toVariant());}
        else if(action=="track"){player.openLocal(step["value"].toString());player.pause();}
        else if(action=="source"){
            if(!sources.selectSource(step["value"].toString())){snapshot("source-selection-failed");app.exit(11);return;}
        }
        else if(action=="mvSearch"){service.searchMv(step["value"].toString(),"bili");}
        else if(action=="mvFrame"){service.setOffsetMs(step["position"].toInt()-int(player.position()));}
        else if(action=="mvSelect"){
            const int index=step["index"].toInt();
            if(index<0||index>=service.candidates().size()){snapshot("mv-candidate-missing");app.exit(13);return;}
            service.selectMv(index);
        }
        else if(action=="importSource"){
            if(!sources.importLocalFile(step["value"].toString())){snapshot("source-import-failed");app.exit(11);return;}
        }
        else if(action=="search"){player.search(step["value"].toString());}
        else if(action=="playResult"){
            const auto rows=player.searchResults();const int index=step["index"].toInt();
            if(index<0 || index>=rows.size() || !player.openTrack(rows[index].toMap())){snapshot("online-start-failed");app.exit(12);return;}
        }
        else if(action=="selectQueue"){
            if(!player.selectQueue(step["index"].toInt())){snapshot("queue-selection-failed");app.exit(12);return;}
        }
        else if(action=="compactHeap"){
#ifdef Q_OS_WIN
            struct { ULONG version=1,flags=0; } info;
            QElapsedTimer clock;clock.start();
            const bool ok=HeapSetInformation(nullptr,static_cast<HEAP_INFORMATION_CLASS>(3),&info,sizeof(info));
            qInfo()<<"PERF_HEAP_OPTIMIZE"<<ok<<"ms"<<clock.elapsed();
#endif
        }
        else if(action=="downloadPanel"){shell->setProperty("downloadsOpen",step["open"].toBool());}
        else if(action=="downloadAdd"){
            if(!downloads){app.exit(11);return;}
            settings.setValue("download.enabled",true);settings.setValue("download.embedContent.Lyrics",false);
            settings.setValue("download.embedContent.Artwork",false);settings.setValue("download.tryAlternateSource",false);
            settings.setValue("download.folder",QFileInfo(report).dir().filePath("audio"));
            downloads->add({QVariantMap{{"trackId","download-audit"},{"source","kw"},{"rid","1"},
                {"title",QStringLiteral("下载进度验证")},{"artist","Fixture Artist"}}});
        }
        else if(action=="downloadsPause"){if(downloads)downloads->pauseAll();}
        else if(action=="downloadsResume"){if(downloads){const auto tasks=downloads->tasks();if(!tasks.isEmpty())downloads->resume(tasks.first().toMap().value("id").toString());}}
        else if(action=="downloadsClear"){if(downloads)downloads->clearRecords();}
        else if(action=="stop"){player.stop();}
        else if(action=="releaseUi"){window->releaseResources();}
        else if(action=="collectQml"){if(auto* engine=qmlEngine(window))engine->collectGarbage();}
        else if(action=="clearQueue"){player.clearQueue();}
        else if(action=="collectionFixture"){
            QVariantList rows;
            const int count=step["count"].toInt(5000);
            for(int i=0;i<count;++i)rows.append(QVariantMap{{"trackId",QString("fixture:%1").arg(i)},
                {"source","fixture"},{"rid",QString::number(i)},
                {"title",QStringLiteral("内存验证歌曲 %1").arg(i)},
                {"artist",QStringLiteral("验证艺术家 %1").arg(i%50)},
                {"album",QStringLiteral("验证专辑 %1").arg(i/10)},
                {"durationMs",180000},{"duration","03:00"}});
            const QVariantMap card{{"id","memory-detail"},{"kind","Local"},{"title","内存验证歌单"},{"tracks",rows}};
            QMetaObject::invokeMethod(shell,"openOnlineCollection",Q_ARG(QVariant,QVariant(card)));
        }
        else if(action=="editor"){
            QElapsedTimer elapsed;elapsed.start();
            if(step.contains("track"))shell->setProperty("musicEditorTrack",step["track"].toObject().toVariantMap());
            shell->setProperty("musicEditorOpen",step["open"].toBool());
            state->editorActionMs=elapsed.nsecsElapsed()/1e6;
        }
        else if(action=="lyricPreview"){
            if(!state->lyricFixture){app.exit(11);return;}
            QVariantList lines;
            QString text;
            for(int i=0;i<step["count"].toInt(240);++i){
                const auto line=QStringLiteral("Preview line %1 — 测试歌词与多语言排版").arg(i+1);
                lines.append(QVariantMap{{"timeMs",i*2000},{"text",line+(i%4==0?QStringLiteral("，这一行包含更长的文字，用来验证窄窗口内的自动换行与行间距。"):QString{})},
                    {"translation",i%3==0?QStringLiteral("这是对应的翻译文本。"):QString{}},
                    {"romanization",i%5==0?QStringLiteral("zhe shi luo ma yin yu lan"):QString{}}});
                text+=QStringLiteral("[%1:%2.00]%3\n").arg(i*2/60,2,10,QChar('0')).arg(i*2%60,2,10,QChar('0')).arg(line);
            }
            state->lyricFixture->setProperty("lyricCandidates",QVariantList{QVariantMap{{"key","fixture:0"},{"title","Preview fixture"},{"artist","Test Artist"},{"score",100},{"sourceLabel","Fixture"},{"lyricSource","fixture"}}});
            state->lyricFixture->setProperty("lyricPreview",text);
            state->lyricFixture->setProperty("lyricPreviewLines",lines);
            auto* popup=shell->findChild<QObject*>("lyricsMatchPopup");
            popup->setProperty("selectedKey","fixture:0");
            QMetaObject::invokeMethod(popup,"open");
        }
        else if(action=="lyricPreviewClose"){QMetaObject::invokeMethod(shell->findChild<QObject*>("lyricsMatchPopup"),"close");}
        else if(action=="closeCollection"){QMetaObject::invokeMethod(shell,"closeCollection");}
        else if(action=="collection"){
            QMetaObject::invokeMethod(shell,"openCollection",Q_ARG(QVariant,step["kind"].toString()),
                Q_ARG(QVariant,step["value"].toString()),Q_ARG(QVariant,QColor("#608070")));
        }
        else if(action=="click"){
            QList<QQuickItem*> matches;
            const auto collect=[&](auto&& self,QQuickItem* item)->void{
                if(item->isVisible() && item->objectName()==step["nameOfItem"].toString())matches.append(item);
                for(auto* child:item->childItems())self(self,child);
            };collect(collect,window->contentItem());
            const int index=step["index"].toInt();
            if(index<0 || index>=matches.size()){qWarning()<<"AUDIT click target missing"<<step;app.exit(8);return;}
            auto* target=matches[index];const auto point=target->mapToScene(QPointF(target->width()/2,target->height()*.3));
            for(auto type:{QEvent::MouseButtonPress,QEvent::MouseButtonRelease}){
                QMouseEvent event(type,point,point,window->mapToGlobal(point.toPoint()),Qt::LeftButton,
                    type==QEvent::MouseButtonPress?Qt::LeftButton:Qt::NoButton,Qt::NoModifier);
                QCoreApplication::sendEvent(window,&event);
            }
        }
        if(step.contains("mutations"))QTimer::singleShot(700,&app,[window,step]{
            for(const auto value:step["mutations"].toArray()){
                const auto m=value.toObject();auto* root=window->contentItem();
                if(m.contains("within"))root=auditVisibleItem(root,m["within"].toString());
                if(!root){qWarning()<<"AUDIT missing parent"<<m;continue;}
                auto* item=auditVisibleItem(root,m["name"].toString(),m["type"].toString().toLatin1());
                if(!item){qWarning()<<"AUDIT missing item"<<m;continue;}
                if(m.contains("method"))QMetaObject::invokeMethod(item,m["method"].toString().toLatin1().constData(),Q_ARG(QVariant,m["value"].toVariant()));
                else QQmlProperty::write(item,m["property"].toString(),m["value"].toVariant());
            }
        });
        if(step.contains("seek")){
            if(action=="setup")QTimer::singleShot(1000,&app,[&player,step]{player.seek(step["seek"].toInt());});
            else player.seek(step["seek"].toInt());
        }
        if(step.contains("freezeLyric"))QTimer::singleShot(500,&app,[window,step]{
            if(auto* pv=auditItem(window->contentItem(),"immersivePv")){
                QQmlProperty::write(pv,"playing",false);
                QQmlProperty::write(pv,"positionMs",step["freezeLyric"].toDouble());
            }
        });
        QTimer::singleShot(1500,&app,[snapshot]{snapshot("settled-start");});
        for(const QJsonValue delay:step["captureEarly"].toArray()){
            const int delayMs=delay.toInt();
            QTimer::singleShot(delayMs,&app,[window,report,name=state->stage,delayMs,snapshot]{
                snapshot("early-"+QString::number(delayMs));window->grabWindow().save(report+"."+name+"."+QString::number(delayMs)+"ms.png");
            });
        }
        if(step["capture"].toBool())QTimer::singleShot(2500,&app,[window,report,name=state->stage]{window->grabWindow().save(report+"."+name+".png");});
        if(step["captureVideo"].toBool())QTimer::singleShot(2600,&app,[&service,report,name=state->stage]{
            if(service.videoSink())service.videoSink()->videoFrame().toImage().save(report+"."+name+".video.png");
        });
        if(step["compareEffects"].toBool())QTimer::singleShot(2800,&app,[window,report,name=state->stage]{
            QList<QQuickItem*> focused;
            const auto collect=[&](auto&& self,QQuickItem* item)->void{
                if(item->objectName()=="foliaGlyphBody" && item->property("focusSettled").toBool())focused.append(item);
                for(auto* child:item->childItems())self(self,child);
            };collect(collect,window->contentItem());
            const auto optimized=window->grabWindow().convertToFormat(QImage::Format_ARGB32);
            for(auto* glyph:focused)glyph->setProperty("focusSettled",false);
            const auto original=window->grabWindow().convertToFormat(QImage::Format_ARGB32);
            int maximum=0;quint64 difference=0,changed=0;
            for(int y=0;y<original.height();++y)for(int x=0;x<original.width();++x){
                const auto a=original.pixel(x,y),b=optimized.pixel(x,y);bool pixelChanged=false;
                for(int shift:{0,8,16}){const int delta=std::abs(int((a>>shift)&255)-int((b>>shift)&255));maximum=qMax(maximum,delta);difference+=delta;pixelChanged|=delta>0;}
                changed+=pixelChanged;
            }
            original.save(report+"."+name+".original-effect.png");optimized.save(report+"."+name+".optimized-effect.png");
            QJsonObject result{{"focusedGlyphs",focused.size()},{"maximumChannelDifference",maximum},{"changedPixels",qint64(changed)},
                {"meanChannelDifference",double(difference)/(original.width()*original.height()*3.)}};
            QFile file(report+"."+name+".pixels.json");if(file.open(QIODevice::WriteOnly))file.write(QJsonDocument(result).toJson());
            for(auto* glyph:focused)glyph->setProperty("focusSettled",true);
        });
        timer->start(step["ms"].toInt(15000));periodic->start();
    });
    if(config["renderReadbackMs"].toInt()>0){auto* redraw=new QTimer(&app);redraw->setInterval(config["renderReadbackMs"].toInt());QObject::connect(redraw,&QTimer::timeout,window,[window]{const auto image=window->grabWindow();});redraw->start();}
    timer->start(0);
}
