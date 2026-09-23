pragma Singleton
import QtQuick

// QML boundary for local depth and optional spatial assets. Transport, model
// downloads, hashing and CPU work remain owned by kos-platform / liquid-ai.
QtObject {
    id: root

    property int pendingCount: 0
    readonly property bool busy: pendingCount > 0

    signal finished(string imagePath, string depthPath, int width, int height,
                    bool cached, string model, string contract,
                    string backgroundPath, string mattePath,
                    string influencePath)
    signal failed(string imagePath, string code, string message, bool retryable)

    function generate(imagePath) {
        const path = String(imagePath || "").trim()
        if (!path) {
            failed(path, "invalid-image-path", "图片路径不能为空", false)
            return
        }

        pendingCount++
        PlatformClient.request("depth.generate", {
            imagePath: path,
            prepareSpatial: true
        }, response => {
            pendingCount = Math.max(0, pendingCount - 1)
            if (!response || !response.ok) {
                const error = response && response.error ? response.error : ({})
                failed(path, String(error.code || "depth-generation-failed"),
                    String(error.message || "深度图生成失败"), !!error.retryable)
                return
            }
            const result = response.result || ({})
            finished(path, String(result.depthPath || ""), Number(result.width || 0),
                Number(result.height || 0), !!result.cached,
                String(result.model || ""), String(result.contract || ""),
                String(result.backgroundPath || ""),
                String(result.mattePath || ""),
                String(result.influencePath || ""))
        })
    }
}
