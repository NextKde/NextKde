#include <LiquidAI/SpatialAssetGenerator.h>

#include "ForegroundSegmenter.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
// OpenCV 5 把 Point/Rect 拆进 geometry 模块；4.x 里它们在 core（imgproc 已连带）。
#if __has_include(<opencv2/geometry/2d.hpp>)
#include <opencv2/geometry/2d.hpp>
#else
#include <opencv2/core.hpp>
#endif

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr int maximumDimension = 2560;

QString toQString(const fs::path &path)
{
#ifdef Q_OS_WIN
    return QString::fromStdWString(path.native());
#else
    return QString::fromLocal8Bit(path.native().c_str());
#endif
}

cv::Mat decode(const fs::path &path, int flags)
{
    QFile file(toQString(path));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QByteArray encoded = file.readAll();
    if (encoded.isEmpty())
        return {};
    cv::Mat bytes(1, encoded.size(), CV_8UC1,
                  const_cast<char *>(encoded.constData()));
    return cv::imdecode(bytes, flags);
}

bool writePng(const fs::path &path, const cv::Mat &image)
{
    std::vector<uchar> encoded;
    if (!cv::imencode(".png", image, encoded,
                      {cv::IMWRITE_PNG_COMPRESSION, 3}))
        return false;
    QSaveFile file(toQString(path));
    return file.open(QIODevice::WriteOnly)
        && file.write(reinterpret_cast<const char *>(encoded.data()),
                      static_cast<qsizetype>(encoded.size()))
            == static_cast<qsizetype>(encoded.size())
        && file.commit();
}

