#include <QApplication>
#include <QTest>
#include <QSignalSpy>
#include <QQuickWindow>
#include <QSGTexture>
#include <QRunnable>
#include <QTcpServer>
#include <QTcpSocket>
#include <QBuffer>
#include <QRandomGenerator>
#include <QQmlEngine>
#include <QQmlContext>
#include <QQmlComponent>
#include <QQuickItem>
#include <QQuickItemGrabResult>
#include <QTemporaryDir>
#include <QDir>
#include <QFile>
#include "qmlbridge/artwork_texture_factory.h"
#include "qmlbridge/remote_artwork_provider.h"
#include "qmlbridge/list_models.h"
#include "qmlbridge/controllers.h"
#include "qmlbridge/wallpaper_library.h"
#include <QJsonDocument>
#include <QJsonObject>
#include "media/artwork_video.h"

class ResourceOwnershipTests : public QObject {
    Q_OBJECT
private Q_SLOTS:
    void wallpaperLibraryDiscoveryAndPicker() {
        using listenfree::qmlbridge::WallpaperLibrary;
        QTemporaryDir temporary;QVERIFY(temporary.isValid());
        const auto steam=temporary.filePath("Steam");const auto second=temporary.filePath(QString::fromUtf8("其他 Steam 库"));
        const auto library=second+"/steamapps/workshop/content/431960";
        QVERIFY(QDir().mkpath(steam+"/steamapps"));QVERIFY(QDir().mkpath(library));
        QFile vdf(steam+"/steamapps/libraryfolders.vdf");QVERIFY(vdf.open(QIODevice::WriteOnly));
        auto escaped=QDir::toNativeSeparators(second);escaped.replace("\\","\\\\");
        vdf.write(("\"libraryfolders\"\n{\n\"0\"\n{\n\"path\" \""+escaped+"\"\n}\n\"1\" \""+escaped+"\"\n}\n").toUtf8());vdf.close();
        for(const auto* name:{"video", "scene", "web", "missing"}) {
            const auto directory=library+'/'+name;QVERIFY(QDir().mkpath(directory));
            if(QString(name)!="missing")QVERIFY(QFile::copy(QStringLiteral(LISTENFREE_TEST_SOURCE_DIR "/tests/fixtures/artwork-red-blue.mp4"),directory+"/wall.mp4"));
            QImage preview(80,45,QImage::Format_RGB32);preview.fill(Qt::blue);QVERIFY(preview.save(directory+"/preview.png"));
            QFile file(directory+"/project.json");QVERIFY(file.open(QIODevice::WriteOnly));
            file.write(QJsonDocument(QJsonObject{{"title",QString::fromUtf8("蓝色测试壁纸")},{"type",QString(name)=="video"||QString(name)=="missing"?"Video":name},{"file","wall.mp4"},{"preview","preview.png"}}).toJson());
        }
        auto cancelled=std::make_shared<std::atomic_bool>(false);
        const auto result=WallpaperLibrary::discover({steam,steam},library,cancelled);
        QCOMPARE(result.items.size(),1);QCOMPARE(result.skipped,3);QCOMPARE(result.roots.size(),1);
        QVERIFY(!result.items[0].toMap().value("preview").toUrl().isEmpty());
        QCOMPARE(WallpaperLibrary::discover({},library+"/video",cancelled).items.size(),1);
        *cancelled=true;QVERIFY(WallpaperLibrary::discover({steam},{},cancelled).items.isEmpty());
        WallpaperLibrary service(nullptr,{steam});
        service.scan();service.cancel();service.scan();
        QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),8000);QCOMPARE(service.items().size(),1);

        const auto components=temporary.filePath("components");QVERIFY(QDir().mkpath(components));
        for(const auto* name:{"WallpaperPickerPopup","AppTheme","UiButton","RoundIconButton","IconGlyph","GlassSurface"})
            QVERIFY(QFile::copy(QStringLiteral(LISTENFREE_TEST_SOURCE_DIR "/music_player_desktop/components/")+name+".qml",components+"/"+name+".qml"));
        QFile module(components+"/qmldir");QVERIFY(module.open(QIODevice::WriteOnly));
        module.write("singleton AppTheme 1.0 AppTheme.qml\n");module.close();
        listenfree::qmlbridge::SettingsController settings;
        QQmlEngine engine;engine.rootContext()->setContextProperty("testLibrary",&service);engine.rootContext()->setContextProperty("testSettings",&settings);
        QQmlComponent component(&engine);
        component.setData("import QtQuick\nimport QtQuick.Controls.Basic\nimport \"components\"\nApplicationWindow { visible: true; width: 800; height: 640; WallpaperPickerPopup { objectName: \"picker\"; service: testLibrary; settingsStore: testSettings } }",QUrl::fromLocalFile(temporary.filePath("Test.qml")));
        std::unique_ptr<QObject> root(component.create());QVERIFY2(root,qPrintable(component.errorString()));
        auto* window=qobject_cast<QQuickWindow*>(root.get());QVERIFY(window);QVERIFY(QTest::qWaitForWindowExposed(window));
        auto* popup=root->findChild<QObject*>("picker");QVERIFY(popup);QSignalSpy selected(popup,SIGNAL(wallpaperSelected(QUrl)));
        QVERIFY(selected.isValid());QVERIFY(QMetaObject::invokeMethod(popup,"open"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.busy() && service.items().size()==1,8000);
        auto* content=popup->property("contentItem").value<QQuickItem*>();QVERIFY(content);
        auto* search=content->findChild<QObject*>("wallpaperSearch");auto* grid=content->findChild<QObject*>("wallpaperGrid");QVERIFY(search);QVERIFY(grid);
        search->setProperty("text","no match");QTRY_COMPARE(grid->property("count").toInt(),0);
        search->setProperty("text",QString::fromUtf8("蓝色"));QTRY_COMPARE(grid->property("count").toInt(),1);
        const auto findCard=[&](auto&& self,QQuickItem* item)->QQuickItem* {
            if(item->objectName()=="wallpaperCard")return item;
            for(auto* child:item->childItems())if(auto* found=self(self,child))return found;
            return nullptr;
        };
        QQuickItem* card=nullptr;QTRY_VERIFY((card=findCard(findCard,content))!=nullptr);
        QTest::qWait(250);
        QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,card->mapToScene({card->width()/2,card->height()/2}).toPoint());
        QTRY_COMPARE(selected.size(),1);
        QCOMPARE(selected[0][0].toUrl(),result.items[0].toMap().value("project").toUrl());
        QTRY_VERIFY(!popup->property("visible").toBool());QTRY_VERIFY(service.items().isEmpty());
    }
    void localWallpaperResolution() {
        QTemporaryDir directory; QVERIFY(directory.isValid());
        listenfree::qmlbridge::SettingsController settings;
        const auto video=directory.filePath(QString::fromUtf8("背景 space #1.mp4"));
        QVERIFY(QFile::copy(QStringLiteral(LISTENFREE_TEST_SOURCE_DIR "/tests/fixtures/artwork-red-blue.mp4"),video));
        const auto project=directory.filePath("project.json");
        const auto writeProject=[&](const QByteArray& bytes) {
            QFile file(project); if(!file.open(QIODevice::WriteOnly))return false;
            return file.write(bytes)==bytes.size();
        };
        const auto resolve=[&]{return settings.resolveBackground(QUrl::fromLocalFile(project),true);};
        QVERIFY(writeProject(QJsonDocument(QJsonObject{{"type","video"},{"file",QFileInfo(video).fileName()}}).toJson()));
        QCOMPARE(resolve().value("kind").toString(),QString("Video"));
        QCOMPARE(resolve().value("source").toUrl(),QUrl::fromLocalFile(video));
        QCOMPARE(settings.localFilePath(QUrl::fromLocalFile(video)),QDir::toNativeSeparators(video));
        QCOMPARE(settings.resolveBackground(QUrl::fromLocalFile(video),false).value("kind").toString(),QString("Video"));
        for(const auto& bytes:{QByteArray("not json"),QByteArray("[]"),
            QByteArray("{\"type\":\"scene\",\"file\":\"scene.pkg\"}"),
            QByteArray("{\"type\":\"web\",\"file\":\"index.html\"}"),
            QByteArray("{\"type\":\"video\",\"file\":\"missing.mp4\"}"),
            QByteArray("{\"type\":\"video\",\"file\":\"https://example.com/video.mp4\"}"),
            QByteArray("{\"type\":\"video\",\"file\":\"../outside.mp4\"}")}) {
            QVERIFY(writeProject(bytes)); QVERIFY(!resolve().value("error").toString().isEmpty());
        }
        QImage image(8,8,QImage::Format_RGB32);image.fill(Qt::green);
        QVERIFY(image.save(directory.filePath("wall.png")));
        QVERIFY(writeProject("{\"type\":\"image\",\"file\":\"wall.png\"}"));
        QCOMPARE(resolve().value("kind").toString(),QString("Image"));
        QVERIFY(writeProject(QByteArray(1024*1024+1,' ')));QVERIFY(!resolve().value("error").toString().isEmpty());
        QVERIFY(!settings.resolveBackground(QUrl("https://example.com/project.json"),true).value("error").toString().isEmpty());
        QVERIFY(settings.resolveBackground({},true).isEmpty());
    }
    void localVideoBackgroundLifecycle() {
        QTemporaryDir temporary;QVERIFY(temporary.isValid());
        const auto fixture=temporary.filePath("components");QVERIFY(QDir().mkpath(fixture));
        for(const auto* name:{"GlobalBackground","ArtworkBackground","AppTheme"})
            QVERIFY(QFile::copy(QStringLiteral(LISTENFREE_TEST_SOURCE_DIR "/music_player_desktop/components/")+name+".qml",fixture+"/"+name+".qml"));
        QFile module(fixture+"/qmldir");QVERIFY(module.open(QIODevice::WriteOnly));
        module.write("singleton AppTheme 1.0 AppTheme.qml\nGlobalBackground 1.0 GlobalBackground.qml\nArtworkBackground 1.0 ArtworkBackground.qml\n");module.close();
        const auto assets=temporary.filePath("assets");QVERIFY(QDir().mkpath(assets));
        QVERIFY(QFile::copy(QStringLiteral(LISTENFREE_TEST_SOURCE_DIR "/music_player_desktop/assets/background-grain.svg"),assets+"/background-grain.svg"));
        listenfree::qmlbridge::SettingsController settings;
        settings.setValue("background.type","Video");settings.setValue("background.blur",0);
        const QUrl source=QUrl::fromLocalFile(QStringLiteral(LISTENFREE_TEST_SOURCE_DIR "/tests/fixtures/artwork-red-blue.mp4"));
        settings.setValue("background.video",source.toString());
        listenfree::media::ArtworkVideoFactory factory;
        QQmlEngine engine;engine.rootContext()->setContextProperty("backendArtworkVideoFactory",&factory);
        QQmlComponent component(&engine,QUrl::fromLocalFile(fixture+"/GlobalBackground.qml"));
        std::unique_ptr<QObject> root(component.createWithInitialProperties({{"settingsStore",QVariant::fromValue(&settings)}}));
        QVERIFY2(root,qPrintable(component.errorString()));
        auto* item=qobject_cast<QQuickItem*>(root.get());QVERIFY(item);
        QQuickWindow window;window.resize(200,120);item->setParentItem(window.contentItem());item->setSize({200,120});
        window.show();QVERIFY(QTest::qWaitForWindowExposed(&window));
        QTRY_VERIFY(item->findChild<listenfree::media::ArtworkVideo*>());
        QPointer<listenfree::media::ArtworkVideo> movie=item->findChild<listenfree::media::ArtworkVideo*>();
        QTRY_VERIFY_WITH_TIMEOUT(movie->ready(),8000);QVERIFY(movie->playing());QVERIFY(movie->bounded());
        QSignalSpy loops(movie,&listenfree::media::ArtworkVideo::looped);
        QTRY_VERIFY_WITH_TIMEOUT(!loops.isEmpty(),5000);
        const auto grab=item->grabToImage();QSignalSpy grabReady(grab.get(),&QQuickItemGrabResult::ready);
        if(grabReady.isEmpty())QVERIFY(grabReady.wait(3000));
        const auto pixel=grab->image().pixelColor(100,60);
        QVERIFY2(pixel.red()>150 || pixel.blue()>150,"Background should render the video, not only advance its decoder");
        item->setVisible(false);QTRY_VERIFY(!movie->playing());
        item->setVisible(true);QTRY_VERIFY(movie->playing());
        window.hide();QTRY_VERIFY(!movie->playing());window.show();QTRY_VERIFY(movie->playing());
        const auto project=temporary.filePath("project.json");
        QVERIFY(QFile::copy(source.toLocalFile(),temporary.filePath("wall.mp4")));
        QFile file(project);QVERIFY(file.open(QIODevice::WriteOnly));file.write("{\"type\":\"video\",\"file\":\"wall.mp4\"}");file.close();
        settings.setValue("background.wallpaper",QUrl::fromLocalFile(project).toString());settings.setValue("background.type","Wallpaper");
        QTRY_COMPARE(movie->source(),QUrl::fromLocalFile(temporary.filePath("wall.mp4")));
        QTRY_VERIFY_WITH_TIMEOUT(movie->ready(),8000);
        settings.setValue("background.type","Color");QTRY_VERIFY(movie.isNull());
        QVERIFY(item->findChildren<listenfree::media::ArtworkVideo*>().isEmpty());
    }
    void textureRecreatesExactPixels() {
        QImage original(512,384,QImage::Format_ARGB32_Premultiplied);
        for(int y=0;y<original.height();++y) for(int x=0;x<original.width();++x)
            original.setPixel(x,y,qRgba(x%128,y%128,(x+y)%128,160));
        original.setColorSpace(QColorSpace::SRgb); original.setDevicePixelRatio(1.5);
        const auto initialBitmap=ArtworkTextureFactory::liveBitmapBytes.load();
        const auto initialRecovery=ArtworkTextureFactory::liveRecoveryBytes.load();
        {
            ArtworkTextureFactory factory(original);
            QVERIFY(factory.recoveryBytes()>0); QCOMPARE(factory.image(),original);
            QQuickWindow window; window.resize(64,64); window.show();
            QVERIFY(QTest::qWaitForWindowExposed(&window));
            for(int attempt=0;attempt<2;++attempt) {
                std::atomic_int created{0};
                window.scheduleRenderJob(QRunnable::create([&] {
                    auto* texture=factory.createTexture(&window);
                    created.store(texture?1:-1); delete texture;
                }),QQuickWindow::BeforeRenderingStage);
                window.update(); QTRY_COMPARE_WITH_TIMEOUT(created.load(),1,5000);
                QCOMPARE(factory.retainedBitmapBytes(),0);
                const auto restored=factory.image();
                QCOMPARE(restored,original); QCOMPARE(restored.colorSpace(),original.colorSpace());
                QCOMPARE(restored.devicePixelRatio(),original.devicePixelRatio());
            }
            qInfo("artwork raw=%lld recovery=%lld",qint64(original.sizeInBytes()),qint64(factory.recoveryBytes()));
        }
        QCOMPARE(ArtworkTextureFactory::liveBitmapBytes.load(),initialBitmap);
        QCOMPARE(ArtworkTextureFactory::liveRecoveryBytes.load(),initialRecovery);
    }
    void smallAndIncompressibleTextures() {
        QImage tiny(32,24,QImage::Format_RGB32);tiny.fill(Qt::green);
        ArtworkTextureFactory small(tiny);QCOMPARE(small.recoveryBytes(),0);QCOMPARE(small.image(),tiny);
        QImage noise(512,384,QImage::Format_ARGB32_Premultiplied);
        auto* pixels=reinterpret_cast<quint32*>(noise.bits());
        QRandomGenerator random(43);random.fillRange(pixels,noise.sizeInBytes()/4);
        ArtworkTextureFactory large(noise);QCOMPARE(large.recoveryBytes(),0);QCOMPARE(large.image(),noise);
    }
    void sharedRowsKeepRolesAndCopyOnWrite() {
        using namespace listenfree::qmlbridge;
        QVariantList rows{QVariantMap{{"trackId","a"},{"title","曲目"},{"artist","歌手"},{"album","专辑"},
            {"durationMs",qint64(123456)},{"duration","2:03"},{"localPath","C:/a.mp3"},{"artwork","image://covers/a"}}};
        TrackListModel model; QueueModel queue;
        model.setRows(rows); queue.setRows(rows);
        auto snapshot=model.snapshotRows();
        QCOMPARE(snapshot,rows);
        snapshot[0]=QVariantMap{{"trackId","other"},{"title","snapshot changed"}};
        QCOMPARE(model.get(0).value("trackId").toString(),QString("a"));
        QCOMPARE(model.get(0),queue.get(0)); QCOMPARE(model.get(0).value("duration").toLongLong(),123456);
        auto changed=rows[0].toMap();changed["title"]="更改";rows[0]=changed;
        QCOMPARE(model.get(0).value("title").toString(),QString("曲目"));
        model.setRows(rows);QCOMPARE(model.get(0).value("title").toString(),QString("更改"));
        QCOMPARE(queue.get(0).value("title").toString(),QString("曲目"));
        model.setTracks({});QCOMPARE(model.rowCount(),0);QVERIFY(model.get(0).isEmpty());
        model.setRows(rows);QCOMPARE(model.rowCount(),1);model.setRows({});QCOMPARE(model.rowCount(),0);
    }
    void appendRowPreservesRolesAndAvoidsReset() {
        using namespace listenfree::qmlbridge;
        TrackListModel model;
        QSignalSpy inserted(&model,&QAbstractItemModel::rowsInserted);
        QSignalSpy reset(&model,&QAbstractItemModel::modelReset);
        QSignalSpy countChanged(&model,&TrackListModel::countChanged);
        QVERIFY(inserted.isValid()); QVERIFY(reset.isValid()); QVERIFY(countChanged.isValid());
        QCOMPARE(model.rowCount(),0);
        const QVariantMap first{{"trackId","first"},{"title","曲目"},{"artist","歌手"},
            {"album","专辑"},{"durationMs",qint64(123456)},{"localPath","C:/a.mp3"},
            {"artwork","image://covers/a"},{"songKey","local:a"}};
        QVERIFY(model.appendRow(first));
        QCOMPARE(model.rowCount(),1);
        QCOMPARE(inserted.size(),1); QCOMPARE(reset.size(),0); QCOMPARE(countChanged.size(),1);
        QCOMPARE(inserted.at(0).at(1).toInt(),0); QCOMPARE(inserted.at(0).at(2).toInt(),0);
        const auto roles=model.roleNames();
        const auto row=model.index(0,0);
        for(auto it=roles.cbegin();it!=roles.cend();++it)
            QCOMPARE(model.get(0).value(QString::fromUtf8(it.value())),model.data(row,it.key()));
        QCOMPARE(model.data(row,TrackListModel::DurationRole).toLongLong(),qint64(123456));
        QCOMPARE(model.snapshotRows().at(0).toMap(),first);
        auto snapshot=model.snapshotRows();
        const QVariantMap second{{"trackId","second"},{"title","下首"},{"durationMs",qint64(240000)}};
        QVERIFY(model.appendRow(second));
        QCOMPARE(model.rowCount(),2); QCOMPARE(inserted.size(),2);
        QCOMPARE(inserted.at(1).at(1).toInt(),1); QCOMPARE(inserted.at(1).at(2).toInt(),1);
        QCOMPARE(reset.size(),0); QCOMPARE(countChanged.size(),2);
        QCOMPARE(snapshot.size(),1); QCOMPARE(snapshot.at(0).toMap(),first);
        QCOMPARE(model.snapshotRows().at(1).toMap(),second);
    }
    void sameOrderRowReplacementPreservesPersistentIndexes() {
        using namespace listenfree::qmlbridge;
        const QVariantList original{
            QVariantMap{{"trackId","a"},{"title","A"},{"durationMs",1000},{"extra","old"}},
            QVariantMap{{"trackId","b"},{"title","B"},{"durationMs",2000},{"extra","old"}},
            QVariantMap{{"trackId","c"},{"title","C"},{"durationMs",3000},{"extra","old"}}};
        TrackListModel model;
        model.setRows(original);
        const QPersistentModelIndex anchored(model.index(1, 0));
        QSignalSpy reset(&model, &QAbstractItemModel::modelReset);
        QSignalSpy updated(&model, &QAbstractItemModel::dataChanged);
        QSignalSpy countChanged(&model, &TrackListModel::countChanged);
        auto replacement = original;
        auto middle = replacement.at(1).toMap();
        middle["durationMs"] = 2500;
        middle["extra"] = "new";
        replacement[1] = middle;
        QVERIFY(model.replaceRowsSameOrder(replacement, {1}));
        QVERIFY(anchored.isValid());
        QCOMPARE(anchored.row(), 1);
        QCOMPARE(model.data(anchored, TrackListModel::TrackIdRole).toString(), QString("b"));
        QCOMPARE(model.data(anchored, TrackListModel::DurationRole).toInt(), 2500);
        QCOMPARE(model.snapshotRows(), replacement);
        QCOMPARE(reset.size(), 0);
        QCOMPARE(updated.size(), 1);
        QCOMPARE(updated.at(0).at(0).toModelIndex().row(), 1);
        QCOMPARE(countChanged.size(), 0);
        QVERIFY(!model.replaceRowsSameOrder({}, {}));
        QCOMPARE(model.snapshotRows(), replacement);
    }
    void remoteDecodeErrorAndCancellation() {
        QTcpServer server; QVERIFY(server.listen(QHostAddress::LocalHost));
        QImage input(120,80,QImage::Format_RGB32);input.fill(Qt::blue);
        QByteArray png;QBuffer buffer(&png);buffer.open(QIODevice::WriteOnly);input.save(&buffer,"PNG");
        connect(&server,&QTcpServer::newConnection,&server,[&] {
            while(auto* socket=server.nextPendingConnection()) {
                connect(socket,&QTcpSocket::readyRead,socket,[&,socket] {
                    const auto request=socket->readAll();
                    if(request.contains("/wait"))return;
                    const auto body=request.contains("/bad")?QByteArray("invalid"):png;
                    socket->write("HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: "+QByteArray::number(body.size())+"\r\n\r\n"+body);
                    socket->disconnectFromHost();
                });
            }
        });
        RemoteArtworkProvider provider;
        const auto request=[&](const QString& path) {
            return std::unique_ptr<QQuickImageResponse>(provider.requestImageResponse(
                QString::fromLatin1(QUrl::toPercentEncoding(QString("http://127.0.0.1:%1/%2").arg(server.serverPort()).arg(path))),QSize(60,60)));
        };
        auto good=request("image");QSignalSpy done(good.get(),&QQuickImageResponse::finished);
        QTRY_COMPARE_WITH_TIMEOUT(done.size(),1,5000);QVERIFY2(good->errorString().isEmpty(),qPrintable(good->errorString()));
        std::unique_ptr<QQuickTextureFactory> texture(good->textureFactory());
        QCOMPARE(texture->textureSize(),QSize(90,60));QCOMPARE(texture->image().pixelColor(0,0),QColor(Qt::blue));
        {
            QQmlEngine engine; engine.addImageProvider("artwork",new RemoteArtworkProvider);
            QQmlComponent component(&engine);
            const auto url=QString("http://127.0.0.1:%1/image").arg(server.serverPort());
            component.setData("import QtQuick\nImage { source: 'image://artwork/"+QUrl::toPercentEncoding(url)
                +"'; sourceSize: Qt.size(60,60); fillMode: Image.PreserveAspectCrop }",QUrl());
            std::unique_ptr<QObject> image(component.create());QVERIFY2(image,qPrintable(component.errorString()));
            QTRY_COMPARE_WITH_TIMEOUT(image->property("status").toInt(),1,5000);
            const auto width=image->property("implicitWidth").toReal(), height=image->property("implicitHeight").toReal();
            QVERIFY(width>0 && height>0);
            // Qt multiplies sourceSize by the window's DPR before dispatching
            // provider requests, then exposes logical implicit dimensions.
            QCOMPARE(width/height,qreal(1.5));
        }
        auto bad=request("bad");QSignalSpy failed(bad.get(),&QQuickImageResponse::finished);
        QTRY_COMPARE_WITH_TIMEOUT(failed.size(),1,5000);QVERIFY(!bad->errorString().isEmpty());
        auto pending=request("wait");QSignalSpy cancelled(pending.get(),&QQuickImageResponse::finished);
        QTest::qWait(100);pending->cancel();QTRY_COMPARE_WITH_TIMEOUT(cancelled.size(),1,2000);
        QVERIFY(!pending->errorString().isEmpty());
    }
    void concurrentLargeArtworkKeepsPixelsAndCancels() {
        QImage original(2048,1536,QImage::Format_RGB32);
        for(int y=0;y<original.height();++y) for(int x=0;x<original.width();++x)
            original.setPixel(x,y,qRgb(x%256,y%256,(x+y)%256));
        QByteArray png;QBuffer encoded(&png);encoded.open(QIODevice::WriteOnly);QVERIFY(original.save(&encoded,"PNG"));
        QBuffer input(&png);input.open(QIODevice::ReadOnly);QImageReader reader(&input);
        reader.setScaledSize({1024,768});const auto expected=reader.read().convertToFormat(QImage::Format_RGB32);
        QTcpServer server;QVERIFY(server.listen(QHostAddress::LocalHost));
        connect(&server,&QTcpServer::newConnection,this,[&] {
            while(server.hasPendingConnections()) {
                auto* socket=server.nextPendingConnection();
                connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
                connect(socket,&QTcpSocket::readyRead,socket,[&,socket] {
                    socket->readAll();if(socket->property("sent").toBool())return;socket->setProperty("sent",true);
                    socket->write("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: "+QByteArray::number(png.size())+"\r\nConnection: close\r\n\r\n");
                    socket->write(png);socket->disconnectFromHost();
                });
            }
        });
        RemoteArtworkProvider provider;
        std::vector<std::unique_ptr<QQuickImageResponse>> responses;
        int finished=0;
        for(int i=0;i<4;++i) {
            auto* response=provider.requestImageResponse(QString::fromLatin1(QUrl::toPercentEncoding(
                QString("http://127.0.0.1:%1/large/%2").arg(server.serverPort()).arg(i))),{1024,768});
            connect(response,&QQuickImageResponse::finished,this,[&]{++finished;});
            responses.emplace_back(response);
        }
        responses.back()->cancel();
        QTRY_COMPARE_WITH_TIMEOUT(finished,4,12000);
        for(int i=0;i<3;++i) {
            QVERIFY2(responses[i]->errorString().isEmpty(),qPrintable(responses[i]->errorString()));
            std::unique_ptr<QQuickTextureFactory> factory(responses[i]->textureFactory());
            QVERIFY(factory);QCOMPARE(factory->image(),expected);
        }
        QVERIFY(!responses.back()->errorString().isEmpty());
    }
    void artworkVideoLoopPauseAndRelease() {
        const QString path=qEnvironmentVariable("LISTENFREE_TEST_COVER_VIDEO",QStringLiteral(LISTENFREE_TEST_SOURCE_DIR "/tests/fixtures/artwork-red-blue.mp4"));
        QVERIFY2(!path.isEmpty(),"Set LISTENFREE_TEST_COVER_VIDEO to a short H.264 fixture");
        listenfree::media::ArtworkVideo player;QVideoSink sink;
        player.setVideoSink(&sink);QSignalSpy frames(&sink,&QVideoSink::videoFrameChanged);
        QSignalSpy loops(&player,&listenfree::media::ArtworkVideo::looped);
        player.setPlaying(false);player.setSource(QUrl::fromLocalFile(path));
        QTRY_VERIFY_WITH_TIMEOUT(player.ready(),8000);QVERIFY(player.bounded());
        const auto frame=sink.videoFrame();QVERIFY(frame.isValid());
        QTest::qWait(200);QCOMPARE(sink.videoFrame().startTime(),frame.startTime());
        QVERIFY(player.queuedFrames()<=3);
        player.setPlaying(true);QTRY_VERIFY_WITH_TIMEOUT(loops.size()>=2,12000);
        QVERIFY(player.queuedFrames()<=3);player.setPlaying(false);
        QTest::qWait(60);const auto count=frames.size();QTest::qWait(200);QCOMPARE(frames.size(),count);
        player.setSource({});QVERIFY(!player.ready());QVERIFY(!sink.videoFrame().isValid());QCOMPARE(player.queuedFrames(),0);
        player.setSource(QUrl::fromLocalFile(path));QTRY_VERIFY_WITH_TIMEOUT(player.ready(),8000);
    }
    void artworkVideoQtFallbackAndPoster() {
        const auto path=qEnvironmentVariable("LISTENFREE_TEST_FALLBACK_VIDEO",QStringLiteral(LISTENFREE_TEST_SOURCE_DIR "/tests/fixtures/artwork-mpeg4.mp4"));
        QVERIFY(!path.isEmpty());
        listenfree::media::ArtworkVideo player; QVideoSink sink;player.setVideoSink(&sink);
        player.setPlaying(false);player.setSource(QUrl::fromLocalFile(path));
        QTRY_VERIFY_WITH_TIMEOUT(!player.bounded(),5000);
        QTRY_VERIFY_WITH_TIMEOUT(player.ready(),8000);
        QCOMPARE(sink.videoFrame().size(),QSize(160,90));
        QTest::qWait(100);const auto position=sink.videoFrame().startTime();
        QTest::qWait(200);QCOMPARE(sink.videoFrame().startTime(),position);
        player.setSource(QUrl::fromLocalFile(path+".missing"));
        QTRY_VERIFY_WITH_TIMEOUT(!player.bounded(),5000);QVERIFY(!player.ready());
        player.setSource({});QVERIFY(!sink.videoFrame().isValid());
    }
    void qmlCoverUsesNativeMovieAndFreezesBackground() {
        QTemporaryDir temporary;QVERIFY(temporary.isValid());
        const auto fixture=temporary.filePath("components");QVERIFY(QDir().mkpath(fixture));
        for(const auto* name:{"CoverArt","AppTheme","IconGlyph"})
            QVERIFY(QFile::copy(QStringLiteral(LISTENFREE_TEST_SOURCE_DIR "/music_player_desktop/components/")+name+".qml",fixture+"/"+name+".qml"));
        QFile module(fixture+"/qmldir");QVERIFY(module.open(QIODevice::WriteOnly));
        module.write("singleton AppTheme 1.0 AppTheme.qml\nCoverArt 1.0 CoverArt.qml\nIconGlyph 1.0 IconGlyph.qml\n");module.close();
        const auto icons=temporary.filePath("assets/icons");QVERIFY(QDir().mkpath(icons));
        QVERIFY(QFile::copy(QStringLiteral(LISTENFREE_TEST_SOURCE_DIR "/music_player_desktop/assets/album_Cover_2.png"),temporary.filePath("assets/album_Cover_2.png")));
        QVERIFY(QFile::copy(QStringLiteral(LISTENFREE_TEST_SOURCE_DIR "/music_player_desktop/assets/icons/music.svg"),icons+"/music.svg"));
        listenfree::media::ArtworkVideoFactory factory;
        QQmlEngine engine;engine.rootContext()->setContextProperty("backendArtworkVideoFactory",&factory);
        QQmlComponent component(&engine,QUrl::fromLocalFile(fixture+"/CoverArt.qml"));
        std::unique_ptr<QObject> root(component.create());QVERIFY2(root,qPrintable(component.errorString()));
        auto* item=qobject_cast<QQuickItem*>(root.get());QVERIFY(item);
        QQuickWindow window;window.resize(180,180);item->setParentItem(window.contentItem());item->setSize({180,180});
        item->setProperty("source",QUrl());window.show();QVERIFY(QTest::qWaitForWindowExposed(&window));
        item->setProperty("motionSource",QUrl::fromLocalFile(qEnvironmentVariable("LISTENFREE_TEST_COVER_VIDEO",QStringLiteral(LISTENFREE_TEST_SOURCE_DIR "/tests/fixtures/artwork-red-blue.mp4"))));
        QTRY_VERIFY_WITH_TIMEOUT(item->property("dynamicTexture").value<QQuickItem*>(),8000);
        auto* native=item->findChild<listenfree::media::ArtworkVideo*>();QVERIFY(native);QVERIFY(native->bounded());
        QVERIFY(item->findChildren<QMediaPlayer*>().isEmpty());
        auto* poster=item->property("dynamicFirstFrame").value<QQuickItem*>();QVERIFY(poster);
        const auto grab=[&] {
            const auto result=poster->grabToImage(QSize(64,64));
            QSignalSpy ready(result.get(),&QQuickItemGrabResult::ready);
            if(ready.isEmpty())ready.wait(2000);
            return result->image();
        };
        QTest::qWait(100);const auto first=grab();QVERIFY(!first.isNull());
        QVERIFY(first.pixelColor(32,32).red()>200);
        QSignalSpy loop(native,&listenfree::media::ArtworkVideo::looped);
        QTRY_VERIFY_WITH_TIMEOUT(loop.size()>0,5000);
        QCOMPARE(grab(),first);
        item->setProperty("motionPlaying",false);QTest::qWait(150);QCOMPARE(grab(),first);
        item->setProperty("motionSource",QUrl());
        QTRY_VERIFY(item->findChildren<listenfree::media::ArtworkVideo*>().isEmpty());
    }
};
QTEST_MAIN(ResourceOwnershipTests)
#include "resource_ownership_tests.moc"
