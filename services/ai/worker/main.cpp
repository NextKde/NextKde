#include <LiquidAI/DepthGenerator.h>
#include <LiquidAI/ModelManager.h>
#include <QStandardPaths>
#include <QDirIterator>
#include <QDir>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QDateTime>
#include <algorithm>
#include <vector>
#include <LiquidAI/SpatialAssetGenerator.h>

#include <QCoreApplication>
#include <QNetworkProxyFactory>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

#include <filesystem>
#include <iostream>
#include <string>

#ifdef Q_OS_LINUX
#include <sys/resource.h>
#include <fcntl.h>
#include <unistd.h>
#endif

namespace {

bool trimSpatialCache(const QString &keep) {
    const qint64 limit=2LL*1024*1024*1024;
    const QString root=QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)+"/liquid-shell/wallpapers";
    struct Group {QString path; qint64 bytes; QDateTime time;};
    std::vector<Group> groups; qint64 total=0;
    for(const auto &dir:QDir(root).entryInfoList(QDir::Dirs|QDir::NoDotAndDotDot|QDir::NoSymLinks)) {
        qint64 size=0;
        for(QDirIterator it(dir.absoluteFilePath(),QDir::Files|QDir::NoSymLinks,QDirIterator::Subdirectories);it.hasNext();)
            size+=it.nextFileInfo().size();
        total+=size; groups.push_back({dir.absoluteFilePath(),size,dir.lastModified()});
    }
    std::sort(groups.begin(),groups.end(),[](const Group &a,const Group &b){return a.time<b.time;});
    for(const auto &g:groups) {
        if(total<=limit) break;
        if(g.path==keep) continue;
        if(QDir(g.path).removeRecursively()) total-=g.bytes;
    }
    return total<=limit;
}

constexpr std::size_t maximumRequestBytes = 64 * 1024;

std::filesystem::path pathFromQString(const QString &value)
{
#ifdef Q_OS_WIN
    return std::filesystem::path(value.toStdWString());
#else
    return std::filesystem::path(value.toLocal8Bit().constData());
#endif
}

QString pathToQString(const std::filesystem::path &path)
{
#ifdef Q_OS_WIN
    return QString::fromStdWString(path.native());
#else
    return QString::fromLocal8Bit(path.native().c_str());
#endif
}

QByteArray errorResponse(const QString &requestId, const QString &code,
                         const QString &message, bool retryable)
{
    return QJsonDocument(QJsonObject{
        {QStringLiteral("version"), 1},
        {QStringLiteral("requestId"), requestId},
        {QStringLiteral("ok"), false},
        {QStringLiteral("error"), QJsonObject{
            {QStringLiteral("code"), code},
            {QStringLiteral("message"), message},
            {QStringLiteral("retryable"), retryable},
        }},
    }).toJson(QJsonDocument::Compact);
}

