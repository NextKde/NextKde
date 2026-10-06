#include <LiquidAI/DepthGenerator.h>
#include <LiquidAI/ModelManager.h>

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>

#include <onnxruntime_cxx_api.h>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <vector>

namespace {

constexpr qint64 maximumSourceBytes = 128LL * 1024 * 1024;
constexpr qint64 maximumPixels = 64LL * 1024 * 1024;
constexpr qint64 maximumModelPixels = 4LL * 1024 * 1024;

QString cacheRoot()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
        + QStringLiteral("/liquid-shell/wallpapers");
}

bool sourceDigest(const QString &path, QByteArray *digest, QString *error)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        *error = QStringLiteral("无法读取图片文件");
        return false;
    }
    if (file.size() <= 0 || file.size() > maximumSourceBytes) {
        *error = QStringLiteral("图片文件为空或超过大小上限");
        return false;
    }
    QCryptographicHash hash(QCryptographicHash::Sha256);
    while (!file.atEnd()) {
        const QByteArray chunk = file.read(1024 * 1024);
        if (chunk.isEmpty() && file.error() != QFileDevice::NoError) {
            *error = QStringLiteral("读取图片失败");
            return false;
        }
        hash.addData(chunk);
    }
    *digest = hash.result().toHex();
    return true;
}

QString pathToQString(const std::filesystem::path &path)
{
#ifdef _WIN32
    return QString::fromStdWString(path.native());
#else
    return QString::fromLocal8Bit(path.native().c_str());
#endif
}

std::filesystem::path qStringToPath(const QString &path)
{
#ifdef _WIN32
    return std::filesystem::path(path.toStdWString());
#else
    return std::filesystem::path(path.toLocal8Bit().constData());
#endif
}

cv::Mat decodeImageFile(const QString &path, int flags)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QByteArray encoded = file.readAll();
    if (encoded.isEmpty())
        return {};
    cv::Mat bytes(1, encoded.size(), CV_8UC1,
                  const_cast<char *>(encoded.constData()));
    return cv::imdecode(bytes, flags);
}

cv::Size modelSize(const cv::Size &source)
{
    const double scale = std::max(518.0 / source.width, 518.0 / source.height);
    const double scaledWidth = source.width * scale;
    const double scaledHeight = source.height * scale;
    if (scaledWidth > 4096.0 || scaledHeight > 4096.0)
        return {};
    const auto multipleOf14 = [](double value) {
        return std::max(518, static_cast<int>(std::lround(value / 14.0)) * 14);
    };
    return {multipleOf14(scaledWidth), multipleOf14(scaledHeight)};
}

std::vector<float> preprocess(const cv::Mat &bgr, const cv::Size &target)
{
    cv::Mat rgb, resized, floating;
    cv::cvtColor(bgr, rgb, cv::COLOR_BGR2RGB);
    cv::resize(rgb, resized, target, 0, 0, cv::INTER_CUBIC);
    resized.convertTo(floating, CV_32FC3, 1.0 / 255.0);

    constexpr float mean[] = {0.485f, 0.456f, 0.406f};
    constexpr float stddev[] = {0.229f, 0.224f, 0.225f};
    const auto planeSize = target.width * target.height;
    std::vector<float> tensor(3 * planeSize);
    for (int y = 0; y < target.height; ++y) {
        const auto *row = floating.ptr<cv::Vec3f>(y);
        for (int x = 0; x < target.width; ++x) {
            for (int c = 0; c < 3; ++c)
                tensor[c * planeSize + y * target.width + x]
                    = (row[x][c] - mean[c]) / stddev[c];
        }
    }
    return tensor;
}

bool writeAtomically(const QString &path, const QByteArray &content)
{
    QSaveFile file(path);
    return file.open(QIODevice::WriteOnly)
        && file.write(content) == content.size()
        && file.commit();
}

} // namespace

namespace LiquidAI {

struct DepthGenerator::Runtime {
    Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "liquid-ai"};
    std::unique_ptr<Ort::Session> session;
};

DepthGenerator::DepthGenerator()
    : m_runtime(std::make_unique<Runtime>())
{
}

DepthGenerator::~DepthGenerator() = default;

