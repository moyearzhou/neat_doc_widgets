import 'package:flutter/material.dart';

/// Applies reading colors to paper and page rasters only. Page spacing, loading
/// indicators, annotations and viewer controls must remain outside this surface.
class PdfPageRenderSurface extends StatelessWidget {
  const PdfPageRenderSurface({
    super.key,
    required this.colorFilter,
    required this.child,
  });

  final ColorFilter? colorFilter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Widget paper = ColoredBox(color: Colors.white, child: child);
    return colorFilter == null
        ? paper
        : ColorFiltered(colorFilter: colorFilter!, child: paper);
  }
}
