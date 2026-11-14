# ZotPaper PDF SDK 发布记录

## v-0.2.3-33.1.47

ZotPaper 0.2.3 普通 Flutter 平台使用的 PDF SDK 快照。保留上游包版本：Viewer、macOS、Windows 为 `33.1.47`，PDF 为 `33.2.13`；tag 后缀沿用 Viewer 基线命名。

- 固定 Viewer 内部 PDF、macOS、Windows 包到同一 tag，避免功能分支漂移。
- 优化滚动、缩放、高清预热、可取消搜索、页面释放和像素传输的性能及内存占用。
- 修复中文字体及 GBK 文本解码、文字批注坐标、书签 FitR 和 Windows 中文路径缩略图。
- 提供自定义滚动条、页面加载指示器、可见页面栅格与关闭回调能力。
- Android NDK 固定为 `28.2.13676358`，与应用宿主保持一致。

普通版与鸿蒙版维护不同的平台渲染实现，分别固定 tag；不将平台分支混合合入上游 `master`。
