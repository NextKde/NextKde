#include "platform_settings.h"
#include "windows_media_session.h"
#include <QApplication>
#include <QCloseEvent>
#include <QDir>
#include <QElapsedTimer>
#include <QMessageBox>
#include <QPainter>
#include <QPixmapCache>
#include <QMetaProperty>
#include <QPlatformSurfaceEvent>
#include <QQmlEngine>
#include <QSettings>
#include <QStandardPaths>
#include <QStyleHints>
#include <QThread>
#include <QClipboard>
#include <QDesktopServices>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFile>
#include <QSysInfo>
#include <QTextEdit>
#include <QVBoxLayout>
#include <dwmapi.h>
#include <shobjidl.h>
#include <windows.h>

namespace listenfree {
PlatformSettings::PlatformSettings(QQuickWindow *window, QObject *shell,
                                   qmlbridge::SettingsController &settings,
                                   qmlbridge::PortableSession &player,
                                   qmlbridge::CollectionService &lists,
                                   infrastructure::database::Database &db,
                                   qmlbridge::LibraryController &library,
                                   QObject *parent)
    : QObject(parent), window_(window), shell_(shell), settings_(settings),
      player_(player), lists_(lists), db_(db), library_(library) {
  window_->installEventFilter(this);
  windowShapeUpdate_.setSingleShot(true);
  connect(&windowShapeUpdate_, &QTimer::timeout, this, &PlatformSettings::applyWindowShape);
  connect(window_, &QWindow::widthChanged, this, &PlatformSettings::scheduleWindowShape);
  connect(window_, &QWindow::heightChanged, this, &PlatformSettings::scheduleWindowShape);
  connect(window_, &QWindow::screenChanged, this, &PlatformSettings::scheduleWindowShape);
  connect(window_, &QWindow::visibilityChanged, this, &PlatformSettings::scheduleWindowShape);
  const auto radiusProperty = window_->metaObject()->property(window_->metaObject()->indexOfProperty("cornerRadius"));
  if (radiusProperty.hasNotifySignal()) {
    connect(window_, radiusProperty.notifySignal(), this,
            metaObject()->method(metaObject()->indexOfSlot("scheduleWindowShape()")));
  }
  menu_.addAction(tr("显示 ListenFree"), this, [this] {
    window_->showNormal();
    window_->raise();
    window_->requestActivate();
  });
  menu_.addAction(tr("播放 / 暂停"), this, [this] {
    if (player_.state() == "Playing")
      player_.pause();
    else
      player_.play();
  });
  menu_.addAction(tr("上一首"), &player_, &qmlbridge::PortableSession::previous);
  menu_.addAction(tr("下一首"), &player_, &qmlbridge::PortableSession::next);
  menu_.addSeparator();
  menu_.addAction(tr("退出"), this, [this] {
    quitting_ = true;
    qApp->quit();
  });
  tray_.setContextMenu(&menu_);
  tray_.setToolTip("ListenFree");
  connect(&tray_, &QSystemTrayIcon::activated, this, [this](auto reason) {
    if (reason == QSystemTrayIcon::Trigger ||
        reason == QSystemTrayIcon::DoubleClick) {
      window_->showNormal();
      window_->raise();
      window_->requestActivate();
    }
  });
  connect(&settings_, &qmlbridge::SettingsController::valueChanged, this,
          &PlatformSettings::apply);
  connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged, this,
          [this] {
            applyTheme();
            updateTray();
          });
  connect(&devices_, &QMediaDevices::audioOutputsChanged, this, [this] {
    const auto selected = player_.outputDevice();
    player_.refreshDevices();
    bool exists = selected == "default";
    for (const auto &v : player_.outputDevices())
      if (v.toMap().value("value") == selected)
        exists = true;
    if (!exists) {
      if (settings_.value("audio.pauseOnDeviceRemoval", true).toBool() && player_.state()=="Playing")
        player_.pause();
      settings_.setValue("audio.outputDeviceId", "default");
    }
  });
  const auto selected =
      settings_.value("audio.outputDeviceId", "default").toString();
  if (!player_.selectOutput(selected))
    player_.selectOutput("default");
  const auto mode = settings_.value("playback.defaultMode", "").toString();
  if (!mode.isEmpty())
    player_.setPlaybackMode(mode);
  applyTheme();
  updateTray();
  frameLimit_ = settings_.value("ui.refreshRateLimit", 60).toInt();
  for (const auto& key : {QString("ui.language"),QString("ui.fontFamily"),QString("ui.motionEnabled"),QString("ui.motionStyle"),QString("ui.refreshRateLimit")})
    apply(key,settings_.value(key,key=="ui.language"?QVariant("ZhCn"):key=="ui.fontFamily"?QVariant("SystemDefault"):key=="ui.motionStyle"?QVariant("Elegant"):key=="ui.motionEnabled"?QVariant(true):QVariant(60)));
  applyTransparency();
  // The threaded scene graph emits this on its render thread. Limit completed
  // frames by real elapsed time; never block the UI/basic render loop.
  auto clock = std::make_shared<QElapsedTimer>();
  clock->start();
  connect(
      window_, &QQuickWindow::afterFrameEnd, this,
      [this, clock] {
        if (QThread::currentThread() == qApp->thread())
          return;
        const qint64 budget =
            1000000000LL / qBound(60, frameLimit_.load(), 120);
        const auto remaining = budget - clock->nsecsElapsed();
        if (remaining > 0)
          QThread::usleep(static_cast<unsigned long>(remaining / 1000));
        clock->restart();
      },
      Qt::DirectConnection);
  ITaskbarList3 *taskbar = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                 CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(&taskbar)))) {
    taskbar->HrInit();
    taskbar_ = taskbar;
  }
  status_.setInterval(1000);
  connect(&status_, &QTimer::timeout, this, &PlatformSettings::updateStatus);
  mediaSession_ = new WindowsMediaSession(window_, this);
  connect(mediaSession_, &WindowsMediaSession::buttonRequested, this, [this](auto button) {
    switch (button) {
    case WindowsMediaSession::Play: player_.play(); break;
    case WindowsMediaSession::Pause:
      if (const auto state = player_.state(); state == "Playing" || state == "Loading" || state == "Buffering") player_.pause();
      break;
    case WindowsMediaSession::Stop: player_.stop(); break;
    case WindowsMediaSession::Next: player_.next(); break;
    case WindowsMediaSession::Previous: player_.previous(); break;
    }
  });
  connect(mediaSession_, &WindowsMediaSession::seekRequested, this, [this](qint64 position) {
    if (player_.seekable() && !player_.live()) player_.seek(qBound<qint64>(0, position, player_.duration()));
  });
  // Coalesce track/queue/artwork bursts. The existing one-second status timer
  // supplies timeline samples; frequent audio position signals don't flood COM.
  mediaUpdate_.setSingleShot(true);
  mediaUpdate_.setInterval(30);
  connect(&mediaUpdate_, &QTimer::timeout, this, &PlatformSettings::updateMediaSession);
  for (const auto signal : {&qmlbridge::PortableSession::currentTrackChanged,
                            &qmlbridge::PortableSession::queueChanged})
    connect(&player_, signal, this, [this] { mediaUpdate_.start(); });
  connect(&player_, &qmlbridge::PortableSession::changed, this, [this, previous=QString{}]() mutable {
    if (const auto state = player_.state(); state != previous) { previous = state; mediaUpdate_.start(); }
  });
  mediaUpdate_.start();
  status_.start();
  if (settings_.value("window.startInFullScreen", false).toBool())
    QTimer::singleShot(0, window_, &QWindow::showFullScreen);
  if (settings_.value("search.focusOnLaunch", false).toBool())
    QTimer::singleShot(300, this, [this] {
      QMetaObject::invokeMethod(shell_, "focusSearch");
    });
  if (settings_.value("playback.autoPlayOnLaunch", false).toBool())
    QTimer::singleShot(1000, &player_, &qmlbridge::PortableSession::play);
}
PlatformSettings::~PlatformSettings() {
  delete mediaSession_;
  disconnect(window_, nullptr, this, nullptr);
  tray_.hide();
  SetThreadExecutionState(ES_CONTINUOUS);
  if (taskbar_)
    static_cast<ITaskbarList3 *>(taskbar_)->Release();
}
void PlatformSettings::applyTheme() {
  const auto mode = settings_.value("appearance.mode", "").toString();
  if (mode.isEmpty())
    return;
  const bool dark =
      mode == "Dark" ||
      (mode == "System" &&
       QGuiApplication::styleHints()->colorScheme() == Qt::ColorScheme::Dark);
  shell_->setProperty("darkMode", dark);
}
void PlatformSettings::updateTray() {
  const auto style = settings_.value("tray.iconStyle", "Auto").toString();
  const bool light =
      style == "Light" ||
      (style == "Auto" &&
       QGuiApplication::styleHints()->colorScheme() == Qt::ColorScheme::Dark);
  QPixmap pix(32, 32);
  pix.fill(Qt::transparent);
  QPainter painter(&pix);
  painter.setRenderHint(QPainter::Antialiasing);
  painter.setPen(Qt::NoPen);
  painter.setBrush(light ? Qt::white : QColor("#30343b"));
  painter.drawEllipse(2, 2, 28, 28);
  painter.setBrush(light ? QColor("#30343b") : Qt::white);
  painter.drawPolygon(QPolygon{{13, 9}, {24, 16}, {13, 23}});
  painter.end();
  tray_.setIcon(style == "Auto" ? QIcon(":/qt/qml/ListenFree/Bootstrap/music_player_desktop/assets/icons/app.png") : QIcon(pix));
  tray_.setVisible(settings_.value("tray.enabled", true).toBool() &&
                   QSystemTrayIcon::isSystemTrayAvailable());
  if (!tray_.isVisible() && !window_->isVisible())
    window_->showNormal();
}
void PlatformSettings::apply(const QString &key, const QVariant &value) {
  if(key=="ui.language") {
    shell_->setProperty("uiLanguage",value.toString()=="EnUs"?"en-US":"zh-CN");
    const QStringList labels{tr("显示 ListenFree"),tr("播放 / 暂停"),tr("上一首"),tr("下一首"),QString{},tr("退出")};
    const auto actions=menu_.actions();
    for(qsizetype i=0;i<actions.size() && i<labels.size();++i)if(!actions[i]->isSeparator())actions[i]->setText(labels[i]);
  }
  if(key=="ui.fontFamily")shell_->setProperty("uiFontFamily",value);
  if(key=="ui.motionEnabled")shell_->setProperty("animationsEnabled",value);
  if(key=="ui.motionStyle")shell_->setProperty("animationStyle",value);
  if(key=="ui.refreshRateLimit")shell_->setProperty("refreshRateLimit",value);
  if(key=="window.transparencyEnabled")applyTransparency();
  if (key=="playback.transition.smart") player_.setSmartTransition(value.toBool());
  if (key=="playback.clearShuffleHistory") QSettings().setValue("ListenFree/clearShuffleHistory",value);
  else if (key == "appearance.mode")
    applyTheme();
  else if (key.startsWith("tray."))
    updateTray();
  else if (key == "ui.refreshRateLimit")
    frameLimit_ = value.toInt();
  else if (key == "audio.outputDeviceId") {
    if (!player_.selectOutput(value.toString()))
      settings_.setValue(key, player_.outputDevice());
  } else if (key == "playback.defaultMode")
    player_.setPlaybackMode(value.toString());
  else if (key == "app.launchAtLogin") {
    QSettings run(
        "HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
        QSettings::NativeFormat);
    if (value.toBool())
      run.setValue("ListenFree",
                   '"' +
                       QDir::toNativeSeparators(
                           QCoreApplication::applicationFilePath()) +
                       '"');
    else
      run.remove("ListenFree");
    run.sync();
    if (run.status() != QSettings::NoError)
      emit player_.notice(tr("无法更新登录启动项"));
  }
  updateStatus();
}
void PlatformSettings::updateStatus() {
  updateMediaSession();
  const auto state = player_.state();
  const bool playing = state == "Playing";
  SetThreadExecutionState(
      ES_CONTINUOUS |
      ((playing &&
        settings_.value("playback.preventSystemSleep", true).toBool())
           ? ES_SYSTEM_REQUIRED
           : 0));
  const auto track = player_.currentTrack();
  tray_.setToolTip((track.value("title").toString() + " — " +
                    track.value("artist").toString())
                       .left(120));
  if (taskbar_) {
    auto *bar = static_cast<ITaskbarList3 *>(taskbar_);
    const HWND hwnd = reinterpret_cast<HWND>(window_->winId());
    if (!settings_.value("window.showTaskbarProgress", true).toBool() ||
        player_.duration() <= 0 || (!playing && state != "Paused"))
      bar->SetProgressState(hwnd, TBPF_NOPROGRESS);
    else {
      bar->SetProgressState(hwnd, playing ? TBPF_NORMAL : TBPF_PAUSED);
      bar->SetProgressValue(hwnd, static_cast<ULONGLONG>(player_.position()),
                            static_cast<ULONGLONG>(player_.duration()));
    }
  }
}
void PlatformSettings::updateMediaSession() {
  if (!mediaSession_) return;
  const auto track = player_.currentTrack();
  WindowsMediaSession::State state;
  state.hasTrack = !track.isEmpty();
  state.title = track.value("title").toString();
  state.artist = track.value("artist").toString();
  state.album = track.value("album").toString();
  state.artwork = track.value("artwork").toString();
  state.playback = player_.state();
  state.position = player_.position();
  state.duration = player_.duration();
  state.seekable = player_.seekable() && !player_.live();
  state.previous = state.hasTrack;
  state.next = player_.queueSongs().size() > 1;
  mediaSession_->update(state);
}
bool PlatformSettings::eventFilter(QObject *watched, QEvent *event) {
  if (watched == window_) {
    if (event->type() == QEvent::PlatformSurface) {
      shapedWindow_ = nullptr;
      const auto* surface = static_cast<QPlatformSurfaceEvent*>(event);
      if (surface->surfaceEventType() == QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed)
        windowShapeUpdate_.stop();
      else {
        // A new HWND needs both backdrop configuration and the matching shape.
        QTimer::singleShot(0, this, &PlatformSettings::applyTransparency);
      }
    } else if (event->type() == QEvent::Resize || event->type() == QEvent::Show ||
               event->type() == QEvent::WindowStateChange ||
               event->type() == QEvent::DevicePixelRatioChange || event->type() == QEvent::ScreenChangeInternal) {
      scheduleWindowShape();
    }
  }
  if(watched==window_ && (event->type()==QEvent::ApplicationPaletteChange || event->type()==QEvent::ThemeChange))applyTransparency();
  if (watched != window_ || event->type() != QEvent::Close || quitting_)
    return false;
  // Automated harness shutdown must not wait on a human dialog.
  const auto args = QCoreApplication::arguments();
  if (args.contains("--validation-report") ||
      args.contains("--ui-regression") || args.contains("--capture"))
    return false;
  if (tray_.isVisible() &&
      settings_.value("window.closeAction", "Quit").toString() ==
          "MinimizeToTray") {
    static_cast<QCloseEvent *>(event)->ignore();
    window_->hide();
    return true;
  }
  if (settings_.value("window.askBeforeClosing", true).toBool() &&
      QMessageBox::question(nullptr, tr("退出 ListenFree"), tr("确定退出播放器？"),
                            QMessageBox::Yes | QMessageBox::No,
                            QMessageBox::No) != QMessageBox::Yes) {
    static_cast<QCloseEvent *>(event)->ignore();
    return true;
  }
  quitting_ = true;
  return false;
}
void PlatformSettings::action(const QString &key) {
  if(key=="diagnostics.copy") {
    QGuiApplication::clipboard()->setText(diagnostics());emit player_.notice(tr("诊断信息已复制。"));return;
  }
  if(key=="updates.openReleasePage") {
    if(!QDesktopServices::openUrl(QUrl("https://github.com/Tabris-Ayanami/ListenFree-desktop/releases")))emit player_.notice(tr("无法打开下载页面。"));return;
  }
  if(key=="updates.checkManually") {
    if (!updater_) {
      updater_ = std::make_unique<UpdateService>(UpdateService::productionConfiguration());
      connect(updater_.get(), &UpdateService::shutdownRequested, this, [this] {
        quitting_ = true;
        qApp->quit();
      });
    }
    QString error;
    if (!updater_->check(&error)) emit player_.notice(error);
    return;
  }
  if(key=="about.licenses") {
    auto* dialog=new QDialog;dialog->setAttribute(Qt::WA_DeleteOnClose);dialog->setWindowTitle(tr("开源许可"));dialog->resize(760,580);
    auto* layout=new QVBoxLayout(dialog);auto* text=new QTextEdit(dialog);text->setReadOnly(true);layout->addWidget(text);
    QStringList sections;const QDir directory(QCoreApplication::applicationDirPath()+"/licenses");
    for(const auto& name:directory.entryList({"*.txt","*.md"},QDir::Files,QDir::Name)) {
      QFile file(directory.filePath(name));if(file.open(QIODevice::ReadOnly))sections.append(name+"\n\n"+QString::fromUtf8(file.readAll()));
    }
    text->setPlainText(sections.isEmpty()?tr("未找到随包许可证文件，请检查安装目录中的 licenses 文件夹。"):sections.join("\n\n────────────────────────\n\n"));
    auto* buttons=new QDialogButtonBox(QDialogButtonBox::Close,dialog);layout->addWidget(buttons);connect(buttons,&QDialogButtonBox::rejected,dialog,&QDialog::close);
    dialog->show();return;
  }
  if (key == "playback.clearShuffleHistory") {
    player_.clearShuffleHistory();
    emit player_.notice(tr("随机播放历史已清空"));
    return;
  }
  if (key == "playlist.clearSavedLists") {
    if (QMessageBox::question(nullptr, tr("清空歌单"),
                              tr("删除所有保存的歌单？不会删除音乐文件。")) ==
        QMessageBox::Yes)
      lists_.clear();
    return;
  }
  if (key == "library.clearIndex") {
    if (library_.scanning() || library_.maintenance()) {
      emit player_.notice(tr("请先结束资料库扫描或重复歌曲处理。"));
      return;
    }
    if (QMessageBox::question(
            nullptr, tr("清空索引"),
            tr("清空本地歌曲索引？目录配置和音频文件保留，可重新扫描恢复。")) !=
        QMessageBox::Yes)
      return;
    if (db_.clearLibraryIndex()) {
      player_.reloadCatalogChanges();
      emit player_.notice(tr("资料库索引已清空"));
    }
    return;
  }
  if (key == "cache.resources.clear") {
    // Resource caches are scoped under the application's data directory.
    window_->releaseResources();
    QPixmapCache::clear();
    if (auto *engine = qmlEngine(shell_))
      engine->trimComponentCache();
    emit player_.notice(tr("已清理未使用的界面资源缓存"));
    return;
  }
}
QString PlatformSettings::diagnostics() const {
  return QString("ListenFree %1\nQt %2\n%3 (%4)\n%5\nQmmp\n%6 Hz")
      .arg(qApp->applicationVersion(),QString::fromLatin1(qVersion()),QSysInfo::prettyProductName(),QSysInfo::currentCpuArchitecture(),
           QFileInfo::exists(qApp->applicationDirPath()+"/portable.mode")?"Portable":"Installed")
      .arg(frameLimit_.load());
}
void PlatformSettings::applyTransparency() {
  HIGHCONTRASTW contrast{};contrast.cbSize=sizeof(contrast);
  SystemParametersInfoW(SPI_GETHIGHCONTRAST,sizeof(contrast),&contrast,0);
  QSettings personalize("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",QSettings::NativeFormat);
  BOOL composition=false;DwmIsCompositionEnabled(&composition);
  const bool wanted=settings_.value("window.transparencyEnabled",true).toBool() && composition && !(contrast.dwFlags&HCF_HIGHCONTRASTON) && personalize.value("EnableTransparency",1).toBool();
  const HWND hwnd=reinterpret_cast<HWND>(window_->winId());
  // A whole-HWND system backdrop ignores our custom 32-DIP alpha boundary,
  // including SetWindowRgn. Use Qt's per-pixel alpha composition instead;
  // the existing QML shader exposes the desktop only through the sidebar.
  const int backdrop=1; // DWMWA_SYSTEMBACKDROP_TYPE / DWMSBT_NONE (Win11 22H2+).
  DwmSetWindowAttribute(hwnd,38,&backdrop,sizeof(backdrop));
  // Glass extension permits alpha in Qt's redirected D3D surface; it is not
  // a system backdrop material. Keep it only while desktop alpha is wanted.
  const MARGINS margins=wanted?MARGINS{-1,-1,-1,-1}:MARGINS{0,0,0,0};
  DwmExtendFrameIntoClientArea(hwnd,&margins);
  transparencyActive_=wanted && window_->format().alphaBufferSize()>0 && window_->color().alpha()==0;
  shell_->setProperty("desktopTransparencyActive",transparencyActive_);
  scheduleWindowShape();
}

