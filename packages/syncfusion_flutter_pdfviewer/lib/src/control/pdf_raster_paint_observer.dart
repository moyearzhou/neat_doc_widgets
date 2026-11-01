import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports an actual raster paint, not a loaded document or an offscreen prefetch.
class PdfRasterPaintObserver extends SingleChildRenderObjectWidget {
  const PdfRasterPaintObserver({
    required this.image,
    required this.onPaint,
    required super.child,
    super.key,
  });
  final ui.Image? image;
  final ValueChanged<ui.Image> onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RasterObserver(image, onPaint);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RasterObserver renderObject,
  ) {
    renderObject.image = image;
    renderObject.onPaint = onPaint;
  }
}

class _RasterObserver extends RenderProxyBox {
  _RasterObserver(this.image, this.onPaint);
  ui.Image? image;
  ValueChanged<ui.Image> onPaint;
  ui.Image? _pending;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final painted = image;
    if (painted == null || size.isEmpty || identical(painted, _pending)) {
      return;
    }
    _pending = painted;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && identical(painted, image)) {
        onPaint(painted);
      }
      if (identical(_pending, painted)) {
        _pending = null;
      }
    });
  }
}
