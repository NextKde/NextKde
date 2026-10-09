#pragma once
#include <windows.h>
#include <psapi.h>
#include <QQmlProperty>
inline double immersivePrivateMiB() {
    PROCESS_MEMORY_COUNTERS_EX counters{};
    using ReadMemory = BOOL(WINAPI*)(HANDLE, PPROCESS_MEMORY_COUNTERS, DWORD);
    const auto read = reinterpret_cast<ReadMemory>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "K32GetProcessMemoryInfo"));
    if (!read || !read(GetCurrentProcess(), reinterpret_cast<PPROCESS_MEMORY_COUNTERS>(&counters), sizeof(counters))) return -1;
    return double(counters.PrivateUsage) / 1048576.;
}
inline void runImmersiveRegression(QApplication& app, QQuickWindow* window, QObject* shell,
    listenfree::qmlbridge::ImmersiveController& service, listenfree::qmlbridge::SettingsController& settings, const QString& report) {
    struct State { int phase=0,style=0,waitFrames=0; QJsonObject checks,memory; double clock=0,camera=0,cameraY=0; };
    auto state=std::make_shared<State>();auto* timer=new QTimer(&app);timer->setInterval(600);
    QObject::connect(timer,&QTimer::timeout,&app,[&,window,shell,report,state,timer]{
        const auto item=[&](const QString& name){return uiItem(window->contentItem(),name);};
        const auto capture=[&](const QString& name){window->grabWindow().save(report+"."+name+".png");};
        auto* page=item("nowPlayingPage");auto* stage=item("immersiveStage");auto* pv=item("immersivePv");
        auto* panel=stage?stage->property("settingsPanel").value<QObject*>():nullptr;
        auto* sources=stage?stage->property("sourcesPanel").value<QObject*>():nullptr;
        const auto finish=[&]{timer->stop();bool pass=true;for(const auto& value:state->checks)pass &=value.toBool();state->checks["passed"]=pass;state->checks["privateMiB"]=state->memory;QFile file(report);if(file.open(QIODevice::WriteOnly))file.write(QJsonDocument(state->checks).toJson());app.exit(pass?0:7);};
        const bool orbitOnly=qEnvironmentVariableIsSet("LISTENFREE_CLADDAGH_REGRESSION");
        switch(state->phase++) {
        case 0:
            window->showNormal();window->resize(1440,900);window->requestActivate();
            settings.setValue("nowPlaying.playerStyle","Classic");settings.setValue("immersive.lyricStyle","fume");settings.setValue("immersive.background","blur");settings.setValue("immersive.visualization","none");
            if(orbitOnly)settings.setValue("immersive.lyricStyle","claddagh");
            shell->setProperty("animationsEnabled",false);shell->setProperty("nowPlayingOpen",true);shell->setProperty("morphProgress",1.);shell->setProperty("coverMorphProgress",1.);return;
        case 1:{
            if(!page){state->checks["page_loaded"]=false;finish();return;}
            page->setProperty("trackTitle",QStringLiteral("One Last Kiss"));page->setProperty("trackArtist",QStringLiteral("原生浮名 · 镜头与逐字打印"));
            const QStringList texts={QStringLiteral("第一次去到卢浮宫时"),QStringLiteral("并没有感觉有多惊讶"),QStringLiteral("因为只属于我的蒙娜丽莎"),QStringLiteral("早在很久以前我就已遇见"),QStringLiteral("第一次见到你的那一天"),QStringLiteral("齿轮开始转动"),QStringLiteral("无法阻止失去的预感"),QStringLiteral("但已经有很多东西无法忘怀"),QStringLiteral("即使年龄不断增长"),QStringLiteral("oh~oh~oh~oh"),QStringLiteral("你能再给我最后一吻吗"),QStringLiteral("不想忘记的事情"),QStringLiteral("你的身影已经烙印在我心间"),QStringLiteral("One Last Kiss"),QStringLiteral("让时间停在这一瞬间"),QStringLiteral("我们的故事还没有结束")};
            QVariantList lines;
            for(int i=0;i<texts.size();i++){QVariantList words;for(int j=0;j<texts[i].size();j++)words.append(QVariantMap{{"text",texts[i].mid(j,1)},{"startMs",i*5000+j*250},{"endMs",i*5000+(j+1)*250}});lines.append(QVariantMap{{"text",texts[i]},{"timeMs",i*5000},{"words",words}});}
            page->setProperty("lyrics",lines);page->setProperty("artworkSource",QUrl("qrc:/qt/qml/ListenFree/Bootstrap/music_player_desktop/assets/album_Cover_2@2x.png"));
            if(orbitOnly){
                for(const auto& name:QStringList{"red","blue"}){QImage cover(192,192,QImage::Format_RGB32);
                    for(int y=0;y<192;++y)for(int x=0;x<192;++x){const qreal value=.24+.52*(.5+.5*std::sin(x*.052+y*.02));cover.setPixelColor(x,y,QColor::fromHsvF(name=="red"?.985:.62,.78,value));}
                    cover.save(report+"."+name+"-cover.png");}
                page->setProperty("artworkSource",QUrl::fromLocalFile(report+".red-cover.png"));
                page->setProperty("trackTitle","AIZO");page->setProperty("trackArtist","King Gnu · 回环渲染回归");
            }
            page->setProperty("positionMs",41200.);page->setProperty("playing",false);page->setProperty("reducedMotion",false);return;}
        case 2:state->memory["classicBaseline"]=immersivePrivateMiB();QMetaObject::invokeMethod(page,"toggleImmersive");return;
        case 3:
            state->checks["native_stage_loaded"]=stage&&pv&&service.active();if(!stage||!pv){finish();return;}
            state->checks["classic_setting_preserved"]=!page->property("overflowStyle").toBool();
            state->checks["full_screen_pv"]=qAbs(pv->width()-page->width())<1&&qAbs(pv->height()-page->height())<1;
            state->checks["normal_lyrics_hidden"]=!item("nowPlayingLyricsRegion")->isVisible();
            if(orbitOnly){stage->setProperty("controlsOpen",false);state->phase=70;return;}
            state->checks["fume_timed_line_selected"]=pv->property("lineIndex").toInt()==8;
            state->clock=pv->property("renderPosition").toDouble();state->camera=pv->property("cameraX").toDouble();state->cameraY=pv->property("cameraY").toDouble();
            state->checks["initial_camera_targets_current_block"]=qAbs(state->camera-pv->property("targetX").toDouble())<1&&qAbs(state->cameraY-pv->property("targetY").toDouble())<1;
            state->memory["fume"]=immersivePrivateMiB();capture("fume-print");return;
        case 4:
            state->checks["pause_freezes_camera_and_print"]=pv->property("renderPosition").toDouble()==state->clock&&pv->property("cameraX").toDouble()==state->camera;
            page->setProperty("positionMs",53500.);return;
        case 5:
            state->checks["seek_retargets_article"]=pv->property("lineIndex").toInt()==10 && (pv->property("cameraX").toDouble()!=state->camera || pv->property("cameraY").toDouble()!=state->cameraY);
            capture("fume-seek");page->setProperty("positionMs",54920.);page->setProperty("playing",true);state->phase=40;return;
        case 40:
            if(pv->property("lineIndex").toInt()!=11&&state->waitFrames++<8){window->grabWindow();state->phase=40;return;}
            state->waitFrames=0;
            state->checks["natural_clock_crosses_line"]=pv->property("lineIndex").toInt()==11;
            capture("fume-motion");page->setProperty("playing",false);stage->setProperty("visualization","none");stage->setProperty("controlsOpen",false);state->phase=50;return;
        case 50:{
            const QStringList styles={"classic","cadenza","partita","cappella","tilt","claddagh","diorama","monet","pendolo","sonnet","tempera","still"};
            if(state->style>=styles.size()){stage->setProperty("pvStyle","fume");stage->setProperty("visualization","ambient");if(panel)QMetaObject::invokeMethod(panel,"open");state->phase=6;return;}
            stage->setProperty("pvStyle",styles[state->style]);page->setProperty("positionMs",41200.);state->phase=51;return;}
        case 51:{
            const QString style=stage->property("pvStyle").toString();
            auto* native=qobject_cast<FoliaScene*>(item("foliaNativeScene"));
            state->checks[style+"_native_loaded"]=native&&native->lineIndex()==8;
            state->memory[style]=immersivePrivateMiB();capture("style-"+style);
            page->setProperty("positionMs",43100.);state->phase=52;return;}
        case 52:
            capture("style-"+stage->property("pvStyle").toString()+"-later");state->style++;state->phase=50;return;
        case 6:
            state->checks["settings_three_sections"]=panel&&panel->property("visible").toBool()&&item("immersiveSettingsTabs");capture("settings-lyrics");if(panel)panel->setProperty("tab",1);return;
        case 7:capture("settings-visual");if(panel)panel->setProperty("tab",2);return;
        case 8:capture("settings-background");QMetaObject::invokeMethod(shell,"navigateBack");return;
        case 9:
            state->checks["back_closes_modal_first"]=panel&&!panel->property("visible").toBool()&&page->property("immersiveActive").toBool();
            if(sources)QMetaObject::invokeMethod(sources,"open");return;
        case 10:
            state->checks["source_vertical_tabs"]=sources&&sources->property("visible").toBool()&&item("immersiveSourceTabs");capture("sources-mv");if(sources)sources->setProperty("tab",1);return;
        case 11:capture("sources-lyrics");if(sources)QMetaObject::invokeMethod(sources,"close");stage->setProperty("visualization","spectrum");stage->setProperty("controlsOpen",true);
            if(auto* spectrum=item("immersiveSpectrum")){QVariantList bands;for(int i=0;i<32;i++)bands.append(.15+.7*std::pow(std::sin(i*.38),2));spectrum->setProperty("bands",bands);}return;
        case 12:{
            auto* bar=item("immersiveProgress");auto* spectrum=item("immersiveSpectrum");
            state->checks["progress_flush_bottom"]=bar&&qAbs(bar->mapToScene({0,bar->height()}).y()-page->mapToScene({0,page->height()}).y())<1;
            state->checks["spectrum_flush_bottom"]=spectrum&&qAbs(spectrum->mapToScene({0,spectrum->height()}).y()-page->mapToScene({0,page->height()}).y())<1;
            capture("bottom-controls");stage->setProperty("visualization","ambient");if(auto* ambient=item("immersiveAmbient"))ambient->setProperty("bands",QVariant::fromValue(QVector3D(1,.7,.8)));state->phase=60;return;}
        case 60:capture("ambient-peak");QMetaObject::invokeMethod(shell,"openQueue",Q_ARG(QVariant,QVariant(true)));state->phase=13;return;
        case 13:
            state->checks["immersive_queue_uses_left"]=!shell->property("queueFromOverflow").toBool();capture("left-queue");shell->setProperty("queueOpen",false);
            stage->setProperty("backgroundMode","mv");QMetaObject::invokeMethod(stage,"cancelAutoMatch");service.openLocalVideo(QUrl::fromLocalFile("Z:/missing.mp4"));return;
        case 14:
            state->checks["mv_failure_preserves_cover_and_pv"]=!service.videoReady()&&!service.error().isEmpty()&&pv&&item("immersiveBackground")->isVisible();
            stage->setProperty("backgroundMode","blur");QMetaObject::invokeMethod(page,"toggleFullScreen");return;
        case 15:
            state->checks["fullscreen_available"]=window->visibility()==QWindow::FullScreen;
            QMetaObject::invokeMethod(shell,"navigateBack");return;
        case 16:
            state->checks["back_returns_to_nowplaying"]=page&&!page->property("immersiveActive").toBool()&&shell->property("nowPlayingOpen").toBool();
            state->checks["exit_releases_service"]=!stage&&!service.active()&&!service.sampling()&&!service.videoPlayer();
            state->checks["exit_restores_window"]=window->visibility()==QWindow::Windowed;
            state->memory["afterExit"]=immersivePrivateMiB();QMetaObject::invokeMethod(shell,"navigateBack");return;
        case 17:state->checks["second_back_returns_to_miniplayer"]=!shell->property("nowPlayingOpen").toBool();finish();return;
        case 70:{
            auto* native=qobject_cast<FoliaScene*>(item("foliaNativeScene"));
            // Hidden/occluded Windows tests do not continuously render. Pump a
            // frame and let the asynchronous image readback finish before the
            // assertion, with a finite deadline (never substitute a test tint).
            if(native&&native->accentColor().redF()<=native->accentColor().greenF()*2&&state->waitFrames++<8){window->grabWindow();state->phase=70;return;}
            state->waitFrames=0;
            state->checks["cover_automatically_supplies_red"]=native&&native->accentColor().redF()>native->accentColor().greenF()*2;
            auto* body=item("foliaGlyphBody");
            state->checks["sharp_body_is_unlayered_curve"]=body&&body->property("renderType").toInt()==2&&!QQmlProperty(body,"layer.enabled").read().toBool();
            if(native){const auto past=native->pose({{"line",8},{"glyph",4}}).color,future=native->pose({{"line",8},{"glyph",7}}).color;
                state->checks["past_tinted_future_translucent"]=past.redF()>past.greenF()*2&&future.alphaF()<past.alphaF();}
            state->memory["orbit"]=immersivePrivateMiB();capture("red-before");page->setProperty("positionMs",41900.);return;}
        case 71:capture("red-after");page->setProperty("reducedMotion",true);return;
        case 72:capture("reduced-motion");page->setProperty("reducedMotion",false);page->setProperty("artworkSource",QUrl::fromLocalFile(report+".blue-cover.png"));return;
        case 73:{
            auto* native=qobject_cast<FoliaScene*>(item("foliaNativeScene"));
            if(native&&native->accentColor().blueF()<=native->accentColor().redF()*2&&state->waitFrames++<8){window->grabWindow();state->phase=73;return;}
            state->checks["cover_switch_updates_blue"]=native&&native->accentColor().blueF()>native->accentColor().redF()*2;
            capture("blue");page->setProperty("artworkSource",QUrl::fromLocalFile(report+".red-cover.png"));
            // An old GPU readback must not win over a newer cover/reset.
            if(native)native->sampleArtwork(item("foliaAccentSample"));
            page->setProperty("artworkSource",QUrl::fromLocalFile(report+".missing-cover.png"));return;}
        case 74:{
            auto* native=qobject_cast<FoliaScene*>(item("foliaNativeScene"));
            state->checks["failed_cover_clears_stale_accent"]=native&&native->accentColor()==QColor("#ddd9d3");
            page->setProperty("artworkSource",QUrl::fromLocalFile(report+".red-cover.png"));window->resize(1000,700);return;}
        case 75:capture("small-window");QMetaObject::invokeMethod(shell,"navigateBack");return;
        case 76:state->checks["exit_returns_to_nowplaying"]=!page->property("immersiveActive").toBool();finish();return;
        }
    });timer->start();
}