bool writeMetadata(const fs::path &path, int width, int height,
                   bool modelSegmentation)
{
    const QJsonObject object{
        {QStringLiteral("contract"),
         QString::fromLatin1(LiquidAI::SpatialAssetGenerator::contractVersion)},
        {QStringLiteral("width"), width},
        {QStringLiteral("height"), height},
        {QStringLiteral("segmentation"), modelSegmentation
            ? QStringLiteral("isnet-general-use") : QStringLiteral("depth-fallback")},
        {QStringLiteral("created"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
    };
    const QByteArray bytes = QJsonDocument(object).toJson(QJsonDocument::Compact);
    QSaveFile file(toQString(path));
    return file.open(QIODevice::WriteOnly)
        && file.write(bytes) == bytes.size() && file.commit();
}

cv::Mat largestComponent(const cv::Mat &binary, double minimumFraction,
                         double maximumFraction, bool allowBottom = false)
{
    cv::Mat labels, stats, centroids;
    const int count = cv::connectedComponentsWithStats(binary, labels, stats,
                                                        centroids, 8);
    const double pixels = static_cast<double>(binary.total());
    int selected = 0;
    for (int index = 1; index < count; ++index) {
        const int area = stats.at<int>(index, cv::CC_STAT_AREA);
        if (area < pixels * minimumFraction || area > pixels * maximumFraction)
            continue;
        const int left = stats.at<int>(index, cv::CC_STAT_LEFT);
        const int top = stats.at<int>(index, cv::CC_STAT_TOP);
        const int right = left + stats.at<int>(index, cv::CC_STAT_WIDTH);
        const int bottom = top + stats.at<int>(index, cv::CC_STAT_HEIGHT);
        if (left < 2 || top < 2 || right > binary.cols - 2
            || (!allowBottom && bottom > binary.rows - 2))
            continue;
        if (!selected || area > stats.at<int>(selected, cv::CC_STAT_AREA))
            selected = index;
    }
    return selected ? labels == selected : cv::Mat{};
}

void fillEnclosedHoles(cv::Mat &mask, const cv::Mat &depth)
{
    if (mask.empty())
        return;
    // Narrow gaps between petals can leave an opaque center connected to the
    // exterior through the matte. Close small boundary gaps first, then fill
    // only enclosed regions; large holes remain untouched.
    const int diameter = std::clamp(static_cast<int>(std::lround(
        std::min(mask.cols, mask.rows) * 0.025)), 9, 41) | 1;
    cv::Mat closed;
    cv::morphologyEx(mask, closed, cv::MORPH_CLOSE,
        cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                  cv::Size(diameter, diameter)));
    cv::Mat exterior = closed.clone();
    cv::floodFill(exterior, cv::Point(0, 0), cv::Scalar(255));
    cv::Mat holes;
    cv::bitwise_not(exterior, holes);
    cv::Mat labels, stats, centroids;
    const int count = cv::connectedComponentsWithStats(
        holes, labels, stats, centroids, 8);
    const int maximumHoleArea = static_cast<int>(mask.total() * 0.025);
    for (int index = 1; index < count; ++index) {
        const int area = stats.at<int>(index, cv::CC_STAT_AREA);
        if (area > maximumHoleArea) continue;
        const cv::Mat hole = labels == index;
        cv::Mat ring;
        cv::dilate(hole, ring, cv::getStructuringElement(cv::MORPH_ELLIPSE, {7, 7}));
        cv::bitwise_and(ring, mask, ring);
        if (!cv::countNonZero(ring)) continue;
        // Real gaps between arms/fingers see the farther background. Only
        // restore holes whose depth agrees with the surrounding subject.
        const double boundaryDepth = cv::mean(depth, ring)[0];
        cv::Mat supported = depth >= std::max(0.0, boundaryDepth - 0.10 * 65535);
        cv::bitwise_and(supported, hole, supported);
        if (cv::countNonZero(supported) >= area * 0.8)
            mask.setTo(255, hole);
    }
}

cv::Mat foregroundMask(const cv::Mat &photo, const cv::Mat &depth)
{
    cv::Mat candidate = depth > static_cast<ushort>(0.30 * 65535);
    candidate = largestComponent(candidate, 0.015, 0.55);
    if (candidate.empty())
        return {};

    const auto kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                                   cv::Size(21, 21));
    cv::Mat interior, vicinity;
    cv::erode(candidate, interior, kernel);
    cv::dilate(candidate, vicinity, kernel);
    cv::Mat labels(photo.size(), CV_8U, cv::Scalar(cv::GC_BGD));
    labels.setTo(cv::GC_PR_BGD, vicinity);
    labels.setTo(cv::GC_PR_FGD, candidate);
    labels.setTo(cv::GC_FGD, interior);
    cv::Mat backgroundModel, foregroundModel;
    cv::grabCut(photo, labels, cv::Rect(), backgroundModel, foregroundModel,
                4, cv::GC_INIT_WITH_MASK);
    cv::Mat binary = (labels == cv::GC_FGD) | (labels == cv::GC_PR_FGD);
    binary = largestComponent(binary, 0.015, 0.55);
    if (binary.empty())
        return {};
    cv::Mat overlap;
    cv::bitwise_and(binary, candidate, overlap);
    if (cv::countNonZero(overlap) < cv::countNonZero(candidate) * 0.65)
        return {};
    cv::morphologyEx(binary, binary, cv::MORPH_CLOSE,
                     cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                               cv::Size(3, 3)));
    fillEnclosedHoles(binary, depth);
    return binary;
}

