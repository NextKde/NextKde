# 音源浏览器环境兼容资源

`browser.js` 是 core-js 3.45.1 的 URL、URLSearchParams、atob、btoa，以及 buffer 6.0.3 的静态浏览器构建。运行时由 SourceHost 内的 QuickJS 执行，不依赖 Node 或 npm，不包含网络端点、用户脚本或凭据。

从仓库根目录可重复生成：

```powershell
cd tools/sourcehost_compat
npm ci --ignore-scripts
npm run build
```

依赖及构建工具由 package-lock.json 固定。完整原许可见 LICENSES.txt。LX 事件、网络、定时器及加密边界仍由项目现有兼容层适配。
