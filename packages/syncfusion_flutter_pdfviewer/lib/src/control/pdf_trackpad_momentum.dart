import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

/// Supplies framework momentum because macOS suppresses native momentum events.
class PdfTrackpadMomentum {
  /// Creates a frame-driven, cancellable document pan animation.
  PdfTrackpadMomentum({required this.onUpdate, required this.onEnd}) {
    _ticker = Ticker(_tick);
  }

  /// Applies document offsets once per frame; returns whether the view moved.
  final bool Function(Offset) onUpdate;

  /// Refreshes visible tiles when the animation stops.
  final void Function() onEnd;
  late final Ticker _ticker;
  late FrictionSimulation _x;
  late FrictionSimulation _y;

  /// Starts momentum from the released document offset and viewport velocity.
  void start(Offset offset, Offset velocity, double zoom) {
    stop();
    if (velocity.distance < kMinFlingVelocity) {
      return;
    }
    // Match InteractiveViewer's default friction; velocity is in scene units.
    final Tolerance tolerance = Tolerance(velocity: 10 / zoom);
    _x = FrictionSimulation(
      0.0000135,
      offset.dx,
      -velocity.dx / zoom,
      tolerance: tolerance,
    );
    _y = FrictionSimulation(
      0.0000135,
      offset.dy,
      -velocity.dy / zoom,
      tolerance: tolerance,
    );
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final double seconds =
        elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final bool moved = onUpdate(Offset(_x.x(seconds), _y.x(seconds)));
    // The first frame starts at zero; later unchanged offsets mean a boundary.
    if ((seconds > 0 && !moved) || (_x.isDone(seconds) && _y.isDone(seconds))) {
      stop();
      onEnd();
    }
  }

  /// Stops immediately on a new gesture, click, or native inertia cancellation.
  void stop() => _ticker.stop();

  /// Releases the frame callback when its viewer is disposed.
  void dispose() => _ticker.dispose();
}
