#include <LiquidAI/ModelManager.h>

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QEventLoop>
#include <QElapsedTimer>

#include <limits>

namespace {

QString modelCacheDirectory()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
        + QStringLiteral("/liquid-shell/models");
}

std::filesystem::path toPath(const QString &path)
{
#ifdef _WIN32
    return std::filesystem::path(path.toStdWString());
#else
    return std::filesystem::path(path.toLocal8Bit().constData());
#endif
}

bool hashFile(const QString &path, QByteArray *digest)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    QCryptographicHash hash(QCryptographicHash::Sha256);
    while (!file.atEnd()) {
        const QByteArray chunk = file.read(1024 * 1024);
        if (chunk.isEmpty() && file.error() != QFileDevice::NoError)
            return false;
        hash.addData(chunk);
    }
    *digest = hash.result().toHex();
    return true;
}

bool ensureVerifiedModel(const QString &fileName, const char *expectedSha256,
                         const char *downloadUrl, std::filesystem::path *path,
                         std::string *error, int timeoutMs)
{
    const QString directory = modelCacheDirectory();
    if (directory.isEmpty() || !QDir().mkpath(directory)) {
        *error = "无法创建模型缓存目录";
        return false;
    }
    const QString destination = directory + QLatin1Char('/') + fileName;
    const std::string label = fileName.startsWith("depth-") ? "深度估计模型" : "前景分割模型";
    if (LiquidAI::ModelManager::progress)
        LiquidAI::ModelManager::progress("正在校验" + label, -1, -1);
    QByteArray digest;
    if (QFileInfo(destination).isFile() && hashFile(destination, &digest)
        && digest == QByteArray(expectedSha256)) {
        *path = toPath(destination);
        return true;
    }

    QFile::remove(destination);
    QNetworkAccessManager network;
    QNetworkRequest request{QUrl(QString::fromLatin1(downloadUrl))};
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setTransferTimeout(60000); // Fail stalled transfers, allow slow active downloads.
    QNetworkReply *reply = network.get(request);
    reply->setReadBufferSize(1024 * 1024);
    QSaveFile output(destination + QStringLiteral(".download"));
    if (!output.open(QIODevice::WriteOnly)) {
        reply->abort();
        reply->deleteLater();
        *error = "无法创建模型临时文件";
        return false;
    }

    constexpr qint64 maximumModelBytes = 200LL * 1024 * 1024;
    bool tooLarge = false;
    bool writeFailed = false;
    QObject::connect(reply, &QIODevice::readyRead, reply, [&] {
        const QByteArray chunk = reply->readAll();
        if (output.size() + chunk.size() > maximumModelBytes) {
            tooLarge = true;
            reply->abort();
            return;
        }
        if (output.write(chunk) != chunk.size()) {
            writeFailed = true;
            reply->abort();
        }
    });
    QElapsedTimer progressClock;
    progressClock.start();
    QObject::connect(reply, &QNetworkReply::downloadProgress, reply,
        [label, &progressClock](qint64 received, qint64 total) {
            if (progressClock.elapsed() < 200 && received != total)
                return;
            progressClock.restart();
            if (LiquidAI::ModelManager::progress)
                LiquidAI::ModelManager::progress("正在下载" + label, received, total);
        });
    QEventLoop loop;
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    QTimer timeout;
    timeout.setSingleShot(true);
    timeout.setInterval(timeoutMs);
    bool timedOut = false;
    QObject::connect(&timeout, &QTimer::timeout, reply, [&] {
        timedOut = true;
        reply->abort();
    });
    timeout.start();
    loop.exec();

    const QByteArray tail = reply->readAll();
    if (output.size() + tail.size() > maximumModelBytes)
        tooLarge = true;
    else if (!tail.isEmpty() && output.write(tail) != tail.size())
        writeFailed = true;
    const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const auto networkError = reply->error();
    const QString networkMessage = reply->errorString();
    reply->deleteLater();
    if (tooLarge || output.size() > maximumModelBytes) {
        output.cancelWriting();
        *error = "模型文件超过大小上限";
        return false;
    }
    if (writeFailed) {
        output.cancelWriting();
        *error = "模型写入失败，请检查磁盘空间";
        return false;
    }
    if (networkError != QNetworkReply::NoError || status < 200 || status >= 300) {
        output.cancelWriting();
        *error = timedOut ? "模型下载超时，请检查网络或代理后重试"
            : "模型下载失败：" + networkMessage.toStdString();
        return false;
    }
    if (!output.commit() || !hashFile(destination + QStringLiteral(".download"), &digest)
        || digest != QByteArray(expectedSha256)) {
        QFile::remove(destination + QStringLiteral(".download"));
        *error = "模型 SHA256 校验失败";
        return false;
    }
    if (!QFile::rename(destination + QStringLiteral(".download"), destination)) {
        QFile::remove(destination + QStringLiteral(".download"));
        *error = "无法安装已校验的模型";
        return false;
    }
    *path = toPath(destination);
    return true;
}

} // namespace

namespace LiquidAI {

thread_local ModelManager::Progress ModelManager::progress;

bool ModelManager::ensureDepthAnythingV2Small(std::filesystem::path *path,
                                             std::string *error) const
{
    return ensureVerifiedModel(QStringLiteral("depth-anything-v2-small-vits.onnx"),
                               modelSha256, modelUrl, path, error, 600000);
}

bool ModelManager::ensureForegroundIsNet(std::filesystem::path *path,
                                         std::string *error) const
{
    return ensureVerifiedModel(QStringLiteral("isnet-general-use.onnx"),
                               foregroundModelSha256, foregroundModelUrl,
                               path, error, 600000);
}

} // namespace LiquidAI