void PlatformSettings::scheduleWindowShape() {
  windowShapeUpdate_.start(0);
}

void PlatformSettings::applyWindowShape() {
  if (!window_->handle() || window_->windowState() == Qt::WindowMinimized) return;
  const auto hwnd = reinterpret_cast<HWND>(window_->winId());
  RECT bounds{};
  if (!GetWindowRect(hwnd, &bounds)) return;
  const QSize size(bounds.right-bounds.left, bounds.bottom-bounds.top);
  if (size.isEmpty()) return;
  const bool square = window_->windowState() == Qt::WindowMaximized ||
                      window_->windowState() == Qt::WindowFullScreen;
  const int radius = square ? 0 : qBound(0, qRound(window_->property("cornerRadius").toReal()*window_->devicePixelRatio()),
                                        qMin(size.width(),size.height())/2);
  if (shapedWindow_ == hwnd && shapedSize_ == size && shapedRadius_ == radius) return;
  // Clip the native backdrop as well as the QML scene. Win32 takes ownership
  // of a successful region; the physical geometry avoids fractional-DPI loss.
  HRGN region = radius > 0 ? CreateRoundRectRgn(0,0,size.width()+1,size.height()+1,radius*2,radius*2) : nullptr;
  if (radius > 0 && !region) return;
  if (!SetWindowRgn(hwnd,region,TRUE)) {
    if (region) DeleteObject(region);
    return;
  }
  shapedWindow_ = hwnd;
  shapedSize_ = size;
  shapedRadius_ = radius;
}
} // namespace listenfree