QByteArray handleRequest(const QByteArray &line, LiquidAI::DepthGenerator &generator)
{
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return errorResponse({}, QStringLiteral("invalid-worker-request"),
                             QStringLiteral("AI worker 请求格式无效"), false);

    const QJsonObject request = document.object();
    const QString requestId = request.value(QStringLiteral("requestId")).toString();
    const QString operation = request.value(QStringLiteral("operation")).toString();
    if (request.value(QStringLiteral("version")).toInt() != 1)
        return errorResponse(requestId, "unsupported-worker-request", "协议版本无效", false);
    auto progress = [requestId](const std::string &stage, std::int64_t received, std::int64_t total) {
        const auto data = QJsonDocument(QJsonObject{
            {"version", 1}, {"requestId", requestId}, {"event", "progress"},
            {"stage", QString::fromStdString(stage)},
            {"received", double(received)}, {"total", double(total)}
        }).toJson(QJsonDocument::Compact);
        std::cout << data.constData() << '\n' << std::flush;
    };
    LiquidAI::ModelManager::progress = progress;
    const QString cache = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
        + "/liquid-shell/";
    auto success = [requestId](const QJsonObject &result) {
        return QJsonDocument(QJsonObject{{"version", 1}, {"requestId", requestId},
            {"ok", true}, {"result", result}}).toJson(QJsonDocument::Compact);
    };
    auto bytes = [](const QString &directory) {
        qint64 size = 0;
        QDirIterator files(directory, QDir::Files | QDir::NoSymLinks, QDirIterator::Subdirectories);
        while (files.hasNext()) { files.next(); size += files.fileInfo().size(); }
        return double(size);
    };
    if (operation == "spatial.initialize") {
        LiquidAI::ModelManager manager;
        std::filesystem::path path;
        std::string error;
        if (!manager.ensureDepthAnythingV2Small(&path, &error)
            || !manager.ensureForegroundIsNet(&path, &error))
            return errorResponse(requestId, "model-initialization-failed",
                                 QString::fromStdString(error), false);
        return success({{"modelsReady", true}, {"modelBytes", bytes(cache + "models")},
                        {"generatedBytes", bytes(cache + "wallpapers")}});
    }
    if (operation == "spatial.inspect") {
        bool ready = true;
        const std::pair<QString, const char *> models[] = {
            {"depth-anything-v2-small-vits.onnx", LiquidAI::ModelManager::modelSha256},
            {"isnet-general-use.onnx", LiquidAI::ModelManager::foregroundModelSha256}};
        for (const auto &model : models) {
            QFile file(cache + "models/" + model.first);
            QCryptographicHash hash(QCryptographicHash::Sha256);
            const bool opened = file.open(QIODevice::ReadOnly);
            if (!opened || !hash.addData(&file) || hash.result().toHex() != model.second)
                ready = false;
        }
        return success({{"modelsReady", ready}, {"modelBytes", bytes(cache + "models")},
                        {"generatedBytes", bytes(cache + "wallpapers")}});
    }
    if (operation == "spatial.clear") {
        const QString kind = request.value("imagePath").toString();
        if (kind != "generated" && kind != "models" && kind != "all")
            return errorResponse(requestId, "invalid-cache-kind", "缓存类型无效", false);
        // This worker is sequential. No generation can race with deletion.
        bool ok = true;
        for (const QString &name : {QString("models"), QString("wallpapers")}) {
            if (kind != "all" && (kind == "generated" ? name != "wallpapers" : name != "models"))
                continue;
            QDir directory(cache + name);
            if (directory.exists() && !directory.removeRecursively()) ok = false;
        }
        if (!ok) return errorResponse(requestId, "cache-delete-failed", "部分资源无法删除，请重试", false);
        // Drop inference sessions after deleting model files.
        return success({{"cleared", kind}});
    }
    if (operation != "depth.generate")
        return errorResponse(requestId, "unsupported-worker-request", "未知的 AI 操作", false);

    const QString imagePath = request.value(QStringLiteral("imagePath")).toString();
    if (imagePath.isEmpty() || imagePath.size() > 32768)
        return errorResponse(requestId, QStringLiteral("invalid-image-path"),
                             QStringLiteral("图片路径无效"), false);

    progress("正在生成深度图", -1, -1);
    const auto result = generator.generate(pathFromQString(imagePath));
    if (!result.success) {
        return errorResponse(requestId, QStringLiteral("depth-generation-failed"),
                             QString::fromStdString(result.error), false);
    }

    LiquidAI::SpatialAssetResult scene;
    if (request.value(QStringLiteral("prepareSpatial")).toBool(false)) {
        progress("正在分离前景与补齐背景", -1, -1);
        LiquidAI::SpatialAssetGenerator sceneGenerator;
        scene = sceneGenerator.generate(pathFromQString(imagePath),
                                        result.depthPath);
        if (!scene.success)
            std::cerr << "[spatial-assets] " << scene.error << '\n';
    }

    const QString keep=QFileInfo(pathToQString(result.depthPath)).absolutePath();
    if(!trimSpatialCache(keep)) {
        QDir(keep).removeRecursively();
        return errorResponse(requestId,"cache-limit","空间壁纸缓存无法保持在 2 GB 内",false);
    }

    return QJsonDocument(QJsonObject{
        {QStringLiteral("version"), 1},
        {QStringLiteral("requestId"), requestId},
        {QStringLiteral("ok"), true},
        {QStringLiteral("result"), QJsonObject{
            {QStringLiteral("depthPath"), pathToQString(result.depthPath)},
            {QStringLiteral("width"), result.width},
            {QStringLiteral("height"), result.height},
            {QStringLiteral("cached"), result.cached},
            {QStringLiteral("model"), QStringLiteral("depth-anything-v2-small-vits-onnx-v1")},
            {QStringLiteral("contract"),
             QString::fromLatin1(LiquidAI::DepthGenerator::contractVersion)},
            {QStringLiteral("backgroundPath"), scene.success
                ? pathToQString(scene.backgroundPath) : QString()},
            {QStringLiteral("mattePath"), scene.success
                ? pathToQString(scene.mattePath) : QString()},
            {QStringLiteral("influencePath"), scene.success
                ? pathToQString(scene.influencePath) : QString()},
            {QStringLiteral("spatialContract"), scene.success
                ? QString::fromLatin1(LiquidAI::SpatialAssetGenerator::contractVersion)
                : QString()},
        }},
    }).toJson(QJsonDocument::Compact);
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QNetworkProxyFactory::setUseSystemConfiguration(true);
#ifdef Q_OS_LINUX
    // If the machine is under memory pressure, prefer reclaiming this
    // optional worker over the platform daemon that owns desktop controls.
    setpriority(PRIO_PROCESS, 0, 10);
    const int oomScore = open("/proc/self/oom_score_adj", O_WRONLY | O_CLOEXEC);
    if (oomScore >= 0) {
        constexpr char value[] = "500";
        (void)write(oomScore, value, sizeof(value) - 1);
        close(oomScore);
    }
#endif
    LiquidAI::DepthGenerator generator;

    std::string line;
    line.reserve(maximumRequestBytes);
    bool oversized = false;
    char character = 0;
    while (std::cin.get(character)) {
        if (character != '\n') {
            if (line.size() < maximumRequestBytes)
                line.push_back(character);
            else
                oversized = true;
            continue;
        }

        const QByteArray response = oversized
            ? errorResponse({}, QStringLiteral("worker-request-too-large"),
                            QStringLiteral("AI worker 请求超过大小限制"), false)
            : handleRequest(QByteArray::fromStdString(line), generator);
        std::cout.write(response.constData(), response.size());
        std::cout.put('\n');
        std::cout.flush();
        line.clear();
        oversized = false;
    }
    return 0;
}
