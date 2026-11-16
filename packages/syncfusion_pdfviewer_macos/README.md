## ZotPaper private pub distribution

```yaml
syncfusion_pdfviewer_macos:
  hosted: https://pub.zotpaper.cn
  version: 33.1.47-zotpaper.1
```

This package preserves the runtime source of ZotPaper's standard release baseline. Use the exact version for this fork; platform variants must be selected explicitly. See UPSTREAM.md for provenance. Original Syncfusion licensing still applies; private hosting does not replace a valid upstream license.

﻿# Flutter PDF Viewer macOS

The macOS implementation of [Syncfusion® Flutter PDF Viewer](https://pub.dev/packages/syncfusion_flutter_pdfviewer) plugin.

## Usage

### Import the package

This package is an endorsed implementation of `syncfusion_flutter_pdfviewer` for the macOS platform since version `19.2.0-beta`, so it gets automatically added to your dependencies when you depend on package `syncfusion_flutter_pdfviewer`.

```yaml
...
dependencies:
  ...
  syncfusion_flutter_pdfviewer: ^20.3.0
  ...
...
```

### Loading PDF from network

To load PDF from network using SfPdfViewer.network in macOS, network access must be
enabled in your macOS application

On your `macos/Runner/DebugProfile.entitlements` file, add the following lines inside the `<dict>`
tag to enable the network access in your application:

```html
<key>com.apple.security.network.client</key>
<true/>
```