#include "FlatpakTransactionProcess.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <csignal>
#include <sys/prctl.h>
#include <unistd.h>

namespace FlatpakTransactionProcess {
QVariantMap run(const QVariantMap& request, const Cancelled& cancelled, const Progress& progress)
{
    QProcess process;
    process.setProgram(QCoreApplication::applicationDirPath() + "/kos-flatpak-worker");
    process.setArguments({"--flatpak-transaction-helper"});
    const auto parent = ::getpid();
    process.setChildProcessModifier([parent] {
        if (::prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || ::getppid() != parent) ::_exit(127);
    });
    process.start();
    if (!process.waitForStarted(1000))
        return {{"code", "RESULT_UNKNOWN"}, {"message", "Cannot start the companion Flatpak transaction process."}};
    process.write(QJsonDocument(QJsonObject::fromVariantMap(request)).toJson(QJsonDocument::Compact));
    process.closeWriteChannel();
    QByteArray output;
    QVariantMap result;
    bool resultSeen = false, invalid = false, stopping = false;
    QElapsedTimer grace;
    const auto drain = [&] {
        output += process.readAllStandardOutput();
        // Library diagnostics are not the protocol and can include signed URLs.
        process.readAllStandardError();
        if (output.size() > 65536) { invalid = true; return; }
        while (output.contains('\n')) {
            const auto end = output.indexOf('\n');
            QJsonParseError error;
            const auto document = QJsonDocument::fromJson(output.left(end), &error);
            output.remove(0, end + 1);
            const auto object = document.object();
            if (error.error != QJsonParseError::NoError || !document.isObject() || resultSeen) { invalid = true; return; }
            if (object.value("type") == "progress") {
                const auto status = object.value("status").toString();
                const int value = object.value("progress").toInt(-1);
                if (status.size() > 4096 || value < -1 || value > 100) { invalid = true; return; }
                progress(status, value);
            } else if (object.value("type") == "result" && object.value("result").isObject()) {
                result = object.value("result").toObject().toVariantMap();
                resultSeen = true;
            } else { invalid = true; return; }
        }
    };
    while (process.state() != QProcess::NotRunning) {
        process.waitForFinished(50);
        drain();
        if (!stopping && (cancelled() || invalid)) {
            stopping = true;
            grace.start();
            process.terminate();
        }
        if (stopping && grace.elapsed() >= 2000 && process.state() != QProcess::NotRunning) {
            process.kill();
            if (!process.waitForFinished(1000))
                return {{"code", "RESULT_UNKNOWN"}, {"message", "The Flatpak transaction process did not stop. Inspect the actual installation before retrying."}};
        }
    }
    drain();
    if (cancelled())
        return {{"code", "CANCELLED"}, {"message", "The Flatpak transaction was interrupted. Installed state is re-read; interruption does not imply rollback."}};
    if (invalid || !resultSeen || !output.isEmpty() || process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0)
        return {{"code", "RESULT_UNKNOWN"}, {"message", "The companion Flatpak transaction did not return a valid result. Inspect the reconciled installation before retrying."}};
    return result;
}
}
