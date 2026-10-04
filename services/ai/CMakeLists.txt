find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)

find_path(ONNXRUNTIME_INCLUDE_DIR onnxruntime_cxx_api.h
    PATH_SUFFIXES onnxruntime onnxruntime/core/session REQUIRED)
find_library(ONNXRUNTIME_LIBRARY NAMES onnxruntime REQUIRED)

add_library(kos-ai STATIC
    include/LiquidAI/DepthGenerator.h
    include/LiquidAI/ModelManager.h
    include/LiquidAI/SpatialAssetGenerator.h
    src/DepthGenerator.cpp
    src/ForegroundSegmenter.h
    src/ForegroundSegmenter.cpp
    src/ModelManager.cpp
    src/SpatialAssetGenerator.cpp
)
target_include_directories(kos-ai
    PUBLIC include
    PRIVATE ${ONNXRUNTIME_INCLUDE_DIR} ${OpenCV_INCLUDE_DIRS})
target_link_libraries(kos-ai
    PUBLIC Qt6::Core Qt6::Network
    PRIVATE ${ONNXRUNTIME_LIBRARY} ${OpenCV_LIBS})
target_compile_features(kos-ai PUBLIC cxx_std_20)
set_target_properties(kos-ai PROPERTIES POSITION_INDEPENDENT_CODE ON)
