#pragma once

#include <opencv2/core.hpp>

#include <memory>
#include <string>

namespace LiquidAI {

// Optional salient-object matte. The depth generator remains independent of
// this model; failures leave SpatialAssetGenerator's depth/GrabCut fallback.
class ForegroundSegmenter final {
public:
    ForegroundSegmenter();
    ~ForegroundSegmenter();
    ForegroundSegmenter(const ForegroundSegmenter &) = delete;
    ForegroundSegmenter &operator=(const ForegroundSegmenter &) = delete;

    cv::Mat segment(const cv::Mat &bgr, std::string *error);

private:
    struct Runtime;
    std::unique_ptr<Runtime> m_runtime;
};

} // namespace LiquidAI
