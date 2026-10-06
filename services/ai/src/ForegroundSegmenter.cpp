#include "ForegroundSegmenter.h"

#include <LiquidAI/ModelManager.h>

#include <onnxruntime_cxx_api.h>

#include <opencv2/imgproc.hpp>

#include <array>
#include <algorithm>
#include <cmath>
#include <string_view>
#include <vector>

namespace LiquidAI {

namespace {
constexpr int inputSize = 1024;
constexpr int inputPixels = inputSize * inputSize;

std::vector<float> preprocess(const cv::Mat &bgr)
{
    cv::Mat rgb, resized;
    cv::cvtColor(bgr, rgb, cv::COLOR_BGR2RGB);
    cv::resize(rgb, resized, cv::Size(inputSize, inputSize),
               0, 0, cv::INTER_AREA);
    constexpr std::array<float, 3> mean{0.5f, 0.5f, 0.5f};
    constexpr std::array<float, 3> stddev{1.0f, 1.0f, 1.0f};
    std::vector<float> tensor(3 * inputPixels);
    for (int y = 0; y < inputSize; ++y) {
        const auto *row = resized.ptr<cv::Vec3b>(y);
        for (int x = 0; x < inputSize; ++x) {
            for (int channel = 0; channel < 3; ++channel)
                tensor[channel * inputPixels + y * inputSize + x]
                    = (row[x][channel] / 255.0f - mean[channel])
                        / stddev[channel];
        }
    }
    return tensor;
}
} // namespace

struct ForegroundSegmenter::Runtime {
    Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "liquid-ai-foreground"};
    std::unique_ptr<Ort::Session> session;
    bool unavailable = false;
};

ForegroundSegmenter::ForegroundSegmenter()
    : m_runtime(std::make_unique<Runtime>())
{
}

ForegroundSegmenter::~ForegroundSegmenter() = default;

cv::Mat ForegroundSegmenter::segment(const cv::Mat &bgr, std::string *error)
{
    try {
        if (bgr.empty() || bgr.type() != CV_8UC3) {
            *error = "前景分割输入格式无效";
            return {};
        }
        if (m_runtime->unavailable) {
            *error = "前景模型在当前 worker 中不可用";
            return {};
        }
        if (!m_runtime->session) {
            std::filesystem::path modelPath;
            ModelManager manager;
            if (!manager.ensureForegroundIsNet(&modelPath, error)) {
                m_runtime->unavailable = true;
                return {};
            }
            Ort::SessionOptions options;
            options.SetIntraOpNumThreads(4);
            options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
            auto session = std::make_unique<Ort::Session>(
                m_runtime->env, modelPath.c_str(), options);
            if (session->GetInputCount() != 1 || session->GetOutputCount() != 12
                || session->GetInputTypeInfo(0).GetTensorTypeAndShapeInfo()
                    .GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT
                || session->GetInputTypeInfo(0).GetTensorTypeAndShapeInfo()
                    .GetShape() != std::vector<int64_t>{1, 3, inputSize, inputSize}
                || session->GetOutputTypeInfo(0).GetTensorTypeAndShapeInfo()
                    .GetShape() != std::vector<int64_t>{1, 1, inputSize, inputSize}) {
                *error = "前景模型输入输出与版本契约不匹配";
                m_runtime->unavailable = true;
                return {};
            }
            auto inputName = session->GetInputNameAllocated(
                0, Ort::AllocatorWithDefaultOptions{});
            auto outputName = session->GetOutputNameAllocated(
                0, Ort::AllocatorWithDefaultOptions{});
            if (std::string_view(inputName.get()) != "input_image"
                || std::string_view(outputName.get()) != "output_image") {
                *error = "前景模型输入输出名称与版本契约不匹配";
                m_runtime->unavailable = true;
                return {};
            }
            m_runtime->session = std::move(session);
        }

        std::vector<float> pixels = preprocess(bgr);
        constexpr std::array<int64_t, 4> shape{1, 3, inputSize, inputSize};
        auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        auto input = Ort::Value::CreateTensor<float>(memory, pixels.data(),
                         pixels.size(), shape.data(), shape.size());
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
            || outputInfo.GetShape()
                != std::vector<int64_t>{1, 1, inputSize, inputSize}) {
            *error = "前景模型输出形状与版本契约不匹配";
            return {};
        }
        cv::Mat raw(inputSize, inputSize, CV_32FC1,
                    outputs[0].GetTensorMutableData<float>());
        double minimum = 0.0, maximum = 0.0;
        cv::minMaxLoc(raw, &minimum, &maximum);
        if (!std::isfinite(minimum) || !std::isfinite(maximum)
            || maximum - minimum < 0.00001) {
            *error = "前景模型输出无有效范围";
            return {};
        }
        cv::Mat normalized = (raw - minimum) * (255.0 / (maximum - minimum));
        cv::Mat enlarged, matte;
        cv::resize(normalized, enlarged, bgr.size(), 0, 0, cv::INTER_CUBIC);
        enlarged.convertTo(matte, CV_8UC1);
        return matte;
    } catch (const Ort::Exception &exception) {
        *error = exception.what();
    } catch (const cv::Exception &exception) {
        *error = exception.what();
    } catch (const std::exception &exception) {
        *error = exception.what();
    }
    return {};
}

} // namespace LiquidAI
