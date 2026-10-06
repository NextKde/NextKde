#pragma once

#include <filesystem>
#include <string>
#include <functional>
#include <cstdint>

namespace LiquidAI {

class ModelManager final {
public:
    using Progress = std::function<void(const std::string &, std::int64_t, std::int64_t)>;
    // Scoped by the worker's current request; never retained by the UI.
    static thread_local Progress progress;
    bool ensureDepthAnythingV2Small(std::filesystem::path *path,
                                    std::string *error) const;
    bool ensureForegroundIsNet(std::filesystem::path *path,
                               std::string *error) const;

    static constexpr const char *modelId = "depth-anything-v2-small-vits-onnx-v1";
    static constexpr const char *modelSha256 =
        "46c4e8eeda3a27f34701831b6a2ec7753d7b38779b215acb5633424703deed8f";
    static constexpr const char *modelUrl =
        "https://github.com/fabio-sim/Depth-Anything-ONNX/releases/download/v2.0.0/depth_anything_v2_vits_dynamic.onnx";
    static constexpr const char *foregroundModelSha256 =
        "60920e99c45464f2ba57bee2ad08c919a52bbf852739e96947fbb4358c0d964a";
    static constexpr const char *foregroundModelUrl =
        "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx";
};

} // namespace LiquidAI
