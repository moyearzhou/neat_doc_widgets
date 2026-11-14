# ZotPaper PDF SDK 发布记录

## v-0.2.3-33.1.47-ohos

ZotPaper 0.2.3 鸿蒙平台使用的 PDF SDK 快照。保留上游包版本：Viewer 为 `33.1.47`，PDF 为 `33.2.13`；tag 后缀沿用 Viewer 基线命名。

- 固定 Viewer 内部 PDF 包到同一鸿蒙 tag，与宿主 Git 依赖保持一致。
- 同步可取消搜索、高清预热、页面加载指示器、文字解码、批注坐标与书签 FitR 修复。
- 保留鸿蒙 PDFium 渲染、视口优先队列、过期任务取消、像素缓冲释放和鼠标滚轮兼容。
- 提供宿主可见页面栅格、关闭回调及资源生命周期能力。

鸿蒙宿主需同时将 `syncfusion_flutter_pdfviewer` 和 `syncfusion_flutter_pdf` 指向本 tag 对应的包路径。
普通版与鸿蒙版维护不同的平台渲染实现，分别固定 tag；不将平台分支混合合入上游 `master`。