// A close subject can leave the bottom of a photograph. Find a compact,
// central depth island above the ground, then let GrabCut extend it downwards.
// The side and top borders remain hard background to avoid selecting a field.
cv::Mat bottomEdgeForegroundMask(const cv::Mat &photo, const cv::Mat &depth)
{
    const int width = photo.cols;
    const int height = photo.rows;
    cv::Mat high = depth > static_cast<ushort>(0.58 * 65535);
    high.rowRange(static_cast<int>(height * 0.78), height).setTo(0);
    high.colRange(0, static_cast<int>(width * 0.12)).setTo(0);
    high.colRange(static_cast<int>(width * 0.88), width).setTo(0);
    cv::Mat seed = largestComponent(high, 0.004, 0.22);
    if (seed.empty())
        return {};

    const cv::Rect seedBox = cv::boundingRect(seed);
    // A stronger depth island can cover only part of a wide subject (flower
    // petals), while a broad fixed corridor can join a second subject through
    // nearby grass. Expand the seed at a lower depth threshold and size the
    // GrabCut search from that connected foreground island.
    cv::Mat expanded = depth > static_cast<ushort>(0.50 * 65535);
    expanded.rowRange(static_cast<int>(height * 0.78), height).setTo(0);
    expanded.colRange(0, static_cast<int>(width * 0.12)).setTo(0);
    expanded.colRange(static_cast<int>(width * 0.88), width).setTo(0);
    expanded = largestComponent(expanded, 0.004, 0.45, true);
    cv::Rect searchBox = seedBox;
    if (!expanded.empty()) {
        cv::Mat overlap;
        cv::bitwise_and(expanded, seed, overlap);
        const cv::Rect box = cv::boundingRect(expanded);
        if (cv::countNonZero(overlap) >= cv::countNonZero(seed) * 0.8
            && box.width < width * 0.75)
            searchBox = box;
        else
            expanded.release();
    }
    const int horizontalMargin = std::max(static_cast<int>(width * 0.025),
                                           static_cast<int>(searchBox.width * 0.12));
    const int left = std::max(2, searchBox.x - horizontalMargin);
    const int right = std::min(width - 2,
                               searchBox.x + searchBox.width + horizontalMargin);
    const int top = std::max(2, searchBox.y - searchBox.height / 6);
    if (right - left < width * 0.08 || top > height * 0.62)
        return {};

    cv::Mat labels(photo.size(), CV_8U, cv::Scalar(cv::GC_BGD));
    const cv::Rect corridor(left, top, right - left, height - top);
    labels(corridor).setTo(cv::GC_PR_BGD);
    cv::Mat likely = depth > static_cast<ushort>(0.48 * 65535);
    if (!expanded.empty())
        cv::bitwise_and(likely, expanded, likely);
    likely.colRange(0, left).setTo(0);
    likely.colRange(right, width).setTo(0);
    likely.rowRange(0, top).setTo(0);
    labels.setTo(cv::GC_PR_FGD, likely);
    cv::erode(seed, seed,
              cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(11, 11)));
    labels.setTo(cv::GC_FGD, seed);
    cv::Mat backgroundModel, foregroundModel;
    cv::grabCut(photo, labels, cv::Rect(), backgroundModel, foregroundModel,
                4, cv::GC_INIT_WITH_MASK);
    cv::Mat binary = (labels == cv::GC_FGD) | (labels == cv::GC_PR_FGD);
    cv::Mat nearSubject = depth > static_cast<ushort>(0.45 * 65535);
    cv::bitwise_and(binary, nearSubject, binary);
    binary = largestComponent(binary, 0.015, 0.35, true);
    if (binary.empty())
        return {};
    cv::Mat overlap;
    cv::bitwise_and(binary, seed, overlap);
    if (cv::countNonZero(overlap) < cv::countNonZero(seed) * 0.9)
        return {};
    const cv::Rect box = cv::boundingRect(binary);
    if (box.width > width * 0.65 || box.y > height * 0.5)
        return {};
    cv::morphologyEx(binary, binary, cv::MORPH_CLOSE,
                     cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                               cv::Size(11, 11)));
    fillEnclosedHoles(binary, depth);
    return binary;
}

cv::Mat extendedBackground(const cv::Mat &photo, const cv::Mat &subject)
{
    cv::Mat hidden;
    // The background plane travels farther than the foreground. Extend the
    // reconstruction beyond the maximum expected sampling offset so the
    // original subject cannot reappear as a ghost silhouette during motion.
    const int fillRadius = std::max(12, static_cast<int>(std::lround(
        std::min(photo.cols, photo.rows) * 0.012)));
    const int fillDiameter = fillRadius * 2 + 1;
    cv::dilate(subject, hidden,
               cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                         cv::Size(fillDiameter, fillDiameter)));
    cv::Mat distance, labels;
    cv::distanceTransform(hidden, distance, labels, cv::DIST_L2,
                          5, cv::DIST_LABEL_PIXEL);
    double minimum, maximum;
    cv::minMaxLoc(labels, &minimum, &maximum);
    std::vector<cv::Point> nearest(static_cast<size_t>(maximum) + 1,
                                   cv::Point(-1, -1));
    for (int y = 0; y < photo.rows; ++y) {
        const auto *hiddenRow = hidden.ptr<uchar>(y);
        const auto *labelRow = labels.ptr<int>(y);
        for (int x = 0; x < photo.cols; ++x) {
            if (!hiddenRow[x])
                nearest.at(labelRow[x]) = cv::Point(x, y);
        }
    }
    cv::Mat filled = photo.clone();
    for (int y = 0; y < photo.rows; ++y) {
        const auto *hiddenRow = hidden.ptr<uchar>(y);
        const auto *labelRow = labels.ptr<int>(y);
        auto *row = filled.ptr<cv::Vec3b>(y);
        for (int x = 0; x < photo.cols; ++x) {
            if (!hiddenRow[x])
                continue;
            const cv::Point point = nearest.at(labelRow[x]);
            if (point.x < 0)
                continue;
            const cv::Point reflected(2 * point.x - x, 2 * point.y - y);
            if (reflected.x >= 0 && reflected.x < photo.cols
                && reflected.y >= 0 && reflected.y < photo.rows
                && !hidden.at<uchar>(reflected))
                row[x] = photo.at<cv::Vec3b>(reflected);
            else
                row[x] = photo.at<cv::Vec3b>(point);
        }
    }
    cv::Mat softened, softMask;
    cv::GaussianBlur(filled, softened, cv::Size(), 2.0);
    cv::GaussianBlur(hidden, softMask, cv::Size(), 1.4);
    cv::Mat originalFloat, softenedFloat, alphaFloat, alpha3;
    photo.convertTo(originalFloat, CV_32FC3, 1.0 / 255.0);
    softened.convertTo(softenedFloat, CV_32FC3, 1.0 / 255.0);
    softMask.convertTo(alphaFloat, CV_32F, 1.0 / 255.0);
    cv::cvtColor(alphaFloat, alpha3, cv::COLOR_GRAY2BGR);
    cv::Mat blended = softenedFloat.mul(alpha3)
        + originalFloat.mul(cv::Scalar::all(1.0) - alpha3);
    blended.convertTo(blended, CV_8UC3, 255.0);
    return blended;
}

