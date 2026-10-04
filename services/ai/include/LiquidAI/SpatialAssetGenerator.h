#pragma once

#include <filesystem>
#include <string>

namespace LiquidAI {

struct SpatialAssetResult {
    bool success = false;
    bool cached = false;
    std::filesystem::path backgroundPath;
    std::filesystem::path mattePath;
    std::filesystem::path influencePath;
    std::string error;
};

// Optional scene preparation. A failed or unsuitable segmentation leaves the
// depth result usable by the simpler renderer.
class SpatialAssetGenerator final {
public:
    static constexpr const char *contractVersion =
        "isnet-general-use-softmatte-lowhalo-v14";

    SpatialAssetResult generate(const std::filesystem::path &imagePath,
                                const std::filesystem::path &depthPath) const;
};

} // namespace LiquidAI
