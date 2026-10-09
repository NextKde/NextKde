#include "platform_settings.h"
#include "shortcut_service.h"
#include "single_instance.h"
#include "qmlbridge/library_catalog.h"
#include "qmlbridge/download_service.h"
#include "qmlbridge/collection_service.h"
#include "qmlbridge/radio_service.h"
#include "infrastructure/database/database.h"
#include "infrastructure/database/repositories.h"
#include "infrastructure/library/library_scanner.h"
#include "qmlbridge/controllers.h"
#include "qmlbridge/list_models.h"
#include "qmlbridge/spring_value.h"
#include "qmlbridge/lyric_text_metrics.h"
#include "qmlbridge/album_mosaic_model.h"
#include "qmlbridge/portable_session.h"
#include "qmlbridge/immersive_controller.h"
#include "qmlbridge/fume_layout.h"
#include "qmlbridge/folia_scene.h"
#include "qmlbridge/cover_image_provider.h"
#include "qmlbridge/remote_artwork_provider.h"
#include "media/artwork_video.h"
#include "qmlbridge/background_contrast.h"
#include "qmlbridge/account_service.h"
#include "qmlbridge/duplicate_service.h"
#include "qmlbridge/settings_transfer.h"
#include "qmlbridge/wallpaper_library.h"
#include "interface_translator.h"
#include <QApplication>
#include <QQuickItem>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <QJSValue>
#include <QIcon>
#include <QSettings>
#include <qmmp/qmmp.h>
#ifdef Q_OS_WIN
#include <objbase.h>
#include "windows_media_session.h"
#endif

#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTimer>
#include <QTextStream>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "account_browser.h"
#include "media_arguments.h"