cv::Mat handInfluence(const cv::Mat &depth, const cv::Mat &subject)
{
    cv::Mat near = depth > static_cast<ushort>(0.82 * 65535);
    cv::bitwise_and(near, subject, near);
    near = largestComponent(near, 0.001, 0.30);
    if (near.empty())
        return cv::Mat(depth.size(), CV_8UC1, cv::Scalar(0));
    cv::dilate(near, near,
               cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                         cv::Size(101, 101)));
    cv::GaussianBlur(near, near, cv::Size(), 25.0);
    return near;
}

} // namespace

namespace LiquidAI {

SpatialAssetResult SpatialAssetGenerator::generate(const fs::path &imagePath,
                                                    const fs::path &depthPath) const
{
    SpatialAssetResult result;
    try {
        const fs::path directory = depthPath.parent_path() / "spatial-v4";
        result.backgroundPath = directory / "background.png";
        result.mattePath = directory / "matte.png";
        result.influencePath = directory / "influence.png";
        const fs::path metadataPath = directory / "metadata.json";

        const cv::Mat source = decode(imagePath, cv::IMREAD_COLOR);
        const cv::Mat sourceDepth = decode(depthPath, cv::IMREAD_UNCHANGED);
        if (source.empty() || sourceDepth.type() != CV_16UC1
            || source.size() != sourceDepth.size()) {
            result.error = "空间素材输入不匹配";
            return result;
        }
        const double scale = std::min(1.0, double(maximumDimension)
            / std::max(source.cols, source.rows));
        const int width = std::max(1, static_cast<int>(std::lround(source.cols * scale)));
        const int height = std::max(1, static_cast<int>(std::lround(source.rows * scale)));

        QFile metadataFile(toQString(metadataPath));
        if (metadataFile.open(QIODevice::ReadOnly)) {
            const QJsonObject metadata = QJsonDocument::fromJson(
                metadataFile.readAll()).object();
            if (metadata.value(QStringLiteral("contract")).toString()
                    == QString::fromLatin1(contractVersion)
                && metadata.value(QStringLiteral("segmentation")).toString()
                    == QStringLiteral("isnet-general-use")
                && metadata.value(QStringLiteral("width")).toInt() == width
                && metadata.value(QStringLiteral("height")).toInt() == height
                && decode(result.backgroundPath, cv::IMREAD_COLOR).size()
                    == cv::Size(width, height)
                && decode(result.mattePath, cv::IMREAD_GRAYSCALE).size()
                    == cv::Size(width, height)
                && decode(result.influencePath, cv::IMREAD_GRAYSCALE).size()
                    == cv::Size(width, height)) {
                result.success = true;
                result.cached = true;
                return result;
            }
        }

        cv::Mat photo, depth;
        if (source.size() != cv::Size(width, height)) {
            cv::resize(source, photo, cv::Size(width, height), 0, 0, cv::INTER_AREA);
            cv::resize(sourceDepth, depth, cv::Size(width, height), 0, 0,
                       cv::INTER_AREA);
        } else {
            photo = source;
            depth = sourceDepth;
        }
        cv::Mat mask;
        cv::Mat depthSupport;
        cv::Mat holeSupport;
        bool modelSegmentation = false;
        static ForegroundSegmenter segmenter;
        std::string segmentError;
        cv::Mat modelAlpha = segmenter.segment(photo, &segmentError);
        if (!modelAlpha.empty()) {
            cv::Mat proposed = modelAlpha > 64;
            proposed = largestComponent(proposed, 0.005, 0.60, true);
            if (!proposed.empty()) {
                cv::Mat strongDepth = depth > static_cast<ushort>(0.58 * 65535);
                strongDepth.rowRange(static_cast<int>(height * 0.78), height)
                    .setTo(0);
                strongDepth.colRange(0, static_cast<int>(width * 0.12))
                    .setTo(0);
                strongDepth.colRange(static_cast<int>(width * 0.88), width)
                    .setTo(0);
                strongDepth = largestComponent(strongDepth, 0.004, 0.22);
                cv::Mat overlap;
                if (!strongDepth.empty())
                    cv::bitwise_and(strongDepth, proposed, overlap);
                if (!strongDepth.empty() && cv::countNonZero(overlap)
                        >= cv::countNonZero(strongDepth) * 0.55) {
                    mask = proposed;
                    // Depth-guided GrabCut can recover holes in a salient
                    // matte (bright palms and dark flower centers), but only
                    // next to pixels already selected by the model. Do not
                    // grow into a separate person or nearby ground.
                    cv::Mat depthMask = foregroundMask(photo, depth);
                    if (depthMask.empty())
                        depthMask = bottomEdgeForegroundMask(photo, depth);
                    if (!depthMask.empty()) {
                        cv::Mat vicinity, support;
                        cv::dilate(mask, vicinity,
                            cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                                      cv::Size(31, 31)));
                        cv::bitwise_and(depthMask, vicinity, support);
                        cv::bitwise_or(mask, support, mask);
                        depthSupport = std::move(support);
                    }
                    const cv::Mat beforeRepair = mask.clone();
                    fillEnclosedHoles(mask, depth);
                    cv::subtract(mask, beforeRepair, holeSupport);
                    modelSegmentation = true;
                }
            }
        }
        if (mask.empty())
            mask = foregroundMask(photo, depth);
        if (mask.empty())
            mask = bottomEdgeForegroundMask(photo, depth);
        if (mask.empty()) {
            result.error = "未找到适合分层的独立前景";
            return result;
        }
        cv::Mat alpha;
        if (modelSegmentation) {
            // Preserve IS-Net's soft confidence along hair and grass edges.
            // The previous binary threshold discarded it and a later blur
            // could only create a broad halo, not restore the lost contour.
            cv::Mat allowed;
            cv::dilate(mask, allowed,
                cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                          cv::Size(17, 17)));
            alpha = cv::Mat::zeros(modelAlpha.size(), CV_8UC1);
            modelAlpha.copyTo(alpha, allowed);
            if (!depthSupport.empty())
                alpha.setTo(255, depthSupport);
            if (!holeSupport.empty())
                alpha.setTo(255, holeSupport);
            cv::GaussianBlur(alpha, alpha, cv::Size(), 0.7);
        } else {
            cv::Mat matteCore;
            cv::erode(mask, matteCore,
                cv::getStructuringElement(cv::MORPH_ELLIPSE,
                                          cv::Size(3, 3)));
            cv::GaussianBlur(matteCore, alpha, cv::Size(), 0.9);
        }
        const cv::Mat background = extendedBackground(photo, mask);
        const cv::Mat influence = handInfluence(depth, mask);
        if (!QDir().mkpath(toQString(directory))
            || !writePng(result.backgroundPath, background)
            || !writePng(result.mattePath, alpha)
            || !writePng(result.influencePath, influence)
            || !writeMetadata(metadataPath, width, height, modelSegmentation)) {
            result.error = "无法写入空间壁纸缓存";
            return result;
        }
        result.success = true;
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
