#include "depthmeshgeometry.h"

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <QVector3D>
#include <QFileInfo>
#include <QElapsedTimer>
#include <QDebug>
#include <vector>

namespace {
constexpr int columns = 321;
constexpr int rows = 181;
constexpr int edgeRefinement = 8;
constexpr int fineColumns = (columns - 1) * edgeRefinement + 1;
constexpr int fineRows = (rows - 1) * edgeRefinement + 1;
constexpr double farDistance = 3.3;
constexpr double depthSpan = 1.3;
constexpr double foregroundDepthScale = 0.55;
constexpr double backgroundDepthScale = 1.45;
constexpr double fovDegrees = 42.0;
constexpr double refinementThreshold = 0.08;

struct Vertex { float x, y, z, u, v; };

cv::Mat cropAndResize(const cv::Mat &input, double aspect,
                      int targetWidth, int targetHeight)
{
    const double sourceAspect = static_cast<double>(input.cols) / input.rows;
    cv::Rect crop(0, 0, input.cols, input.rows);
    if (sourceAspect > aspect) {
        crop.width = static_cast<int>(std::lround(input.rows * aspect));
        crop.x = (input.cols - crop.width) / 2;
    } else {
        crop.height = static_cast<int>(std::lround(input.cols / aspect));
        crop.y = (input.rows - crop.height) / 2;
    }
    cv::Mat resized;
    cv::resize(input(crop), resized, {targetWidth, targetHeight},
               0, 0, cv::INTER_LINEAR);
    return resized;
}

QString localPath(const QUrl &url)
{
    const QString path = url.isLocalFile() ? url.toLocalFile()
        : url.scheme().isEmpty() ? url.path(QUrl::FullyDecoded) : QString();
    return QFileInfo(path).isAbsolute() ? path : QString();
}
} // namespace

DepthMeshGeometry::DepthMeshGeometry(QQuick3DObject *parent)
    : QQuick3DGeometry(parent)
{
    setStride(sizeof(Vertex));
    setPrimitiveType(PrimitiveType::Triangles);
    addAttribute(Attribute::PositionSemantic, offsetof(Vertex, x), Attribute::F32Type);
    addAttribute(Attribute::TexCoord0Semantic, offsetof(Vertex, u), Attribute::F32Type);
}

void DepthMeshGeometry::setDepthPath(const QUrl &path)
{
    if (m_depthPath == path) return;
    m_depthPath = path;
    emit depthPathChanged();
    rebuild();
}

void DepthMeshGeometry::setMattePath(const QUrl &path)
{
    if (m_mattePath == path) return;
    m_mattePath = path;
    emit mattePathChanged();
    rebuild();
}

void DepthMeshGeometry::setImageZoom(float zoom)
{
    const float bounded = std::clamp(zoom, 1.0f, 1.5f);
    if (std::abs(m_imageZoom - bounded) < 1e-5f) return;
    m_imageZoom = bounded;
    emit imageZoomChanged();
    rebuild();
}

void DepthMeshGeometry::setOutputAspect(float aspect)
{
    const float bounded = std::clamp(aspect, 0.5f, 4.0f);
    if (std::abs(m_outputAspect - bounded) < 1e-5f) return;
    m_outputAspect = bounded;
    emit outputAspectChanged();
    rebuild();
}

void DepthMeshGeometry::setSourceAspect(float aspect)
{
    const float bounded = std::clamp(aspect, 0.01f, 100.0f);
    if (std::abs(m_sourceAspect - bounded) < 1e-5f) return;
    m_sourceAspect = bounded;
    emit sourceAspectChanged();
    rebuild();
}

void DepthMeshGeometry::setValid(bool valid)
{
    if (m_valid == valid) return;
    m_valid = valid;
    emit validChanged();
}