GenerateDepthResult DepthGenerator::generate(const std::filesystem::path &imagePath)
{
    GenerateDepthResult result;
    try {
        const QString sourcePath = pathToQString(imagePath);
        const QFileInfo sourceInfo(sourcePath);
        if (!sourceInfo.exists() || !sourceInfo.isFile()) {
            result.error = "图片不存在";
            return result;
        }
        QByteArray sourceHash;
        QString error;
        if (!sourceDigest(sourcePath, &sourceHash, &error)) {
            result.error = error.toStdString();
            return result;
        }

        cv::Mat image = decodeImageFile(sourceInfo.absoluteFilePath(), cv::IMREAD_COLOR);
        if (image.empty()) {
            result.error = "图片格式不支持或文件已损坏";
            return result;
        }
        if (static_cast<qint64>(image.cols) * image.rows > maximumPixels) {
            result.error = "图片像素数超过上限";
            return result;
        }
        result.width = image.cols;
        result.height = image.rows;

        const QString keyInput = QString::fromLatin1(sourceHash) + QLatin1Char('\n')
            + QString::fromLatin1(ModelManager::modelSha256) + QLatin1Char('\n')
            + QString::fromLatin1(contractVersion);
        const QString key = QCryptographicHash::hash(keyInput.toUtf8(),
            QCryptographicHash::Sha256).toHex();
        const QString outputDirectory = cacheRoot() + QLatin1Char('/') + key;
        const QString outputPath = outputDirectory + QStringLiteral("/depth.png");
        const QString metadataPath = outputDirectory + QStringLiteral("/metadata.json");
        if (QDir().mkpath(outputDirectory)) {
            cv::Mat cached = decodeImageFile(outputPath, cv::IMREAD_UNCHANGED);
            QFile metadataFile(metadataPath);
            if (!cached.empty() && cached.type() == CV_16UC1
                && cached.cols == image.cols && cached.rows == image.rows
                && metadataFile.open(QIODevice::ReadOnly)) {
                const auto metadata = QJsonDocument::fromJson(metadataFile.readAll()).object();
                if (metadata.value(QStringLiteral("model_sha256")).toString()
                        == QString::fromLatin1(ModelManager::modelSha256)
                    && metadata.value(QStringLiteral("contract")).toString()
                        == QString::fromLatin1(contractVersion)
                    && metadata.value(QStringLiteral("source_sha256")).toString()
                        == QString::fromLatin1(sourceHash)) {
                    result.success = true;
                    result.cached = true;
                    result.depthPath = qStringToPath(outputPath);
                    return result;
                }
            }
        } else {
            result.error = "无法创建深度图缓存目录";
            return result;
        }

        if (!m_runtime->session) {
            ModelManager modelManager;
            std::filesystem::path modelPath;
            std::string modelError;
            if (!modelManager.ensureDepthAnythingV2Small(&modelPath, &modelError)) {
                result.error = modelError;
                return result;
            }
            Ort::SessionOptions options;
            options.SetIntraOpNumThreads(4);
            options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
            m_runtime->session = std::make_unique<Ort::Session>(
                m_runtime->env, modelPath.c_str(), options);
            if (m_runtime->session->GetInputCount() != 1
                || m_runtime->session->GetOutputCount() != 1) {
                m_runtime->session.reset();
                result.error = "模型输入输出数量不符合约定";
                return result;
            }
            const auto inputType = m_runtime->session->GetInputTypeInfo(0);
            const auto inputInfo = inputType.GetTensorTypeAndShapeInfo();
            if (inputInfo.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT
                || inputInfo.GetShape() != std::vector<int64_t>{-1, 3, -1, -1}) {
                m_runtime->session.reset();
                result.error = "模型输入形状与版本契约不匹配";
                return result;
            }
        }

        if (ModelManager::progress) ModelManager::progress("正在生成深度图", -1, -1);
        const cv::Size inputSize = modelSize(image.size());
        if (inputSize.empty()
            || static_cast<qint64>(inputSize.width) * inputSize.height > maximumModelPixels) {
            result.error = "图片长宽比超出模型推理范围";
            return result;
        }
        auto pixels = preprocess(image, inputSize);
        const std::array<int64_t, 4> inputShape{
            1, 3, inputSize.height, inputSize.width};
        auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        auto input = Ort::Value::CreateTensor<float>(memory, pixels.data(), pixels.size(),
                                                      inputShape.data(), inputShape.size());
        auto inputName = m_runtime->session->GetInputNameAllocated(
            0, Ort::AllocatorWithDefaultOptions{});
        auto outputName = m_runtime->session->GetOutputNameAllocated(
            0, Ort::AllocatorWithDefaultOptions{});
        const char *inputNames[] = {inputName.get()};
        const char *outputNames[] = {outputName.get()};
        auto outputs = m_runtime->session->Run(Ort::RunOptions{nullptr}, inputNames,
                                                &input, 1, outputNames, 1);
        const auto outputInfo = outputs[0].GetTensorTypeAndShapeInfo();
        if (outputInfo.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT
            || outputInfo.GetShape() != std::vector<int64_t>{
                1, inputSize.height, inputSize.width}) {
            result.error = "模型输出形状与版本契约不匹配";
            return result;
        }

        cv::Mat raw(inputSize.height, inputSize.width, CV_32FC1,
                    outputs[0].GetTensorMutableData<float>());
        cv::Mat enlarged;
        cv::resize(raw, enlarged, image.size(), 0, 0, cv::INTER_CUBIC);
        double minimum = std::numeric_limits<double>::infinity();
        double maximum = -std::numeric_limits<double>::infinity();
        for (int y = 0; y < enlarged.rows; ++y) {
            const float *row = enlarged.ptr<float>(y);
            for (int x = 0; x < enlarged.cols; ++x) {
                if (!std::isfinite(row[x])) {
                    result.error = "模型输出包含无效深度值";
                    return result;
                }
                minimum = std::min(minimum, static_cast<double>(row[x]));
                maximum = std::max(maximum, static_cast<double>(row[x]));
            }
        }
        if (maximum <= minimum) {
            result.error = "模型输出没有有效深度范围";
            return result;
        }
        cv::Mat depth(image.size(), CV_16UC1);
        for (int y = 0; y < enlarged.rows; ++y) {
            const float *source = enlarged.ptr<float>(y);
            auto *destination = depth.ptr<uint16_t>(y);
            for (int x = 0; x < enlarged.cols; ++x) {
                const double normalized = (source[x] - minimum) / (maximum - minimum);
                destination[x] = static_cast<uint16_t>(std::lround(normalized * 65535.0));
            }
        }
        std::vector<unsigned char> png;
        if (!cv::imencode(".png", depth, png, {cv::IMWRITE_PNG_COMPRESSION, 3})) {
            result.error = "无法编码深度图 PNG";
            return result;
        }
        if (!writeAtomically(outputPath, QByteArray(
                reinterpret_cast<const char *>(png.data()), static_cast<qsizetype>(png.size())))) {
            result.error = "无法写入深度图缓存";
            return result;
        }
        const QJsonObject metadata{
            {QStringLiteral("version"), 1},
            {QStringLiteral("model"), QString::fromLatin1(ModelManager::modelId)},
            {QStringLiteral("model_sha256"), QString::fromLatin1(ModelManager::modelSha256)},
            {QStringLiteral("contract"), QString::fromLatin1(contractVersion)},
            {QStringLiteral("source_sha256"), QString::fromLatin1(sourceHash)},
            {QStringLiteral("created"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
            {QStringLiteral("width"), image.cols},
            {QStringLiteral("height"), image.rows},
        };
        if (!writeAtomically(metadataPath,
                QJsonDocument(metadata).toJson(QJsonDocument::Compact))) {
            QFile::remove(outputPath);
            result.error = "无法写入深度图元数据";
            return result;
        }
        result.success = true;
        result.depthPath = qStringToPath(outputPath);
        return result;
    } catch (const Ort::Exception &exception) {
        m_runtime->session.reset();
        result.error = exception.what();
        return result;
    } catch (const cv::Exception &exception) {
        result.error = exception.what();
        return result;
    } catch (const std::exception &exception) {
        result.error = exception.what();
        return result;
    }
}

} // namespace LiquidAI