int main(int argc, char* argv[]) {
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    qputenv("QSG_USE_SIMPLE_ANIMATION_DRIVER", "1");
    // Smaller packing pages retain each image's pixels and filtering. Images
    // that do not fit use Qt's normal independent texture path.
    if(!qEnvironmentVariableIsSet("QSG_ATLAS_WIDTH"))qputenv("QSG_ATLAS_WIDTH","1024");
    if(!qEnvironmentVariableIsSet("QSG_ATLAS_HEIGHT"))qputenv("QSG_ATLAS_HEIGHT","1024");
    QApplication app(argc, argv);
    QQuickWindow::setDefaultAlphaBuffer(true);
    app.setWindowIcon(QIcon(":/qt/qml/ListenFree/Bootstrap/music_player_desktop/assets/icons/nextkde-music.svg"));
    app.setApplicationName("ListenFree");
    app.setOrganizationName("ListenFree");
    // Keep the existing storage/application IDs so upgrades retain the library.
    app.setApplicationDisplayName("KOS ListenFree");
    app.setApplicationVersion("0.3.8-nextkde.5");
    app.setDesktopFileName("listenfree");
#ifdef Q_OS_WIN
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    listenfree::WindowsMediaSession::registerApplicationIdentity("ListenFree.Desktop", "ListenFree");
#endif
    const QStringList arguments = app.arguments();
    if (arguments.contains("--version")) {
        QTextStream(stdout) << app.applicationDisplayName() << ' ' << app.applicationVersion() << Qt::endl;
        return 0;
    }
    const bool portableSmokeMode = arguments.contains(QStringLiteral("--portable-smoke"));
    const bool smokeMode = arguments.contains(QStringLiteral("--smoke")) || portableSmokeMode;
    const auto captureIndex = arguments.indexOf(QStringLiteral("--capture"));
    const auto viewIndex = arguments.indexOf(QStringLiteral("--view"));
    const QString capturePath = captureIndex >= 0 && captureIndex + 1 < arguments.size()
                                    ? arguments.at(captureIndex + 1)
                                    : QString{};
    const QString captureView = viewIndex >= 0 && viewIndex + 1 < arguments.size()
                                    ? arguments.at(viewIndex + 1)
                                    : QStringLiteral("library/albums");
    const bool captureMode = !capturePath.isEmpty();
    const bool darkCapture = arguments.contains(QStringLiteral("--dark"));
    const bool portableMode = arguments.contains(QStringLiteral("--portable")) ||
                              QFileInfo(QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("portable.mode"))).isFile();

    listenfree::infrastructure::database::Database database;
    QString dataDirectory = portableMode ? QDir(app.applicationDirPath()).filePath("data") : QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    const auto dataIndex = arguments.indexOf("--data-dir");
    if (dataIndex >= 0 && dataIndex + 1 < arguments.size()) dataDirectory = QFileInfo(arguments[dataIndex+1]).absoluteFilePath();
    if (!QDir().mkpath(dataDirectory)) return 2;
    listenfree::SingleInstance instance(dataDirectory);
    const auto instanceResult = instance.acquire(listenfree::mediaFilesFromArguments(arguments.mid(1)));
    if (instanceResult == listenfree::SingleInstance::Result::Forwarded) return 0;
    if (instanceResult == listenfree::SingleInstance::Result::Error) {
        qCritical().noquote() << instance.errorString();
        return 2;
    }
    app.setProperty("listenfreeDataDir", dataDirectory);
    const QString databasePath = QDir(dataDirectory).filePath("library.sqlite");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, dataDirectory);
    QSettings::setPath(QSettings::IniFormat, QSettings::SystemScope, dataDirectory);
    Qmmp::setConfigDir(QDir(dataDirectory).filePath("qmmp"));
    if (qEnvironmentVariableIsEmpty("QMMP_PLUGINS")) qputenv("QMMP_PLUGINS", QDir(app.applicationDirPath()).filePath("qmmp").toLocal8Bit());
    if (!database.open(databasePath) || !database.migrate()) return 2;

    listenfree::infrastructure::database::TrackRepository trackRepository(database);
    listenfree::infrastructure::database::LibraryFolderRepository libraryFolderRepository(database);
    listenfree::infrastructure::database::SettingsRepository settingsRepository(database);
    listenfree::infrastructure::library::LocalLibraryScannerAdapter libraryScanner;
    listenfree::qmlbridge::SourceController sourceController(&settingsRepository, QString{}, true);
    listenfree::qmlbridge::PortableSession controller(database, databasePath, sourceController);
    QObject::connect(&instance, &listenfree::SingleInstance::filesRequested, &controller,
                     [&controller](const QStringList& files) {
        if (files.size() == 1) { controller.openLocal(files.first()); return; }
        QVariantList tracks;
        for (const auto& path : files) {
            QVariantMap track{{"trackId", path}, {"title", QFileInfo(path).completeBaseName()}, {"localPath", path}};
            for (const auto& value : controller.songs()) {
                if (value.toMap().value("localPath").toString() == path) { track = value.toMap(); break; }
            }
            tracks.append(track);
        }
        if (!tracks.isEmpty()) controller.playAll(tracks);
    });
    listenfree::qmlbridge::ImmersiveController immersive;
    const auto syncImmersive = [&] { immersive.setPlayback(controller.position(), controller.state() == "Playing", controller.currentTrack().value("entryId").toString() + ":" + controller.currentTrackId()); };
    QObject::connect(&controller, &listenfree::qmlbridge::PortableSession::progressChanged, &immersive, syncImmersive);
    listenfree::qmlbridge::LibraryController libraryController(libraryScanner, trackRepository,
                                                               &libraryFolderRepository, databasePath);

    listenfree::qmlbridge::CollectionService playlistController(database);
    listenfree::qmlbridge::LibraryCatalog libraryCatalog(controller.tracksModel());
    const auto updateLocalCatalog = [&] { libraryCatalog.setLocalCatalog(controller.songs(), controller.albums(), controller.artists()); };
    const auto updateSavedCatalog = [&] { libraryCatalog.setCollections(playlistController.playlists()); };
    QObject::connect(&controller, &listenfree::qmlbridge::PortableSession::catalogChanged, &libraryCatalog, updateLocalCatalog);
    QObject::connect(&playlistController, &listenfree::qmlbridge::CollectionService::playlistsChanged, &libraryCatalog, updateSavedCatalog);
    updateLocalCatalog(); updateSavedCatalog();
    playlistController.setBilibiliClient(&sourceController.bilibili());
    listenfree::qmlbridge::RadioService radioController(database);
    QObject::connect(&controller, &listenfree::qmlbridge::PortableSession::trackMetadataChanged,
                     &playlistController, &listenfree::qmlbridge::CollectionService::updateTrackMetadata);

    listenfree::qmlbridge::SettingsController settingsController(settingsRepository);
    listenfree::qmlbridge::AccountService accounts(dataDirectory);
    listenfree::AccountBrowser accountBrowser(accounts);
    QObject::connect(&accounts,&listenfree::qmlbridge::AccountService::accountsChanged,&sourceController,[&] {
        auto cookie=accounts.cookieForRequest("bilibili");
        sourceController.bilibili().setCookie(cookie);
        immersive.setBilibiliCookie(cookie); cookie.fill(0);
        const QMap<QString,QString> providers{{"netease","wy"},{"qqmusic","tx"},{"kugou","kg"},{"kuwo","kw"}};
        for (auto it = providers.cbegin(); it != providers.cend(); ++it) {
            auto credential = accounts.cookieForRequest(it.key());
            controller.setAccountCookie(it.value(),credential);
            playlistController.setAccountCookie(it.value(),credential);
            credential.fill(0);
        }
    });
    listenfree::qmlbridge::SettingsTransfer transfer(database,settingsController,libraryController);
    listenfree::qmlbridge::DuplicateService duplicates(databasePath,libraryController);
    QObject::connect(&accounts,&listenfree::qmlbridge::AccountService::notice,&controller,&listenfree::qmlbridge::PortableSession::notice);
    QObject::connect(&transfer,&listenfree::qmlbridge::SettingsTransfer::notice,&controller,&listenfree::qmlbridge::PortableSession::notice);
    QObject::connect(&duplicates,&listenfree::qmlbridge::DuplicateService::notice,&controller,&listenfree::qmlbridge::PortableSession::notice);
    QObject::connect(&duplicates,&listenfree::qmlbridge::DuplicateService::merged,&controller,[&](const QVariantList& redirects) {controller.redirectDuplicates(redirects);playlistController.reloadSaved();});
    QObject::connect(&duplicates,&listenfree::qmlbridge::DuplicateService::mergeStarting,&controller,&listenfree::qmlbridge::PortableSession::prepareDuplicateMerge);
    listenfree::ShortcutService shortcuts(settingsController, &app);
    listenfree::qmlbridge::DownloadService downloads(database, sourceController, settingsController);
    libraryController.setAutoWatchEnabled(settingsController.value("library.autoWatch", true).toBool());
    QObject::connect(&downloads, &listenfree::qmlbridge::DownloadService::fileCompleted,
                     &libraryController, &listenfree::qmlbridge::LibraryController::notifyFileCompleted);
    QObject::connect(&libraryController, &listenfree::qmlbridge::LibraryController::scanningChanged, &controller, [&] {
        if (!libraryController.scanning()) controller.reloadCatalogChanges();
    });
    QObject::connect(&libraryController, &listenfree::qmlbridge::LibraryController::libraryContentChanged,
                     &controller, &listenfree::qmlbridge::PortableSession::reloadCatalogChanges);
    QObject::connect(&controller, &listenfree::qmlbridge::PortableSession::localLibraryChanged,
                     &libraryController, &listenfree::qmlbridge::LibraryController::refreshTotalCount);
    QObject::connect(&app, &QCoreApplication::aboutToQuit, &controller, [&] { libraryController.cancel(); controller.shutdown(); });
    controller.setDynamicArtworkEnabled(settingsController.value("appearance.dynamicArtworkEnabled", true).toBool());
    controller.setBilibiliSourceEnabled(settingsController.value("account.bilibili.sourceEnabled", false).toBool());
    QObject::connect(&settingsController, &listenfree::qmlbridge::SettingsController::valueChanged, &controller, [&](const QString& key, const QVariant& value) {
        if (key == "lyrics.chineseConversion") emit controller.lyricsChanged();
        if (key == "lyrics.autoMatchEnabled") controller.setAutoLyricMatchEnabled(value.toBool());
        if (key == "list.rememberScrollPosition" && !value.toBool()) {database.clearScrollPositions();settingsController.forgetScrollPositions();}
        if (key == "library.autoWatch") libraryController.setAutoWatchEnabled(value.toBool());
        if (key == "appearance.dynamicArtworkEnabled") controller.setDynamicArtworkEnabled(value.toBool());
        if (key == "account.bilibili.sourceEnabled") controller.setBilibiliSourceEnabled(value.toBool());
    });
    qmlRegisterType<listenfree::qmlbridge::SpringValue>("ListenFree.Native", 1, 0, "SpringValue");
    qmlRegisterType<listenfree::qmlbridge::LyricTextMetrics>("ListenFree.Native", 1, 0, "LyricTextMetrics");
    qmlRegisterType<FumeLayout>("ListenFree.Native", 1, 0, "FumeLayout");
    qmlRegisterType<FoliaScene>("ListenFree.Native", 1, 0, "FoliaScene");
    qmlRegisterType<FoliaNodeItem>("ListenFree.Native", 1, 0, "FoliaNodeItem");
    qmlRegisterType<FoliaDecorItem>("ListenFree.Native", 1, 0, "FoliaDecor");
    qmlRegisterType<ImmersiveSpectrumItem>("ListenFree.Native", 1, 0, "ImmersiveSpectrum");
    qmlRegisterType<AlbumMosaicModel>("ListenFree.Native", 1, 0, "AlbumMosaicModel");
    qmlRegisterType<listenfree::qmlbridge::FilteredTrackModel>("ListenFree.Native", 1, 0, "FilteredTrackModel");
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backendAccountBrowser", &accountBrowser);
    UiTranslator translator;
    const auto applyLanguage=[&] {
        app.removeTranslator(&translator);
        if(settingsController.value("ui.language","ZhCn")=="EnUs")app.installTranslator(&translator);
        engine.retranslate();
    };
    applyLanguage();
    QObject::connect(&settingsController,&listenfree::qmlbridge::SettingsController::valueChanged,&engine,[&](const QString& key,const QVariant&){if(key=="ui.language")applyLanguage();});
    engine.rootContext()->setContextProperty("backendImmersive", &immersive);
    engine.rootContext()->setContextProperty("backendAccounts",&accounts);
    engine.rootContext()->setContextProperty("backendRadioController",&radioController);
    engine.rootContext()->setContextProperty("backendSettingsTransfer",&transfer);
    auto* wallpaperLibrary = new listenfree::qmlbridge::WallpaperLibrary(&engine);
    engine.rootContext()->setContextProperty("backendWallpaperLibrary", wallpaperLibrary);
    engine.rootContext()->setContextProperty("backendDuplicates",&duplicates);
    engine.rootContext()->setContextProperty("backendShortcuts", &shortcuts);
    engine.addImageProvider("covers", new CoverImageProvider(controller.collectionCoverIndex()));
    engine.addImageProvider("artwork", new RemoteArtworkProvider);
    engine.rootContext()->setContextProperty("backendArtworkTextures", true);
    auto* artworkVideoFactory = new listenfree::media::ArtworkVideoFactory(&engine);
    engine.rootContext()->setContextProperty("backendArtworkVideoFactory", artworkVideoFactory);
    BackgroundContrast backgroundContrast;
    engine.rootContext()->setContextProperty("backendBackgroundContrast", &backgroundContrast);
    engine.rootContext()->setContextProperty("backendCatalog", &controller);
    engine.rootContext()->setContextProperty("backendLibraryCatalog", &libraryCatalog);
    engine.rootContext()->setContextProperty("backendDownloads", &downloads);
    engine.rootContext()->setContextProperty("backendSourceController", &sourceController);
    // Use names that cannot be shadowed by AppShell's controller properties.
    // Main.qml owns the single explicit hand-off from C++ into the UI shell.
    engine.rootContext()->setContextProperty(QStringLiteral("backendAppController"), &controller);
    engine.rootContext()->setContextProperty(QStringLiteral("backendLibraryController"), &libraryController);
    engine.rootContext()->setContextProperty(QStringLiteral("backendPlayerController"), &controller);
    engine.rootContext()->setContextProperty(QStringLiteral("backendPlaylistController"), &playlistController);
    engine.rootContext()->setContextProperty(QStringLiteral("backendOnlineController"), &controller);
    engine.rootContext()->setContextProperty(QStringLiteral("backendSettingsController"), &settingsController);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); },
                     Qt::QueuedConnection);
    engine.loadFromModule(QStringLiteral("ListenFree.Bootstrap"), QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty()) return 1;
    auto* mainWindow = qobject_cast<QQuickWindow*>(engine.rootObjects().constFirst());
    auto* mainShell = mainWindow ? mainWindow->findChild<QObject*>("appShell") : nullptr;
    shortcuts.setWindow(mainWindow);
    QObject::connect(&shortcuts, &listenfree::ShortcutService::activated, &controller, [&](const QString& action) {
        if (action == "playPause") { if (controller.state() == "Playing") controller.pause(); else controller.play(); }
        else if (action == "previous") controller.previous();
        else if (action == "next") controller.next();
        else if (action == "volumeUp") controller.setVolume(qMin(1.f, controller.volume() + .05f));
        else if (action == "volumeDown") controller.setVolume(qMax(0.f, controller.volume() - .05f));
        else if (action == "focusSearch" && mainShell) QMetaObject::invokeMethod(mainShell, "focusSearch");
        else if (action == "back" && mainShell) QMetaObject::invokeMethod(mainShell, "navigateBack");
    });
    if (mainShell) {
        mainShell->setProperty("uiFontFamily", settingsController.value("ui.fontFamily", "SystemDefault"));
        mainShell->setProperty("animationsEnabled", settingsController.value("ui.motionEnabled", true));
    }
    listenfree::PlatformSettings platform(mainWindow, mainShell, settingsController, controller, playlistController, database, libraryController);
    engine.rootContext()->setContextProperty("backendPlatform", &platform);
    instance.setWindow(mainWindow);
    if(!smokeMode && !captureMode && !arguments.contains("--data-dir")) QTimer::singleShot(0,&accounts,&listenfree::qmlbridge::AccountService::restore);
    if (captureMode) {
        auto* window = qobject_cast<QQuickWindow*>(engine.rootObjects().constFirst());
        auto* shell = window ? window->findChild<QObject*>(QStringLiteral("appShell")) : nullptr;
        if (shell) {
            shell->setProperty("captureView", captureView);
            shell->setProperty("darkMode", darkCapture);
            if (captureView == QStringLiteral("settings") ||
                captureView == QStringLiteral("settings-downloads") ||
                captureView == QStringLiteral("settings-sources") ||
                captureView == QStringLiteral("settings-source-manager") ||
                captureView == QStringLiteral("settings-accounts") ||
                captureView == QStringLiteral("settings-account-cookie")) {
                shell->setProperty("settingsOpen", true);
            } else if (captureView == QStringLiteral("nowplaying") ||
                       captureView == QStringLiteral("nowplaying-queue") ||
                       captureView == QStringLiteral("nowplaying-comments") ||
                       captureView == QStringLiteral("nowplaying-immersive") ||
                       captureView == QStringLiteral("nowplaying-lyrics-menu") ||
                       captureView == QStringLiteral("nowplaying-traffic-hover")) {
                shell->setProperty("nowPlayingOpen", true);
                shell->setProperty("morphProgress", 1.0);
                if (captureView == QStringLiteral("nowplaying-queue")) {
                    shell->setProperty("queueFromNowPlaying", true);
                    shell->setProperty("queueOpen", true);
                }
            } else if (captureView == QStringLiteral("search-lx")) {
                shell->setProperty("currentRoute", QStringLiteral("search"));
            } else if (captureView == QStringLiteral("search-input")) {
                shell->setProperty("currentRoute", QStringLiteral("library/songs"));
            } else if (captureView == QStringLiteral("queue")) {
                shell->setProperty("queueOpen", true);
            } else if (captureView == QStringLiteral("collapsed-player")) {
                shell->setProperty("playerCollapsed", true);
            } else if (captureView == QStringLiteral("sidebar-collapsed")) {
                shell->setProperty("sidebarCollapsed", true);
            } else if (captureView == QStringLiteral("musiceditor")) {
                shell->setProperty("musicEditorOpen", true);
            } else if (captureView == QStringLiteral("musiceditor-properties")) {
                shell->setProperty("musicEditorOpen", true);
            } else if (captureView == QStringLiteral("alert")) {
                shell->setProperty("globalAlertOpen", true);
            } else if (captureView == QStringLiteral("playlist-filter") ||
                       captureView == QStringLiteral("playlist-share")) {
                shell->setProperty("currentRoute", QStringLiteral("playlists"));
            } else if (captureView == QStringLiteral("floating-volume") ||
                       captureView == QStringLiteral("floating-mode") ||
                       captureView == QStringLiteral("traffic-hover")) {
                shell->setProperty("currentRoute", QStringLiteral("library/albums"));
            } else if (captureView == QStringLiteral("my-lists-create")) {
                shell->setProperty("currentRoute", QStringLiteral("my-lists"));
            } else if (captureView == QStringLiteral("detail-album") ||
                       captureView == QStringLiteral("detail-collapsed")) {
                shell->setProperty("currentRoute", QStringLiteral("detail/album"));
            } else {
                shell->setProperty("currentRoute", captureView);
            }

            QTimer::singleShot(520, &app, [shell, captureView] {
                if (captureView == QStringLiteral("search-input")) {
                    if (auto* input = shell->findChild<QQuickItem*>(QStringLiteral("globalSearchInput"))) {
                        input->setProperty("text", QStringLiteral("搜索 ListenFree"));
                        input->forceActiveFocus();
                        qInfo() << "Search input:" << input->property("color") << "focused:" << input->hasActiveFocus();
                    }
                } else if (captureView == QStringLiteral("playlist-filter")) {
                    if (auto* page = shell->findChild<QObject*>(QStringLiteral("playlistPage")))
                        page->setProperty("filterOpen", true);
                } else if (captureView == QStringLiteral("playlist-share")) {
                    if (auto* page = shell->findChild<QObject*>(QStringLiteral("playlistPage")))
                        page->setProperty("shareOpen", true);
                } else if (captureView == QStringLiteral("floating-volume")) {
                    if (auto* player = shell->findChild<QObject*>(QStringLiteral("floatingPlayer")))
                        player->setProperty("volumePinned", true);
                } else if (captureView == QStringLiteral("floating-mode")) {
                    if (auto* player = shell->findChild<QObject*>(QStringLiteral("floatingPlayer")))
                        player->setProperty("modeMenuVisible", true);
                } else if (captureView == QStringLiteral("detail-collapsed")) {
                    if (auto* scroll = shell->findChild<QObject*>(QStringLiteral("collectionScroll")))
                        scroll->setProperty("contentY", 80.0);
                } else if (captureView == QStringLiteral("musiceditor-properties")) {
                    if (auto* editor = shell->findChild<QObject*>(QStringLiteral("musicEditorDialog")))
                        editor->setProperty("selectedTab", 2);
                } else if (captureView == QStringLiteral("settings-downloads")) {
                    if (auto* settings = shell->findChild<QObject*>(QStringLiteral("settingsPage")))
                        settings->setProperty("selectedCategory", 4);
                } else if (captureView == QStringLiteral("settings-sources")) {
                    if (auto* settings = shell->findChild<QObject*>(QStringLiteral("settingsPage")))
                        settings->setProperty("selectedCategory", 5);
                } else if (captureView == QStringLiteral("settings-source-manager")) {
                    if (auto* settings = shell->findChild<QObject*>(QStringLiteral("settingsPage"))) {
                        settings->setProperty("selectedCategory", 5);
                        settings->setProperty("sourceManagerOpen", true);
                    }
                } else if (captureView == QStringLiteral("settings-accounts")) {
                    if (auto* settings = shell->findChild<QObject*>(QStringLiteral("settingsPage")))
                        settings->setProperty("selectedCategory", 6);
                } else if (captureView == QStringLiteral("settings-account-cookie")) {
                    if (auto* settings = shell->findChild<QObject*>(QStringLiteral("settingsPage"))) {
                        settings->setProperty("selectedCategory", 6);
                        settings->setProperty("accountCookieProvider", QStringLiteral("netease"));
                        settings->setProperty("accountCookieOpen", true);
                    }
                } else if (captureView == QStringLiteral("nowplaying-comments")) {
                    if (auto* page = shell->findChild<QObject*>(QStringLiteral("nowPlayingPage")))
                        page->setProperty("commentsOpen", true);
                } else if (captureView == QStringLiteral("nowplaying-immersive")) {
                    if (auto* page = shell->findChild<QObject*>(QStringLiteral("nowPlayingPage")))
                        page->setProperty("immersiveNoticeOpen", true);
                } else if (captureView == QStringLiteral("nowplaying-lyrics-menu")) {
                    if (auto* lyrics = shell->findChild<QObject*>(QStringLiteral("nowPlayingLyricsPanel")))
                        QMetaObject::invokeMethod(lyrics, "openSettingsMenu");
                } else if (captureView == QStringLiteral("my-lists-create")) {
                    if (auto* page = shell->findChild<QObject*>(QStringLiteral("myListsPage")))
                        QMetaObject::invokeMethod(page, "beginCreate");
                }
            });
        }
        QTimer::singleShot(qBound(1500,qEnvironmentVariableIntValue("LISTENFREE_CAPTURE_DELAY"),15000), &app, [&app, window, capturePath] {
            if (!window) {
                app.exit(3);
                return;
            }
            const QFileInfo target(capturePath);
            QDir().mkpath(target.absolutePath());
            const QImage image = window->grabWindow();
            app.exit(!image.isNull() && image.save(target.absoluteFilePath()) ? 0 : 4);
        });
    } else if (smokeMode) {
        QTimer::singleShot(100, &app, &QCoreApplication::quit);
    }
    return app.exec();
}
