#include <mpv/client.h>

#include <QFileInfo>
#include <QTextStream>
#include <QElapsedTimer>

namespace {

bool setOption(mpv_handle* context, const char* name, const char* value) {
    const int result = mpv_set_option_string(context, name, value);
    QTextStream(stdout) << "option." << name << "=" << value << " result=" << result << " ("
                        << mpv_error_string(result) << ")\n";
    return result >= 0;
}

} // namespace

int main(int argc, char* argv[]) {
    // Upstream runtime verified: shinchiro/mpv-winbuild-cmake release
    // 20260831 (git-e8673660ab), x86_64-v3 libmpv package.
    QTextStream out(stdout);
    if (argc != 1 && argc != 2) {
        QTextStream(stderr) << "Usage: listenfree-mpv-core-probe [audio-file]\n";
        return 2;
    }
    if (argc == 2 && !QFileInfo::exists(QString::fromLocal8Bit(argv[1]))) {
        QTextStream(stderr) << "Audio file does not exist: " << argv[1] << '\n';
        return 2;
    }

    mpv_handle* context = mpv_create();
    if (!context) {
        QTextStream(stderr) << "mpv_create failed\n";
        return 3;
    }

    // These are all mature libmpv controls; keeping them in this probe makes
    // the capability claim executable before wiring a product backend.
    bool configured = true;
    configured &= setOption(context, "terminal", "no");
    configured &= setOption(context, "config", "no");
    configured &= setOption(context, "video", "no");
    configured &= setOption(context, "ao", "wasapi");
    configured &= setOption(context, "audio-exclusive", "no");
    configured &= setOption(context, "pause", "yes");
    configured &= setOption(context, "idle", "yes");
    configured &= setOption(context, "af",
                            "lavfi=[equalizer=f=1000:t=q:w=1:g=3,bass=g=2,treble=g=2,aecho=0.8:0.9:1000:0.3]");
    if (!configured) {
        mpv_terminate_destroy(context);
        return 4;
    }

    const int initialized = mpv_initialize(context);
    out << "initialize.result=" << initialized << " (" << mpv_error_string(initialized) << ")\n";
    if (initialized < 0) {
        mpv_terminate_destroy(context);
        return 5;
    }

    if (char* devices = mpv_get_property_string(context, "audio-device-list")) {
        out << "audio-device-list=" << devices << '\n';
        mpv_free(devices);
    }

    if (argc == 2) {
        const QByteArray utf8Path = QString::fromLocal8Bit(argv[1]).toUtf8();
        const char* command[] = {"loadfile", utf8Path.constData(), nullptr};
        const int loadResult = mpv_command(context, command);
        out << "loadfile.result=" << loadResult << " (" << mpv_error_string(loadResult) << ")\n";
        if (loadResult < 0) {
            mpv_terminate_destroy(context);
            return 6;
        }

        QElapsedTimer timer;
        timer.start();
        bool loaded = false;
        bool ended = false;
        int endReason = 0;
        int endError = 0;
        while (timer.elapsed() < 5000 && !ended) {
            const mpv_event* event = mpv_wait_event(context, 0.1);
            if (!event) continue;
            if (event->event_id == MPV_EVENT_FILE_LOADED) loaded = true;
            if (event->event_id == MPV_EVENT_END_FILE) {
                ended = true;
                const auto* end = static_cast<const mpv_event_end_file*>(event->data);
                if (end) {
                    endReason = static_cast<int>(end->reason);
                    endError = end->error;
                }
            }
            if (event->event_id == MPV_EVENT_SHUTDOWN) break;
        }
        out << "file_loaded=" << (loaded ? "true" : "false")
            << " end_file=" << (ended ? "true" : "false")
            << " end_reason=" << endReason << " end_error=" << endError;
        if (endError < 0) out << " (" << mpv_error_string(endError) << ')';
        out << '\n';
    }

    mpv_terminate_destroy(context);
    return 0;
}
