#pragma once

#include <filesystem>
#include <memory>
#include <string>

namespace Ort { class Env; class Session; }

namespace LiquidAI {

struct GenerateDepthResult {
    bool success = false;
    std::filesystem::path depthPath;
    int width = 0;
    int height = 0;
    bool cached = false;
    std::string error;
};

class DepthGenerator final {
public:
    DepthGenerator();
    ~DepthGenerator();
    DepthGenerator(const DepthGenerator &) = delete;
    DepthGenerator &operator=(const DepthGenerator &) = delete;

    GenerateDepthResult generate(const std::filesystem::path &imagePath);

    static constexpr const char *contractVersion =
        "da2-vits-dynamic-aspect518-rgb-imagenet-cubic-uint16-v1";

private:
    struct Runtime;
    std::unique_ptr<Runtime> m_runtime;
};

} // namespace LiquidAI
