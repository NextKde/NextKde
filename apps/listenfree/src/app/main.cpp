#include "platform_settings.h"
#include "shortcut_service.h"
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
#include "../../tools/integration_completion_regression.h"
#include "../../tools/window_corner_regression.h"
#include "../../tools/portable_acceptance.h"
#include "../../tools/interaction_regression.h"
#include "../../tools/new_todo_regression.h"
#include "../../tools/appearance_regression.h"
#include "../../tools/immersive_regression.h"
#include "../../tools/disc_queue_regression.h"
#include "../../tools/playlist_transition_regression.h"
#include "../../tools/artist_blend_regression.h"
#include "../../tools/radio_regression.h"
#include <QApplication>
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
#include <QQmlApplicationEngine>
#include <QQmlContext>

int main(int argc, char* argv[]) {
    qputenv("QSG_USE_SIMPLE_ANIMATION_DRIVER", "1");
    // Smaller packing pages retain each image's pixels and filtering. Images
    // that do not fit use Qt's normal independent texture path.
    if(!qEnvironmentVariableIsSet("QSG_ATLAS_WIDTH"))qputenv("QSG_ATLAS_WIDTH","1024");
    if(!qEnvironmentVariableIsSet("QSG_ATLAS_HEIGHT"))qputenv("QSG_ATLAS_HEIGHT","1024");
    QApplication app(argc, argv);
    app.setWindowIcon(QIcon(":/qt/qml/ListenFree/Bootstrap/music_player_desktop/assets/icons/app.png"));
    app.setApplicationName("ListenFree");
    app.setOrganizationName("ListenFree");
    app.setApplicationVersion("0.3.8");
#ifdef Q_OS_WIN
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    listenfree::WindowsMediaSession::registerApplicationIdentity("ListenFree.Desktop", "ListenFree");
#endif
    const QStringList arguments = app.arguments();
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
    listenfree::qmlbridge::SourceController sourceController(&settingsRepository, QDir(app.applicationDirPath()).filePath("listenfree-sourcehost.exe"), true);
    listenfree::qmlbridge::PortableSession controller(database, databasePath, sourceController);
    listenfree::qmlbridge::ImmersiveController immersive;
    const auto syncImmersive = [&] { immersive.setPlayback(controller.position(), controller.state() == "Playing", controller.currentTrack().value("entryId").toString() + ":" + controller.currentTrackId()); };
    QObject::connect(&controller, &listenfree::qmlbridge::PortableSession::progressChanged, &immersive, syncImmersive);
    listenfree::qmlbridge::LibraryController libraryController(libraryScanner, trackRepository,
                                                               &libraryFolderRepository, databasePath);

    listenfree::qmlbridge::CollectionService playlistController(database);
    playlistController.setBilibiliClient(&sourceController.bilibili());
    listenfree::qmlbridge::RadioService radioController(database);
    QObject::connect(&controller, &listenfree::qmlbridge::PortableSession::trackMetadataChanged,
                     &playlistController, &listenfree::qmlbridge::CollectionService::updateTrackMetadata);

    listenfree::qmlbridge::SettingsController settingsController(settingsRepository);
    listenfree::qmlbridge::AccountService accounts(dataDirectory);
    QObject::connect(&accounts,&listenfree::qmlbridge::AccountService::accountsChanged,&sourceController,[&] {
        auto cookie=accounts.cookieForRequest("bilibili");
        sourceController.bilibili().setCookie(cookie);
        immersive.setBilibiliCookie(cookie); cookie.fill(0);
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
        mainShell->setProperty("darkMode", settingsController.value("ui.appearance", "light").toString() == "dark");
        mainShell->setProperty("uiFontFamily", settingsController.value("ui.fontFamily", "SystemDefault"));
        mainShell->setProperty("animationsEnabled", settingsController.value("ui.motionEnabled", true));
    }
    listenfree::PlatformSettings platform(mainWindow, mainShell, settingsController, controller, playlistController, database, libraryController);
    engine.rootContext()->setContextProperty("backendPlatform", &platform);
    if(!smokeMode && !captureMode && !arguments.contains("--data-dir")) QTimer::singleShot(0,&accounts,&listenfree::qmlbridge::AccountService::restore);
    const auto validationIndex = arguments.indexOf("--validation-report");
    const auto integrationIndex=arguments.indexOf("--integration-regression");
    const auto artistBlendIndex=arguments.indexOf("--artist-blend-regression");
    const auto uiRegressionIndex = arguments.indexOf("--ui-regression");
    const auto todoRegressionIndex = arguments.indexOf("--todo-regression");
    const auto appearanceIndex = arguments.indexOf("--appearance-regression");
    const auto playlistTransitionIndex = arguments.indexOf("--playlist-transition-report");
    const auto radioIndex=arguments.indexOf("--radio-regression");
    const auto radioFavoritesIndex=arguments.indexOf("--radio-favorites-regression");
    const auto immersiveIndex=arguments.indexOf("--immersive-regression");
    const auto discQueueIndex=arguments.indexOf("--disc-queue-regression");
    const auto cornerIndex=arguments.indexOf("--window-corner-regression");
    if(cornerIndex>=0 && cornerIndex+1<arguments.size() && arguments.contains("--data-dir")) {
        runWindowCornerRegression(app,mainWindow,mainShell,settingsController,arguments[cornerIndex+1]);
    } else if(discQueueIndex>=0 && discQueueIndex+1<arguments.size() && arguments.contains("--data-dir")) {
        runDiscQueueRegression(app,mainWindow,mainShell,settingsController,arguments[discQueueIndex+1]);
    } else if(immersiveIndex>=0 && immersiveIndex+1<arguments.size() && arguments.contains("--data-dir")) {
        runImmersiveRegression(app,mainWindow,mainShell,immersive,settingsController,arguments[immersiveIndex+1]);
    } else if(radioFavoritesIndex>=0 && radioFavoritesIndex+1<arguments.size() && arguments.contains("--data-dir")) {
        runRadioFavoritesRegression(app,mainWindow,mainShell,controller,settingsController,radioController,playlistController,arguments[radioFavoritesIndex+1]);
    } else if(radioIndex>=0 && radioIndex+1<arguments.size() && arguments.contains("--data-dir")) {
        runRadioRegression(app,mainWindow,mainShell,controller,settingsController,radioController,arguments[radioIndex+1]);
    } else if(artistBlendIndex>=0 && artistBlendIndex+1<arguments.size() && arguments.contains("--data-dir")) {
        runArtistBlendRegression(app,mainWindow,mainShell,controller,settingsController,arguments[artistBlendIndex+1]);
    } else if(integrationIndex>=0 && integrationIndex+1<arguments.size() && arguments.contains("--data-dir")) {
        runIntegrationCompletionRegression(app,mainWindow,mainShell,settingsController,platform,arguments[integrationIndex+1]);
    } else if (playlistTransitionIndex >= 0 && playlistTransitionIndex + 1 < arguments.size()) {
        runPlaylistTransitionRegression(app,mainWindow,mainShell,controller,settingsController,arguments[playlistTransitionIndex+1]);
    } else if (appearanceIndex >= 0 && appearanceIndex + 1 < arguments.size()) {
        runAppearanceRegression(app,mainWindow,mainShell,controller,settingsController,arguments[appearanceIndex+1]);
    } else if (todoRegressionIndex >= 0 && todoRegressionIndex + 1 < arguments.size()) {
        runNewTodoRegression(app,mainWindow,mainShell,controller,settingsController,arguments[todoRegressionIndex+1]);
    } else if (uiRegressionIndex >= 0 && uiRegressionIndex + 1 < arguments.size()) {
        runUiRegression(app, mainWindow, mainShell, controller, settingsController, playlistController, sourceController, arguments[uiRegressionIndex+1]);
    } else if (validationIndex >= 0 && validationIndex + 1 < arguments.size()) {
        const auto argument = [&](const QString& key) { const auto i = arguments.indexOf(key); return i >= 0 && i+1 < arguments.size() ? arguments[i+1] : QString{}; };
        runPortableAcceptance(app, controller, libraryController, sourceController, mainWindow, mainShell,
                              argument("--validation-root"), argument("--validation-script"), argument("--validation-report"), arguments.contains("--validate-restore"));
    } else if (captureMode) {
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
