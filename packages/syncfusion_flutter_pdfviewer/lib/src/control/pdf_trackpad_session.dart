import 'package:flutter/widgets.dart';

/// Anchors cumulative native pan/zoom data to the initial document transform.
class PdfTrackpadSession {
  /// Captures the initial scene point under the trackpad focal point.
  PdfTrackpadSession({
    required this.zoom,
    required this.focalPoint,
    required TransformationController transform,
  }) : sceneAnchor = transform.toScene(focalPoint);

  /// Initial zoom, never multiplied by a previous update's cumulative scale.
  final double zoom;

  /// Initial local focal point.
  final Offset focalPoint;

  /// Initial document point under the focal point.
  final Offset sceneAnchor;

  /// Resolves the target transform before the viewer applies document bounds.
  ({double zoom, Offset offset}) resolve({
    required double scale,
    required Offset pan,
    required double minZoom,
    required double maxZoom,
  }) {
    final double nextZoom = (zoom * scale).clamp(minZoom, maxZoom);
    return (
      zoom: nextZoom,
      offset: sceneAnchor - (focalPoint + pan) / nextZoom,
    );
  }
}