void DepthMeshGeometry::rebuild()
{
    QElapsedTimer buildTimer;
    buildTimer.start();
    setValid(false);
    setVertexData({});
    const QString depthFile = localPath(m_depthPath);
    const QString matteFile = localPath(m_mattePath);
    if (depthFile.isEmpty() || matteFile.isEmpty()) return;
    const cv::Mat rawDepth = cv::imread(depthFile.toStdString(),
                                        cv::IMREAD_UNCHANGED);
    const cv::Mat rawMatte = cv::imread(matteFile.toStdString(),
                                        cv::IMREAD_GRAYSCALE);
    if (rawDepth.empty() || rawDepth.type() != CV_16UC1 || rawMatte.empty()) return;
    const cv::Mat sourceDepth = cropAndResize(rawDepth, m_outputAspect,
                                              fineColumns, fineRows);
    const cv::Mat matte = cropAndResize(rawMatte, m_outputAspect,
                                        fineColumns, fineRows);
    const float pivotDepth = sourceDepth.at<std::uint16_t>(fineRows / 2, fineColumns / 2)
        / 65535.0f;
    // The mesh carries the reconstructed background. Fill the removed subject's
    // depth with a far value so its original near depth cannot pull background
    // pixels forward through the separate high-resolution foreground cutout.
    std::array<size_t, 256> backgroundHistogram{};
    size_t backgroundSamples = 0;
    for (int y = 0; y < fineRows; y += edgeRefinement) {
        for (int x = 0; x < fineColumns; x += edgeRefinement) {
            if (matte.at<std::uint8_t>(y, x) > 12) continue;
            ++backgroundHistogram[sourceDepth.at<std::uint16_t>(y, x) >> 8];
            ++backgroundSamples;
        }
    }
    double backgroundDepth = std::max(0.05, static_cast<double>(pivotDepth) * 0.5);
    size_t cumulative = 0;
    for (int bin = 0; bin < 256 && backgroundSamples > 0; ++bin) {
        cumulative += backgroundHistogram[bin];
        if (cumulative >= backgroundSamples / 5) {
            backgroundDepth = (bin + 0.5) / 256.0;
            break;
        }
    }
    cv::Mat expandedMatte;
    cv::threshold(matte, expandedMatte, 24, 255, cv::THRESH_BINARY);
    cv::dilate(expandedMatte, expandedMatte,
        cv::getStructuringElement(cv::MORPH_ELLIPSE, {15, 15}));
    cv::GaussianBlur(expandedMatte, expandedMatte, {}, 3.0);
    cv::Mat depth = sourceDepth.clone();
    for (int y = 0; y < fineRows; ++y) {
        auto *depthRow = depth.ptr<std::uint16_t>(y);
        const auto *matteRow = expandedMatte.ptr<std::uint8_t>(y);
        for (int x = 0; x < fineColumns; ++x) {
            const double weight = matteRow[x] / 255.0;
            depthRow[x] = static_cast<std::uint16_t>(std::lround(
                depthRow[x] * (1.0 - weight) + backgroundDepth * 65535.0 * weight));
        }
    }
    const double pivotDistance = farDistance - pivotDepth * depthSpan;
    const auto distanceAtDepth = [pivotDepth, pivotDistance](double value) {
        if (value >= pivotDepth)
            return pivotDistance - (value - pivotDepth) * depthSpan * foregroundDepthScale;
        return pivotDistance + (pivotDepth - value) * depthSpan * backgroundDepthScale;
    };
    const float newFocusDistance = static_cast<float>(pivotDistance);
    if (std::abs(m_focusDistance - newFocusDistance) > 1e-5f) {
        m_focusDistance = newFocusDistance;
        emit focusDistanceChanged();
    }

    const double tangent = std::tan(fovDegrees * CV_PI / 360.0);
    const double aspect = m_outputAspect;
    const double cropU = std::min(1.0, aspect / m_sourceAspect);
    const double cropV = std::min(1.0, m_sourceAspect / aspect);
    const double offsetU = (1.0 - cropU) * 0.5;
    const double offsetV = (1.0 - cropV) * 0.5;
    std::array<Vertex, columns * rows> vertices{};
    double maximumDistance = 0.0;
    float minX = std::numeric_limits<float>::max(), minY = minX, minZ = minX;
    float maxX = std::numeric_limits<float>::lowest(), maxY = maxX, maxZ = maxX;
    auto sampleDepth = [&depth](int x, int y) {
        return depth.at<std::uint16_t>(y, x) / 65535.0;
    };
    auto makeVertex = [&](int x, int y) {
        const double u = static_cast<double>(x) / (fineColumns - 1);
        const double v = static_cast<double>(y) / (fineRows - 1);
        const double z = distanceAtDepth(sampleDepth(x, y));
        maximumDistance = std::max(maximumDistance, z);
        const Vertex vertex {
            static_cast<float>((u * 2 - 1) * m_imageZoom * z * tangent * aspect),
            static_cast<float>((1 - v * 2) * m_imageZoom * z * tangent),
            static_cast<float>(-z),
            static_cast<float>(offsetU + u * cropU),
            static_cast<float>(1.0 - offsetV - v * cropV)
        };
        minX = std::min(minX, vertex.x); minY = std::min(minY, vertex.y);
        minZ = std::min(minZ, vertex.z);
        maxX = std::max(maxX, vertex.x); maxY = std::max(maxY, vertex.y);
        maxZ = std::max(maxZ, vertex.z);
        return vertex;
    };
    for (int y = 0; y < rows; ++y) {
        for (int x = 0; x < columns; ++x) {
            const int sampleX = x * edgeRefinement;
            const int sampleY = y * edgeRefinement;
            const size_t index = static_cast<size_t>(y) * columns + x;
            vertices[index] = makeVertex(sampleX, sampleY);
        }
    }

    std::vector<Vertex> triangles;
    triangles.reserve(static_cast<size_t>(columns - 1) * (rows - 1) * 6);
    int refinedCells = 0;
    auto appendTriangle = [&](const Vertex &a, const Vertex &b, const Vertex &c) {
        triangles.insert(triangles.end(), {a, b, c});
    };
    for (int y = 0; y + 1 < rows; ++y) for (int x = 0; x + 1 < columns; ++x) {
        const int tl = y * columns + x, tr = tl + 1, bl = tl + columns, br = bl + 1;
        const int fineX = x * edgeRefinement;
        const int fineY = y * edgeRefinement;
        double cellMin = 1.0, cellMax = 0.0;
        for (int sy = 0; sy <= edgeRefinement; ++sy) {
            for (int sx = 0; sx <= edgeRefinement; ++sx) {
                const double value = sampleDepth(fineX + sx, fineY + sy);
                cellMin = std::min(cellMin, value);
                cellMax = std::max(cellMax, value);
            }
        }
        if (cellMax - cellMin <= refinementThreshold) {
            appendTriangle(vertices[tl], vertices[bl], vertices[tr]);
            appendTriangle(vertices[tr], vertices[bl], vertices[br]);
            continue;
        }
        ++refinedCells;

        // Refine steep background relief locally. The separate matte cutout
        // supplies the foreground silhouette at image resolution.
        constexpr int patchSize = edgeRefinement + 1;
        std::array<Vertex, patchSize * patchSize> patchVertices;
        for (int sy = 0; sy < patchSize; ++sy) {
            for (int sx = 0; sx < patchSize; ++sx) {
                const int index = sy * patchSize + sx;
                patchVertices[index] = makeVertex(fineX + sx, fineY + sy);
            }
        }
        for (int sy = 0; sy < edgeRefinement; ++sy) {
            for (int sx = 0; sx < edgeRefinement; ++sx) {
                const int a = sy * patchSize + sx;
                const int b = a + 1;
                const int c = a + patchSize;
                const int d = c + 1;
                appendTriangle(patchVertices[a], patchVertices[c], patchVertices[b]);
                appendTriangle(patchVertices[b], patchVertices[c], patchVertices[d]);
            }
        }
    }
    if (triangles.empty()) return;
    setVertexData(QByteArray(reinterpret_cast<const char *>(triangles.data()),
        static_cast<qsizetype>(triangles.size() * sizeof(Vertex))));
    setBounds(QVector3D(minX, minY, minZ), QVector3D(maxX, maxY, maxZ));
    const float newBackgroundDistance = static_cast<float>(maximumDistance + 0.25);
    if (std::abs(m_backgroundDistance - newBackgroundDistance) > 1e-5f) {
        m_backgroundDistance = newBackgroundDistance;
        emit backgroundDistanceChanged();
    }
    setValid(true);
    update();
    qInfo().nospace() << "[Spatial3D] mesh ready: " << triangles.size() / 3
        << " triangles, " << refinedCells << " refined cells, "
        << buildTimer.elapsed() << " ms";
}
