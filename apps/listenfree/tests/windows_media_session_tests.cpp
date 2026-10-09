#include <unknwn.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Storage.Streams.h>
#include "app/windows_media_session.h"
#include <QApplication>
#include <QElapsedTimer>
#include <QImage>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QWindow>
#include <QFile>
#include <QUrl>
#include <QtEndian>
#include <QBuffer>
#include <taglib/fileref.h>
#include <taglib/tvariant.h>
#include <shlobj.h>
#include <QDir>

using namespace winrt::Windows::Media::Control;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Storage::Streams;
using listenfree::WindowsMediaSession;
namespace {
template<class Operation> bool completed(const Operation& op, int timeout = 8000) {
    QElapsedTimer timer; timer.start();
    while (op.Status() == AsyncStatus::Started && timer.elapsed() < timeout) QTest::qWait(20);
    return op.Status() == AsyncStatus::Completed;
}
QString text(const winrt::hstring& value) { return QString::fromStdWString(std::wstring(value)); }
}
class WindowsMediaTests : public QObject {
    Q_OBJECT
    QString identityShortcut_;
private slots:
    void initTestCase() {
        winrt::init_apartment(winrt::apartment_type::single_threaded);
        PWSTR programs = nullptr;
        QVERIFY(SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Programs, KF_FLAG_CREATE, nullptr, &programs)));
        const auto folder = QString::fromWCharArray(programs) + "/ListenFree";
        CoTaskMemFree(programs); QVERIFY(QDir().mkpath(folder));
        auto oldLink = winrt::create_instance<IShellLinkW>(CLSID_ShellLink);
        QVERIFY(SUCCEEDED(oldLink->SetPath(L"C:\\Windows\\notepad.exe")));
        identityShortcut_ = folder + "/ListenFree SMTC Test.lnk";
        QVERIFY(SUCCEEDED(oldLink.as<IPersistFile>()->Save(identityShortcut_.toStdWString().c_str(), TRUE)));
        oldLink = nullptr;
        QCOMPARE(WindowsMediaSession::registerApplicationIdentity("ListenFree.MediaSessionTests", "ListenFree SMTC Test"), identityShortcut_);
        PWSTR processId = nullptr;
        QVERIFY(SUCCEEDED(GetCurrentProcessExplicitAppUserModelID(&processId)));
        const auto id = QString::fromWCharArray(processId); CoTaskMemFree(processId);
        QCOMPARE(id, QString("ListenFree.MediaSessionTests"));
        const auto shellRecognizesName = [] {
            winrt::com_ptr<IShellItem> item;
            if (FAILED(SHCreateItemInKnownFolder(FOLDERID_AppsFolder, 0, L"ListenFree.MediaSessionTests",
                IID_IShellItem, item.put_void()))) return false;
            PWSTR name = nullptr;
            if (FAILED(item->GetDisplayName(SIGDN_NORMALDISPLAY, &name))) return false;
            const auto title = QString::fromWCharArray(name); CoTaskMemFree(name);
            return title == "ListenFree SMTC Test";
        };
        QTRY_VERIFY_WITH_TIMEOUT(shellRecognizesName(), 15000);
        qInfo("Windows Shell resolves the explicit application ID to its friendly name");
    }
    void cleanupTestCase() {
        if (!identityShortcut_.isEmpty()) QFile::remove(identityShortcut_);
        winrt::uninit_apartment();
    }
    void actualWindowsSession() {
        QWindow window; window.setTitle("ListenFree SMTC test");
        window.resize(320, 120); window.show();
        auto media = std::make_unique<WindowsMediaSession>(&window);
        QVERIFY2(media->available(), qPrintable(media->errorString()));
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        QImage red(1024, 1024, QImage::Format_RGB32); red.fill(Qt::red);
        QImage blue(1024, 1024, QImage::Format_RGB32); blue.fill(Qt::blue);
        QVERIFY(red.save(directory.filePath("red.png")));
        QVERIFY(blue.save(directory.filePath("blue.png")));
        WindowsMediaSession::State state;
        state.hasTrack = state.seekable = state.previous = state.next = true;
        state.title = "SMTC 验证曲目"; state.artist = "ListenFree 测试"; state.album = "系统会话";
        state.artwork = directory.filePath("red.png"); state.playback = "Playing";
        state.duration = 180000; state.position = 12000;
        connect(media.get(), &WindowsMediaSession::buttonRequested, this, [&](auto button) {
            if (button == WindowsMediaSession::Play) state.playback = "Playing";
            else if (button == WindowsMediaSession::Pause) state.playback = "Paused";
            else if (button == WindowsMediaSession::Stop) state.playback = "Stopped";
            else if (button == WindowsMediaSession::Next) state.title = "下一首";
            else if (button == WindowsMediaSession::Previous) state.title = "上一首";
            media->update(state);
        });
        connect(media.get(), &WindowsMediaSession::seekRequested, this, [&](qint64 value) {
            state.position = value; media->update(state);
        });
        QSignalSpy buttons(media.get(), &WindowsMediaSession::buttonRequested);
        QSignalSpy seeks(media.get(), &WindowsMediaSession::seekRequested);
        media->update(state);
        auto request = GlobalSystemMediaTransportControlsSessionManager::RequestAsync();
        QVERIFY(completed(request));
        auto manager = request.GetResults();
        GlobalSystemMediaTransportControlsSession session{nullptr};
        const auto findSession = [&] {
            for (const auto& candidate : manager.GetSessions())
                if (text(candidate.SourceAppUserModelId()) == "ListenFree.MediaSessionTests") {
                    session = candidate; return true;
                }
            return false;
        };
        QTRY_VERIFY_WITH_TIMEOUT(findSession(), 10000);
        qInfo().noquote() << "OS session:" << text(session.SourceAppUserModelId());
        const auto properties = [&] {
            auto op = session.TryGetMediaPropertiesAsync();
            if (!completed(op)) throw std::runtime_error("Timed out reading Windows media properties");
            return op.GetResults();
        };
        QTRY_COMPARE_WITH_TIMEOUT(text(properties().Title()), state.title, 5000);
        QCOMPARE(text(properties().Artist()), state.artist);
        QCOMPARE(text(properties().AlbumTitle()), state.album);
        QTRY_COMPARE_WITH_TIMEOUT(session.GetPlaybackInfo().PlaybackStatus(), GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing, 5000);
        QTRY_COMPARE_WITH_TIMEOUT(std::chrono::duration_cast<std::chrono::milliseconds>(session.GetTimelineProperties().EndTime()).count(), 180000, 5000);

        // Replace an in-flight local thumbnail. The OS must receive the latest,
        // bounded bitmap; no original 1024px picture or stale red frame remains.
        state.artwork = directory.filePath("blue.png"); media->update(state);
        const auto thumbnailIsBlue = [&] {
            auto ref = properties().Thumbnail(); if (!ref) return false;
            auto open = ref.OpenReadAsync(); if (!completed(open)) return false;
            auto stream = open.GetResults();
            DataReader reader(stream);
            auto load = reader.LoadAsync(uint32_t(stream.Size())); if (!completed(load)) return false;
            std::vector<uint8_t> data(load.GetResults()); reader.ReadBytes(data);
            const auto image = QImage::fromData(data.data(), int(data.size()));
            return image.size() == QSize(256, 256) && image.pixelColor(100, 100) == QColor(Qt::blue);
        };
        QTRY_VERIFY_WITH_TIMEOUT(thumbnailIsBlue(), 8000);
        qInfo("metadata, timeline and latest 256px thumbnail verified through Windows consumer API");

        // Exercise the actual PortableSession URL, including encoded Chinese,
        // spaces, '#' and a cache revision. Plain PNG paths missed this bug.
        const auto musicPath = directory.filePath(QString::fromUtf8("音乐 封面 #1.wav"));
        QByteArray wav = QByteArray::fromHex("524946462400000057415645666d7420100000000100010044ac000088580100020010006461746100000000");
        wav.append(QByteArray(8820, 0));
        qToLittleEndian<quint32>(wav.size() - 8, wav.data() + 4);
        qToLittleEndian<quint32>(8820, wav.data() + 40);
        { QFile file(musicPath); QVERIFY(file.open(QIODevice::WriteOnly)); QCOMPARE(file.write(wav), wav.size()); }
        QByteArray encoded; QBuffer imageBuffer(&encoded); imageBuffer.open(QIODevice::WriteOnly);
        QVERIFY(blue.save(&imageBuffer, "PNG"));
        {
            const auto native = musicPath.toStdWString();
            TagLib::FileRef file(native.c_str(), false); QVERIFY(!file.isNull());
            TagLib::VariantMap picture;
            picture.insert("data", TagLib::ByteVector(encoded.constData(), encoded.size()));
            picture.insert("mimeType", TagLib::String("image/png"));
            picture.insert("pictureType", TagLib::String("Front Cover"));
            QVERIFY(file.setComplexProperties("PICTURE", {picture})); QVERIFY(file.save());
        }
        state.artwork = "image://covers/" + QString::fromLatin1(QUrl::toPercentEncoding(musicPath)) + "?v=42";
        media->update(state);
        QTRY_VERIFY_WITH_TIMEOUT(thumbnailIsBlue(), 8000);
        qInfo("actual image://covers/ embedded music artwork reaches Windows");
        state.artwork.clear(); media->update(state);
        QTRY_VERIFY_WITH_TIMEOUT(!properties().Thumbnail(), 5000);
        state.artwork = "image://covers/" + QString::fromLatin1(QUrl::toPercentEncoding(musicPath)) + "?v=43";
        media->update(state);
        QTRY_VERIFY_WITH_TIMEOUT(thumbnailIsBlue(), 8000);

        auto pause = session.TryPauseAsync(); QVERIFY(completed(pause)); QVERIFY(pause.GetResults());
        QTRY_COMPARE(state.playback, QString("Paused"));
        QTRY_COMPARE(session.GetPlaybackInfo().PlaybackStatus(), GlobalSystemMediaTransportControlsSessionPlaybackStatus::Paused);
        auto seek = session.TryChangePlaybackPositionAsync(42000LL * 10000); QVERIFY(completed(seek)); QVERIFY(seek.GetResults());
        QTRY_VERIFY(!seeks.isEmpty()); QCOMPARE(seeks.last().first().toLongLong(), 42000);
        auto play = session.TryPlayAsync(); QVERIFY(completed(play)); QVERIFY(play.GetResults());
        QTRY_COMPARE(state.playback, QString("Playing"));
        auto next = session.TrySkipNextAsync(); QVERIFY(completed(next)); QVERIFY(next.GetResults());
        QTRY_COMPARE(state.title, QString("下一首"));
        auto previous = session.TrySkipPreviousAsync(); QVERIFY(completed(previous)); QVERIFY(previous.GetResults());
        QTRY_COMPARE(state.title, QString("上一首"));
        auto stop = session.TryStopAsync(); QVERIFY(completed(stop)); QVERIFY(stop.GetResults());
        QTRY_COMPARE(state.playback, QString("Stopped"));
        QCOMPARE(buttons.size(), 5);
        qInfo("Windows -> Qt play/pause/stop/next/previous/seek verified");
        state.seekable = false; state.playback = "Playing"; media->update(state);
        QTRY_COMPARE(std::chrono::duration_cast<std::chrono::milliseconds>(session.GetTimelineProperties().MaxSeekTime()).count(), 0);
        QCOMPARE(media->errorString(), QString{});
        media.reset();
        QTRY_VERIFY_WITH_TIMEOUT(!findSession(), 10000);
        qInfo("live timeline and session removal verified");
    }
};
QTEST_MAIN(WindowsMediaTests)
#include "windows_media_session_tests.moc"
