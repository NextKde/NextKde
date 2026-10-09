#include "qmlbridge/immersive_controller.h"
#include "qmlbridge/fume_layout.h"
#include "qmlbridge/folia_scene.h"
#include "qmlbridge/diorama_geometry.h"
#include <QApplication>
#include <QTest>
#include <QElapsedTimer>
#include <QSignalSpy>
#include <QVideoFrame>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QQuickView>
#include <QQuickItem>
#include <QQmlEngine>
#include <QDir>
#include <QFile>
#include <QFontDatabase>
#include <qmmp/visual.h>
#include <cmath>
using listenfree::qmlbridge::ImmersiveController;
class ImmersiveTests : public QObject {
    Q_OBJECT
    static QVariantList typographyLines() {
        const QStringList text={QStringLiteral("海风翻过山脊"),QStringLiteral("把远方写进窗里的光"),QStringLiteral("一封还没寄出的信"),
            QStringLiteral("云慢慢经过"),QStringLiteral("城市在雨声里醒来"),QStringLiteral("让这一刻停留"),
            QStringLiteral("沿着河岸寻找春天"),QStringLiteral("灯火落在水面"),QStringLiteral("听见脚步轻轻回响"),
            QStringLiteral("当夜色渐渐散去"),QStringLiteral("仍有星光"),QStringLiteral("走过长长的街道"),
            QStringLiteral("把每一阵微风收藏"),QStringLiteral("你从人海之中走来"),QStringLiteral("抬头看见新的天空"),
            QStringLiteral("风的方向"),QStringLiteral("窗外的树影缓缓摇晃"),QStringLiteral("我们在这里相遇"),
            QStringLiteral("时光留下温柔的痕迹"),QStringLiteral("雨停以后"),QStringLiteral("把故事留给明天"),
            QStringLiteral("远处亮起一盏灯"),QStringLiteral("在星河之下"),QStringLiteral("继续向前")};
        QVariantList result;
        for(int i=0;i<text.size();++i)result.append(QVariantMap{{"text",text[i]},{"timeMs",i*5000},
            {"words",QVariantList{QVariantMap{{"text",text[i]},{"startMs",i*5000},{"endMs",i*5000+4000}}}}});
        return result;
    }
private slots:
    void nativeMvKeepsFramesBoundedAndSeeksInBothDirections() {
        const auto fixture=qEnvironmentVariable("LISTENFREE_TEST_NATIVE_MV");
        if(fixture.isEmpty())QSKIP("Set LISTENFREE_TEST_NATIVE_MV to the red-blue 2-second fixture");
        listenfree::media::MvFrameStream stream;QVideoFrame frame;
        QSignalSpy fallback(&stream,&listenfree::media::MvFrameStream::fallbackRequested);
        connect(&stream,&listenfree::media::MvFrameStream::frameReady,this,[&](const QVideoFrame& value){frame=value;});
        stream.open(QUrl::fromLocalFile(fixture));stream.synchronize(100,false,true);
        QTRY_VERIFY_WITH_TIMEOUT(frame.isValid() || fallback.count(),5000);QCOMPARE(fallback.count(),0);
        QVERIFY(frame.toImage().pixelColor(64,64).red()>200);QCOMPARE(stream.duration(),qint64(2000));
        QTest::qWait(200);QVERIFY(stream.queuedFrames()<=3);const auto count=stream.presentedFrames();
        QTest::qWait(200);QCOMPARE(stream.presentedFrames(),count);
        stream.synchronize(1300,false,true);
        QTRY_VERIFY(frame.startTime()>=1250000);QVERIFY(frame.toImage().pixelColor(64,64).blue()>200);
        stream.synchronize(0,false,true);QTRY_COMPARE(frame.startTime(),qint64(0));
        QVERIFY(frame.toImage().pixelColor(64,64).red()>200);
        stream.synchronize(500,true,true);QTRY_VERIFY(stream.presentedFrames()>count+6);
        QVERIFY(stream.queuedFrames()<=3);QCOMPARE(fallback.count(),0);
    }
    void nativeMvCanBeDestroyedByItsFrameReceiver() {
        const auto fixture=qEnvironmentVariable("LISTENFREE_TEST_NATIVE_MV");
        if(fixture.isEmpty())QSKIP("Set LISTENFREE_TEST_NATIVE_MV to a local AVC fixture");
        auto stream=std::make_unique<listenfree::media::MvFrameStream>();
        connect(stream.get(),&listenfree::media::MvFrameStream::frameReady,this,[&]{stream.reset();});
        stream->open(QUrl::fromLocalFile(fixture));stream->synchronize(0,true,true);
        QTRY_VERIFY_WITH_TIMEOUT(!stream,5000);
    }
    void nativeMvCancelsBlockedNetworkWithoutWaitingForTimeout() {
        QTcpServer server;QVERIFY(server.listen(QHostAddress::LocalHost));
        auto stream=std::make_unique<listenfree::media::MvFrameStream>();
        stream->open(QUrl(QString("http://127.0.0.1:%1/stall").arg(server.serverPort())));
        QTRY_VERIFY_WITH_TIMEOUT(server.hasPendingConnections(),3000);
        auto* socket=server.nextPendingConnection();QVERIFY(socket);
        QElapsedTimer clock;clock.start();stream.reset();QVERIFY(clock.elapsed()<1500);
    }
    void nativeMvRequestsFallbackForOtherCodecs() {
        QTemporaryDir dir;QImage image(32,32,QImage::Format_RGB32);image.fill(Qt::red);
        const auto file=dir.filePath("image.png");QVERIFY(image.save(file));
        listenfree::media::MvFrameStream stream;
        QSignalSpy fallback(&stream,&listenfree::media::MvFrameStream::fallbackRequested);
        QSignalSpy frames(&stream,&listenfree::media::MvFrameStream::frameReady);
        stream.open(QUrl::fromLocalFile(file));
        QTRY_COMPARE_WITH_TIMEOUT(fallback.count(),1,5000);QCOMPARE(frames.count(),0);
    }
    void orbitArtworkAccentIgnoresMarginsAndResets() {
        QImage artwork(64,64,QImage::Format_ARGB32);artwork.fill(Qt::black);
        for(int y=12;y<52;y++)for(int x=16;x<48;x++)artwork.setPixelColor(x,y,QColor("#b21b30"));
        for(int y=28;y<33;y++)for(int x=18;x<46;x++)artwork.setPixelColor(x,y,Qt::white);
        const auto red=FoliaScene::accentFromImage(artwork);
        QVERIFY(red.redF()>red.greenF()*2);QVERIFY(red.valueF()>=.87);
        artwork.fill(QColor("#123a90"));const auto blue=FoliaScene::accentFromImage(artwork);
        QVERIFY(blue.blueF()>blue.redF()*2);
        artwork.fill(Qt::gray);QCOMPARE(FoliaScene::accentFromImage(artwork),QColor("#ddd9d3"));
        QCOMPARE(FoliaScene::accentFromImage(QImage{}),QColor("#ddd9d3"));
        FoliaScene scene;scene.setAccentColor(red);scene.resetArtworkAccent();QCOMPARE(scene.accentColor(),QColor("#ddd9d3"));
    }
    void orbitColorsFollowTheReadHeadAndSeek() {
        FoliaScene scene;scene.setWidth(1440);scene.setHeight(900);scene.setStyle("claddagh");
        scene.setProperty("accentColor",QColor("#ee626b"));
        scene.setLyrics({QVariantMap{{"text",QStringLiteral("爱恨交织")},{"timeMs",0},{"words",QVariantList{QVariantMap{{"text",QStringLiteral("爱恨交织")},{"startMs",0},{"endMs",4000}}}}}});
        const QVariantMap glyph{{"line",0},{"glyph",2},{"kind",0}};
        scene.setPosition(1900);const auto before=scene.pose(glyph).color;
        scene.setPosition(2120);const auto after=scene.pose(glyph).color;
        QVERIFY2(after.redF()>after.greenF()*1.8,"The glyph passing the read head must take the cover accent");
        QVERIFY(before.alphaF()<after.alphaF());
        scene.setPosition(1900);QCOMPARE(scene.pose(glyph).color,before);
        scene.setPosition(3900);QVERIFY(scene.pose(glyph).color.redF()>scene.pose(glyph).color.greenF()*1.8);
        scene.setProperty("accentColor",QColor("#629aee"));
        QVERIFY(scene.pose(glyph).color.blueF()>scene.pose(glyph).color.redF()*1.8);
    }
    void nativeScenesAreDeterministicAndBounded() {
        QVariantList lines;for(int i=0;i<150;i++){QVariantList words;const QString text=QStringLiteral("字母分开 Keep moving ")+QString::number(i);for(int j=0;j<text.size();j++)words.append(QVariantMap{{"text",text.mid(j,1)},{"startMs",i*5000+j*150},{"endMs",i*5000+j*150+150}});lines.append(QVariantMap{{"text",text},{"timeMs",i*5000},{"words",words}});}
        FoliaScene scene;scene.setWidth(1440);scene.setHeight(900);scene.setLyrics(lines);
        for(const auto& style:QStringList{"classic","cadenza","partita","cappella","tilt","claddagh","diorama","monet","pendolo","sonnet","tempera","still"}){
            scene.setStyle(style);scene.setPosition(71200);const auto pose=scene.inspectPose(14,2);
            QVERIFY2(!pose.isEmpty(),qPrintable(style));for(const auto& key:QStringList{"x","y","scale","rotation","alpha"})QVERIFY(std::isfinite(pose[key].toDouble()));
            scene.setPosition(490000);scene.setPosition(71200);QCOMPARE(scene.inspectPose(14,2),pose);
            auto* model=qobject_cast<QAbstractItemModel*>(scene.model());QVERIFY(model);QVERIFY2(model->rowCount()<300,qPrintable(style));
        }
    }
    void orbitUsesIndividualGlyphDepthAndSoulWaitsForWordEnd() {
        FoliaScene scene;scene.setWidth(1440);scene.setHeight(900);scene.setStyle("claddagh");
        scene.setLyrics({QVariantMap{{"text",QStringLiteral("测试逐字")},{"timeMs",0},{"words",QVariantList{QVariantMap{{"text",QStringLiteral("测试逐字")},{"startMs",0},{"endMs",4000}}}}}});
        scene.setPosition(1250);const auto a=scene.inspectPose(0,0),b=scene.inspectPose(0,3);QVERIFY(a["x"]!=b["x"]);QVERIFY(a["scale"]!=b["scale"]);
        // Near-side focus must leave real advance for wide CJK glyphs, even
        // though their readable tangent may legitimately share the -38° cap.
        for(int glyph=0;glyph<3;glyph++){const auto left=scene.inspectPose(0,glyph),right=scene.inspectPose(0,glyph+1);
            const auto distance=std::hypot(left["x"].toDouble()-right["x"].toDouble(),left["y"].toDouble()-right["y"].toDouble());
            QVERIFY(distance>55*std::min(left["scale"].toDouble(),right["scale"].toDouble()));}
        scene.setStyle("diorama");scene.setPosition(1250);QCOMPARE(scene.inspectPose(0,1)["ghost"].toDouble(),0.);
        scene.setPosition(2250);QVERIFY(scene.inspectPose(0,1)["ghost"].toDouble()>0.);
        scene.setReducedMotion(true);QCOMPARE(scene.inspectPose(0,1)["ghost"].toDouble(),0.);
    }
    void dioramaCameraIsContinuousIndependentAndSeekable() {
        FoliaScene scene;scene.setWidth(1280);scene.setHeight(800);scene.setSeed("diorama-stage");scene.setStyle("diorama");scene.setLyrics(typographyLines());
        for(int i=1;i<24;++i){
            scene.setPosition(i*5000-.1);const auto before=scene.inspectCamera();
            scene.setPosition(i*5000+.1);const auto after=scene.inspectCamera();
            QVERIFY((before["eye"].value<QVector3D>()-after["eye"].value<QVector3D>()).length()<.002);
            QVERIFY((before["forward"].value<QVector3D>()-after["forward"].value<QVector3D>()).length()<.002);
        }
        scene.setPosition(32300);const auto camera=scene.inspectCamera();const auto pose=scene.inspectPose(6,2);
        scene.setEnergy(1.);QCOMPARE(scene.inspectCamera(),camera);QCOMPARE(scene.inspectPose(6,2),pose);
        scene.setPosition(114000);scene.setPosition(32300);QCOMPARE(scene.inspectCamera(),camera);QCOMPARE(scene.inspectPose(6,2),pose);
        scene.setPosition(32300);QCOMPARE(scene.inspectCamera(),camera);
        scene.setReducedMotion(true);scene.setPosition(31000);const auto still=scene.inspectCamera();
        scene.setPosition(34000);QCOMPARE(scene.inspectCamera(),still);
        for(const QSize size:{QSize(1280,800),QSize(700,950)}){
            scene.setWidth(size.width());scene.setHeight(size.height());scene.setReducedMotion(false);
            for(int i=0;i<24;++i)for(int time:{1600,3000,4600}){
                scene.setPosition(i*5000+time);const auto camera=scene.inspectCamera();
                const auto right=camera["right"].value<QVector3D>(),down=camera["down"].value<QVector3D>(),forward=camera["forward"].value<QVector3D>();
                QVERIFY(std::abs(QVector3D::dotProduct(right,down))<.001);QVERIFY(std::abs(forward.length()-1)<.001);
                for(int g=0;g<typographyLines()[i].toMap()["text"].toString().size();++g){
                    const auto p=scene.inspectPose(i,g);QVERIFY(p["alpha"].toDouble()>.1);
                    QVERIFY2(p["x"].toDouble()>-30&&p["x"].toDouble()<size.width(),qPrintable(QString("line %1 at %2").arg(i).arg(time)));
                    QVERIFY(p["y"].toDouble()>-40&&p["y"].toDouble()<size.height()*.85);
                }
            }
        }
    }
    void dioramaSurfacesStayWeldedAndBounded() {
        for(int kind=0;kind<4;++kind)for(qreal stretch:{1.,2.8,3.4}){
            const auto surface=diorama::surface(kind,stretch);QVERIFY(surface.size()>300);QVERIFY(surface.size()<=diorama::pointsPerShape);
            QCOMPARE(diorama::surface(kind,stretch),surface);
            for(const auto& point:surface)QVERIFY(std::isfinite(point.length()));
            if(kind==0){QSet<QString> unique;for(const auto& p:surface)unique.insert(QString("%1/%2/%3").arg(p.x()).arg(p.y()).arg(p.z()));QCOMPARE(unique.size(),surface.size());}
        }
        for(int shot=0;shot<13;++shot){const auto shapes=diorama::formation(shot,71231,3.25);QVERIFY(shapes.size()>=4&&shapes.size()<=7);
            for(const auto& shape:shapes){QVERIFY(shape.center.z()>=.5);QVERIFY(std::hypot(shape.center.x(),shape.center.y())>3.);}}
    }
    void dioramaGpuBuffersStayBoundedDuringPlayback() {
        class Probe:public FoliaDecorItem {public:using FoliaDecorItem::updatePaintNode;};
        FoliaScene scene;scene.setWidth(1280);scene.setHeight(800);scene.setStyle("diorama");scene.setSeed("buffer-budget");
        QVariantList lines;for(int i=0;i<300;++i)lines.append(QVariantMap{{"text",QStringLiteral("听见远方的回响")},{"timeMs",i*5000}});
        scene.setLyrics(lines);scene.setPosition(50300);Probe decor;decor.setWidth(1280);decor.setHeight(800);decor.setScene(&scene);
        auto* root=decor.updatePaintNode(nullptr,nullptr);auto* node=dynamic_cast<diorama::Node*>(root);QVERIFY(node);
        const void* data=node->geometry()->vertexData();
        for(int ms=50316;ms<50800;ms+=16){scene.setPosition(ms);QCOMPARE(decor.updatePaintNode(root,nullptr),root);QCOMPARE(node->geometry()->vertexData(),data);}
        qsizetype maxBytes=0;
        for(int index:{0,12,125,240,299,2,125}){
            scene.setPosition(index*5000+1300);QCOMPARE(decor.updatePaintNode(root,nullptr),root);
            const auto* geometry=node->geometry();const qsizetype bytes=geometry->vertexCount()*sizeof(diorama::Vertex)+geometry->indexCount()*sizeof(unsigned);
            maxBytes=std::max(maxBytes,bytes);QVERIFY(bytes<5*1024*1024);QVERIFY(node->last-node->first<=6);
        }
        qInfo()<<"Maximum resident particle vertex/index bytes:"<<maxBytes;
        scene.setStyle("sonnet");root=decor.updatePaintNode(root,nullptr);QVERIFY(!dynamic_cast<diorama::Node*>(root));
        scene.setStyle("diorama");root=decor.updatePaintNode(root,nullptr);QVERIFY(dynamic_cast<diorama::Node*>(root));delete root;
    }
    void dioramaNativeGpuRendering() {
        if(!qEnvironmentVariableIsSet("LISTENFREE_DIORAMA_RENDER"))QSKIP("Opt-in native GPU stage render check");
        const auto source=QFINDTESTDATA("../music_player_desktop/components/FoliaLyrics.qml");QVERIFY(!source.isEmpty());
        QTemporaryDir directory;QVERIFY(directory.isValid());const QDir components=QFileInfo(source).dir();
        for(const auto& name:components.entryList({"*.qml","*.js"},QDir::Files))QVERIFY(QFile::copy(components.filePath(name),directory.filePath(name)));
        {QFile file(directory.filePath("qmldir"));QVERIFY(file.open(QIODevice::WriteOnly));file.write("singleton AppTheme 1.0 AppTheme.qml\n");}
        qmlRegisterType<FoliaScene>("ListenFree.Native",1,0,"FoliaScene");qmlRegisterType<FoliaNodeItem>("ListenFree.Native",1,0,"FoliaNodeItem");qmlRegisterType<FoliaDecorItem>("ListenFree.Native",1,0,"FoliaDecor");
        QQuickView view;view.setColor(QColor("#23171e"));view.setResizeMode(QQuickView::SizeRootObjectToView);view.resize(1280,800);
        view.setSource(QUrl::fromLocalFile(directory.filePath("FoliaLyrics.qml")));
        QVERIFY2(view.status()==QQuickView::Ready,qPrintable(view.errors().isEmpty()?QString{}:view.errors().first().toString()));
        auto* root=view.rootObject();QVERIFY(root);root->setProperty("style","diorama");root->setProperty("title","diorama-stage");root->setProperty("lyrics",typographyLines());
        root->setProperty("energy",.65);view.show();QTest::qWait(150);
        auto* scene=root->findChild<FoliaScene*>();QVERIFY(scene);scene->setAccentColor(QColor("#f45f7b"));
        const auto report=qEnvironmentVariable("LISTENFREE_DIORAMA_RENDER");QVERIFY(QDir().mkpath(report));
        int changed=0;QImage last;
        for(int index:{0,1,3,7,10,13}){
            root->setProperty("positionMs",index*5000+2800.);view.requestUpdate();QTest::qWait(100);
            const auto image=view.grabWindow();QVERIFY(!image.isNull());QVERIFY(image.save(QDir(report).filePath(QString("stage-%1.png").arg(index))));
            int decorPixels=0;for(int y=20;y<image.height()-20;y+=2)for(int x=20;x<image.width()-20;x+=2){
                if(x>image.width()*.30&&x<image.width()*.70&&y>image.height()*.28&&y<image.height()*.66)continue;
                const auto color=image.pixelColor(x,y);if(color.red()>90&&color.red()>color.green()*1.12)++decorPixels;
            }
            QVERIFY2(decorPixels>180,qPrintable(QString("GPU scenery pixels: %1").arg(decorPixels)));
            if(!last.isNull()&&image!=last)++changed;
            last=image;
        }
        QCOMPARE(changed,5);view.resize(700,950);root->setProperty("positionMs",52800.);QTest::qWait(100);
        QVERIFY(view.grabWindow().save(QDir(report).filePath("portrait.png")));
        // Exercise the custom-node/material lifetime when changing styles.
        for(const auto& style:{"claddagh","diorama","sonnet","diorama"}){root->setProperty("style",style);QTest::qWait(30);}
        QVERIFY(!view.grabWindow().isNull());
    }
    void fumeLayoutDeterministicTimedAndNonOverlapping() {
        FumeLayout first, second;
        QVariantList lines;
        for(int i=0;i<24;i++)lines.append(QVariantMap{{"text",QStringLiteral("即使年齡不断增长 · ")+QString::number(i)},{"timeMs",i*5000}});
        lines[1]=QVariantMap{{"text",QStringLiteral("风👨‍👩‍👧‍👦光")},{"timeMs",5000},{"words",QVariantList{QVariantMap{{"text",QStringLiteral("风👨‍👩‍👧‍👦光")},{"startMs",5000},{"endMs",9000}}}}};
        lines[2]=QVariantMap{{"text",""},{"timeMs",10000}};
        first.setSeed("one-last-kiss");second.setSeed("one-last-kiss");first.setLyrics(lines);second.setLyrics(lines);
        QCOMPARE(first.blocks(),second.blocks());QCOMPARE(first.blocks().size(),lines.size());
        QCOMPARE(first.block(2).value("start").toInt(),10000);
        QCOMPARE(first.block(1).value("glyphs").toList().size(),3);
        int heroes=0;
        for(int i=0;i<lines.size();i++){
            const auto a=first.block(i);if(a.value("width").toDouble()==0)continue;
            heroes+=a.value("hero").toBool();
            const QRectF ar(a.value("x").toDouble(),a.value("y").toDouble(),a.value("width").toDouble(),a.value("height").toDouble());
            QVERIFY(ar.width()>0 && ar.height()>0);
            for(int j=i+1;j<lines.size();j++){
                const auto b=first.block(j);const QRectF br(b.value("x").toDouble(),b.value("y").toDouble(),b.value("width").toDouble(),b.value("height").toDouble());
                QVERIFY(!ar.intersects(br));
            }
        }
        QVERIFY(heroes>0);second.setSeed("different-song");QVERIFY(first.blocks()!=second.blocks());
    }
    void fumeMixedDirectionsPreserveGlyphsAndTypeHierarchy() {
        FumeLayout layout;layout.setSeed("typography");layout.setLyrics(typographyLines());
        int vertical=0,horizontal=0;int smallest=1000,largest=0;
        for(const auto& value:layout.blocks()) {
            const auto block=value.toMap();const auto glyphs=block["glyphs"].toList();
            smallest=std::min(smallest,block["fontSize"].toInt());largest=std::max(largest,block["fontSize"].toInt());
            QString reconstructed;qreal previous=block["start"].toDouble();
            for(const auto& item:glyphs) {
                const auto glyph=item.toMap();reconstructed+=glyph["sourceText"].toString();
                QVERIFY(glyph["start"].toDouble()>=previous);QVERIFY(glyph["end"].toDouble()>=glyph["start"].toDouble());
                QVERIFY(glyph["x"].toDouble()>=0 && glyph["y"].toDouble()>=0);
                QVERIFY(glyph["x"].toDouble()+glyph["width"].toDouble()<=block["contentWidth"].toDouble()+1);
                QVERIFY(glyph["y"].toDouble()+glyph["height"].toDouble()<=block["contentHeight"].toDouble()+1);
                previous=glyph["start"].toDouble();
            }
            QCOMPARE(reconstructed,block["text"].toString());
            if(block["orientation"]=="vertical") {
                ++vertical;QVERIFY(glyphs.size()>=3);
                QCOMPARE(glyphs[0].toMap()["x"],glyphs[1].toMap()["x"]);
                QVERIFY(glyphs[1].toMap()["y"].toDouble()>glyphs[0].toMap()["y"].toDouble());
                const auto runs=block["runs"].toList();
                if(runs.size()>1)QVERIFY(runs[0].toMap()["x"].toDouble()>runs[1].toMap()["x"].toDouble());
            } else ++horizontal;
        }
        QVERIFY(vertical>=4);QVERIFY(horizontal>=12);QVERIFY(largest>=smallest*2.5);
        QVariantList english;
        for(int i=0;i<20;++i)english.append(QVariantMap{{"text",QString("A light beyond the window %1").arg(i)},{"timeMs",i*4000}});
        layout.setLyrics(english);int sideways=0;
        for(const auto& value:layout.blocks()) {
            const auto block=value.toMap();
            if(block["orientation"]=="sideways") {
                ++sideways;QCOMPARE(block["rotation"].toInt(),90);
                QCOMPARE(block["width"],block["contentHeight"]);QCOMPARE(block["height"],block["contentWidth"]);
            }
        }
        QVERIFY(sideways>=3);
        layout.setLyrics({QVariantMap{{"text",QStringLiteral("风👨‍👩‍👧‍👦光")},{"timeMs",0}}});
        QVERIFY(layout.block(0)["hero"].toBool());QCOMPARE(layout.block(0)["glyphs"].toList().size(),3);
    }
    void fumeCameraAndNativeTextRendering() {
        if(!qEnvironmentVariableIsSet("LISTENFREE_FUME_RENDER"))QSKIP("Opt-in native QML typography render check");
        const auto source=QFINDTESTDATA("../music_player_desktop/components/FumeLyrics.qml");QVERIFY(!source.isEmpty());
        QTemporaryDir directory;QVERIFY(directory.isValid());
        QVERIFY(QFile::copy(source,directory.filePath("FumeLyrics.qml")));
        QVERIFY(QFile::copy(QFileInfo(source).dir().filePath("AppTheme.qml"),directory.filePath("AppTheme.qml")));
        { QFile file(directory.filePath("qmldir"));QVERIFY(file.open(QIODevice::WriteOnly));file.write("singleton AppTheme 1.0 AppTheme.qml\n"); }
        qmlRegisterType<FumeLayout>("ListenFree.Native",1,0,"FumeLayout");
        QQuickView view;view.setColor(QColor("#101820"));view.setResizeMode(QQuickView::SizeRootObjectToView);view.resize(1280,800);
        view.setSource(QUrl::fromLocalFile(directory.filePath("FumeLyrics.qml")));
        QVERIFY2(view.status()==QQuickView::Ready,qPrintable(view.errors().isEmpty()?QString{}:view.errors().first().toString()));
        auto* scene=view.rootObject();QVERIFY(scene);
        scene->setProperty("reducedMotion",true);scene->setProperty("holdRatio",1.);scene->setProperty("seed","typography");
        scene->setProperty("lyrics",typographyLines());view.show();
        auto* layout=scene->findChild<FumeLayout*>();QVERIFY(layout);QCOMPARE(layout->blocks().size(),24);
        const auto report=qEnvironmentVariable("LISTENFREE_FUME_RENDER");QVERIFY(QDir().mkpath(report));
        const auto capture=[&](const QString& name) {view.requestUpdate();QTest::qWait(80);return view.grabWindow().save(QDir(report).filePath(name+".png"));};
        QVariantMap hero,body,vertical;
        QRectF world;
        for(const auto& value:layout->blocks()) {
            const auto block=value.toMap();world=world.united(QRectF(block["x"].toDouble(),block["y"].toDouble(),block["width"].toDouble(),block["height"].toDouble()));
            if(block["orientation"]=="vertical" && vertical.isEmpty())vertical=block;
            if(block["orientation"]!="horizontal")continue;
            if(block["hero"].toBool() && block["fontSize"].toInt()>hero["fontSize"].toInt())hero=block;
            if(!block["hero"].toBool() && (body.isEmpty() || block["fontSize"].toInt()<body["fontSize"].toInt()))body=block;
        }
        QVERIFY(!hero.isEmpty() && !body.isEmpty() && !vertical.isEmpty());
        const auto focus=[&](const QVariantMap& block) {
            scene->setProperty("positionMs",block["start"].toDouble()+2100);QTest::qWait(30);
            return block["fontSize"].toDouble()*scene->property("targetScale").toDouble();
        };
        const auto heroSize=focus(hero);QVERIFY(capture("hero"));const auto bodySize=focus(body);QVERIFY(capture("body"));
        QVERIFY2(heroSize>bodySize*1.8,qPrintable(QString("hero=%1 body=%2").arg(heroSize).arg(bodySize)));
        focus(vertical);QVERIFY(capture("vertical"));
        QCOMPARE(scene->property("lineIndex").toInt(),vertical["index"].toInt());
        QVERIFY(std::abs(scene->property("cameraX").toDouble()-scene->property("targetX").toDouble())<1);
        int loaded=0;QList<QQuickItem*> pending{scene};
        while(!pending.isEmpty()) {
            auto* child=pending.takeLast();pending.append(child->childItems());
            if(child->objectName().startsWith("fumeBlock-") && child->property("active").toBool())++loaded;
        }
        QVERIFY(loaded>0 && loaded<layout->blocks().size());
        view.resize(700,950);QTest::qWait(50);
        QVERIFY(vertical["width"].toDouble()*scene->property("cameraScale").toDouble()<=view.width()*.85);
        QVERIFY(vertical["height"].toDouble()*scene->property("cameraScale").toDouble()<=view.height()*.73);
        QVERIFY(capture("vertical-portrait"));
        view.resize(1280,800);QTest::qWait(50);scene->setProperty("positionMs",60000.);QTest::qWait(30);
        scene->setProperty("cameraX",world.center().x());scene->setProperty("cameraY",world.center().y());
        scene->setProperty("cameraScale",std::min(1160/world.width(),700/world.height()));QVERIFY(capture("overview"));
    }
    void biliSearchResolveAndVideoFrame() {
        if(!qEnvironmentVariableIsSet("LISTENFREE_TEST_ONLINE_MV"))QSKIP("Opt-in live Bilibili check");
        ImmersiveController service;QVideoSink sink;service.attachVideoSink(&sink);
        service.setPlayback(2000,true,"bili");service.setActive(true);
        service.searchMv("One Last Kiss 宇多田光 官方MV","bili");
        QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),40000);
        QVERIFY2(!service.candidates().isEmpty(),qPrintable(service.error()));
        QCOMPARE(service.candidates().first().toMap().value("provider").toString(),QString("bili"));
        QVERIFY(service.candidates().size()<=30);
        for(int i=1;i<service.candidates().size();i++)QVERIFY(service.candidates()[i-1].toMap().value("playCount").toLongLong()>=service.candidates()[i].toMap().value("playCount").toLongLong());
        service.selectMv(0);
        QTRY_VERIFY_WITH_TIMEOUT(service.videoReady()||!service.error().isEmpty(),35000);
        QVERIFY2(service.videoReady(),qPrintable(service.error()));
        QTRY_VERIFY_WITH_TIMEOUT(sink.videoFrame().isValid(),12000);
        if(service.videoPlayer())QVERIFY(!service.videoPlayer()->audioOutput());
        service.setActive(false);QVERIFY(!service.videoPlayer());QVERIFY(!service.nativeVideoPlayer());
    }
    void automaticMvFindsPlayableMatch() {
        if(!qEnvironmentVariableIsSet("LISTENFREE_TEST_ONLINE_MV"))QSKIP("Opt-in live auto-match check");
        ImmersiveController service;QVideoSink sink;service.attachVideoSink(&sink);
        service.setPlayback(1000,true,"auto");service.setActive(true);
        service.autoMatchMv("Blank Space","Taylor Swift",231000);
        QTRY_VERIFY_WITH_TIMEOUT(service.videoReady()||(!service.busy()&&!service.error().isEmpty()),65000);
        QVERIFY2(service.videoReady(),qPrintable(service.error()));
        QTRY_VERIFY_WITH_TIMEOUT(sink.videoFrame().isValid(),12000);
    }
    void inactiveAndPausedDoNotSample() {
        ImmersiveController service;
        service.setPlayback(100, true, "a"); QVERIFY(!service.sampling());
        service.setActive(true); QVERIFY(service.sampling());
        service.setPlayback(150, false, "a"); QVERIFY(!service.sampling());
        service.setPlayback(150, true, "a"); QVERIFY(service.sampling());
        service.setSpectrumEnabled(false); QVERIFY(!service.sampling());
        service.setSpectrumEnabled(true); QVERIFY(service.sampling());
        service.setSuspended(true); QVERIFY(!service.sampling());
        service.setSuspended(false); QVERIFY(service.sampling());
        service.setActive(false); QVERIFY(!service.sampling());
    }
    void fftUsesActualStereoPcmIncludingAntiphase() {
        Visual::clearBuffer(); ImmersiveController service;
        service.setPlayback(0, true, "a"); service.setActive(true);
        float pcm[1024];
        for (int i=0;i<512;++i) { pcm[i*2]=.25f*std::sin(2*3.141592653589793*16*i/512); pcm[i*2+1]=-pcm[i*2]; }
        QElapsedTimer audioClock; audioClock.start();
        QTimer feed; feed.setInterval(10);
        connect(&feed,&QTimer::timeout,&service,[&] { Visual::addAudio(pcm,1024,2,1000+audioClock.elapsed(),60); });
        feed.start();
        QTest::qWait(180);
        const auto bins=service.spectrum(); QCOMPARE(bins.size(),32);
        double peak=0; int peakIndex=-1;
        for(int i=0;i<bins.size();++i) {const double v=bins[i].toDouble();QVERIFY(std::isfinite(v));QVERIFY(v>=0&&v<=1);if(v>peak){peak=v;peakIndex=i;}}
        qInfo() << "FFT peak" << peak << "band" << peakIndex;
        QVERIFY2(peak>.2,"The real FFT should detect a stereo anti-phase tone");
        QVERIFY(peakIndex>=15&&peakIndex<=17);
        service.setPlayback(36,false,"a");
        for(const auto& v:service.spectrum())QCOMPARE(v.toDouble(),0.);
        Visual::clearBuffer();
    }
    void cancellationAndTrackChangeClearMvState() {
        ImmersiveController service; service.setActive(true);
        service.searchMv("test"); QVERIFY(service.busy());
        service.setPlayback(0,false,"new-track"); QVERIFY(!service.busy());
        QVERIFY(service.candidates().isEmpty()); QVERIFY(!service.videoPlayer());
        service.searchMv("test"); service.setActive(false); QVERIFY(!service.busy());
        QTest::qWait(20); QVERIFY(service.candidates().isEmpty());
    }
    void invalidLocalVideoFallsBackAndOffsetIsBounded() {
        ImmersiveController service; service.setActive(true);
        service.autoMatchMv("Blank Space","Taylor Swift",231000);
        service.openLocalVideo(QUrl::fromLocalFile("Z:/missing/mv.mp4"));
        QVERIFY(!service.busy());
        QVERIFY(!service.error().isEmpty()); QVERIFY(!service.videoReady()); QVERIFY(!service.videoPlayer());
        service.setOffsetMs(999999); QCOMPARE(service.offsetMs(),300000);
        service.clearVideo(); QVERIFY(service.error().isEmpty());
    }
    void onlineMvSearchResolveAndVideoFrame() {
        if(!qEnvironmentVariableIsSet("LISTENFREE_TEST_ONLINE_MV")) QSKIP("Opt-in live MV network check");
        ImmersiveController service; QVideoSink sink; service.attachVideoSink(&sink);
        service.setPlayback(2000,true,"a"); service.setActive(true);
        service.searchMv("Taylor Swift Blank Space");
        QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),15000);
        QVERIFY2(!service.candidates().isEmpty(),qPrintable(service.error()));
        service.selectMv(0);
        QTRY_VERIFY_WITH_TIMEOUT(service.videoReady() || !service.error().isEmpty(),20000);
        QVERIFY2(service.videoReady(),qPrintable(service.error()));
        QTRY_VERIFY_WITH_TIMEOUT(sink.videoFrame().isValid(),12000);
        if(service.videoPlayer())QVERIFY(!service.videoPlayer()->audioOutput());
        service.setActive(false); QVERIFY(!service.videoPlayer()); QVERIFY(!service.nativeVideoPlayer()); QVERIFY(!sink.videoFrame().isValid());
    }
    void localVideoFollowsPauseSeekAndReleasesDecoder() {
        const QString fixture=qEnvironmentVariable("LISTENFREE_TEST_MV");
        if(fixture.isEmpty())QSKIP("Set LISTENFREE_TEST_MV to a local video fixture");
        ImmersiveController service; QVideoSink sink; service.attachVideoSink(&sink);
        service.setPlayback(0,false,"a"); service.setActive(true);
        service.openLocalVideo(QUrl::fromLocalFile(fixture));
        QTRY_VERIFY_WITH_TIMEOUT(service.videoReady(),12000);
        QVERIFY(service.videoPlayer()); QVERIFY(!service.videoPlayer()->audioOutput());
        QTRY_COMPARE(service.videoPlayer()->activeAudioTrack(),-1);
        service.setPlayback(1100,true,"a");
        QTRY_COMPARE(service.videoPlayer()->playbackState(),QMediaPlayer::PlayingState);
        service.setPlayback(1600,false,"a");
        QTRY_COMPARE(service.videoPlayer()->playbackState(),QMediaPlayer::PausedState);
        const qint64 target=service.videoPlayer()->duration()>4000?3000:200;
        service.setPlayback(target,false,"a");
        QTRY_VERIFY(std::abs(service.videoPlayer()->position()-target)<200);
        service.setOffsetMs(500); QTRY_VERIFY(std::abs(service.videoPlayer()->position()-target-500)<200);
        service.setActive(false); QVERIFY(!service.videoPlayer()); QVERIFY(!service.videoReady());
    }
};
int main(int argc,char** argv) {
    QApplication app(argc,argv);
#ifdef Q_OS_WIN
    // The offscreen QPA does not enumerate Windows fonts. Use the same system
    // family as the desktop app so layout/render checks cannot pass with tofu.
    if(QGuiApplication::platformName()=="offscreen")for(const auto& name:{"msyh.ttc","msyhbd.ttc","seguiemj.ttf"})
        QFontDatabase::addApplicationFont(QDir(qEnvironmentVariable("WINDIR")).filePath(QString("Fonts/")+name));
#endif
    ImmersiveTests tests;return QTest::qExec(&tests,argc,argv);
}
#include "immersive_tests.moc"
