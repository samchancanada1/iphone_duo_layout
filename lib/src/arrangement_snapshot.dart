import 'dart:ui';

import 'package:flutter/foundation.dart';

enum NativeArrangementMode { split, span }

enum NativeArrangementAxis { automatic, horizontal, vertical }

enum ArrangementAvailability {
  available,
  waiting,
  unsupportedPlatform,
  osUnavailable,
  viewUnavailable,
  inactive,
  geometryMismatch,
  unsupportedGeometry,
}

@immutable
class ArrangementPane {
  const ArrangementPane({
    required this.bounds,
    required this.visible,
    required this.zIndex,
  });

  /// Logical coordinates relative to the requested arrangement viewport.
  final Rect bounds;
  final bool visible;
  final int zIndex;

  @override
  bool operator ==(Object other) =>
      other is ArrangementPane &&
      bounds == other.bounds &&
      visible == other.visible &&
      zIndex == other.zIndex;
  @override
  int get hashCode => Object.hash(bounds, visible, zIndex);
}

/// A native probe measurement, not an inferred 50/50 Flutter layout.
@immutable
class ArrangementSnapshot {
  const ArrangementSnapshot._(
    this.availability,
    this.viewport,
    this.viewSize,
    this.primary,
    this.secondary,
  );

  factory ArrangementSnapshot.unavailable(
    ArrangementAvailability availability,
  ) {
    if (availability == ArrangementAvailability.available) {
      throw ArgumentError('An available arrangement needs native geometry.');
    }
    return ArrangementSnapshot._(availability, null, null, null, null);
  }

  final ArrangementAvailability availability;

  /// Requested rectangle in Flutter host-view coordinates.
  final Rect? viewport;
  final Size? viewSize;
  final ArrangementPane? primary;
  final ArrangementPane? secondary;
  bool get isAvailable => availability == ArrangementAvailability.available;

  factory ArrangementSnapshot.fromMessage(Object? message) {
    if (message is! Map || message['version'] != 1) {
      throw const FormatException('Unsupported arrangement message.');
    }
    final states = ArrangementAvailability.values.where(
      (v) => v.name == message['availability'],
    );
    if (states.isEmpty) {
      throw const FormatException('Unknown arrangement availability.');
    }
    final availability = states.single;
    if (availability != ArrangementAvailability.available) {
      if (message['primary'] != null ||
          message['secondary'] != null ||
          message['viewport'] != null ||
          message['viewSize'] != null) {
        throw const FormatException(
          'Unavailable arrangements must not carry geometry.',
        );
      }
      return ArrangementSnapshot.unavailable(availability);
    }
    if (message['coordinateSpace'] != 'viewport') {
      throw const FormatException('Unsupported arrangement coordinate space.');
    }
    final viewport = _rect(message['viewport']);
    final size = message['viewSize'];
    if (size is! Map) throw const FormatException('Missing host view size.');
    final viewSize = Size(
      _number(size, 'width', nonnegative: true),
      _number(size, 'height', nonnegative: true),
    );
    return ArrangementSnapshot._(
      availability,
      viewport,
      viewSize,
      _pane(message['primary']),
      _pane(message['secondary']),
    );
  }

  static ArrangementPane _pane(Object? value) {
    if (value is! Map || value['visible'] is! bool || value['zIndex'] is! int) {
      throw const FormatException('Invalid native pane.');
    }
    return ArrangementPane(
      bounds: _rect(value['bounds']),
      visible: value['visible'] as bool,
      zIndex: value['zIndex'] as int,
    );
  }

  static Rect _rect(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid arrangement rectangle.');
    }
    final result = Rect.fromLTWH(
      _number(value, 'x'),
      _number(value, 'y'),
      _number(value, 'width', nonnegative: true),
      _number(value, 'height', nonnegative: true),
    );
    if (!result.isFinite) {
      throw const FormatException('Non-finite arrangement rectangle.');
    }
    return result;
  }

  static double _number(Map map, String key, {bool nonnegative = false}) {
    final value = map[key];
    if (value is! num || !value.isFinite || (nonnegative && value < 0)) {
      throw FormatException('Invalid arrangement metric: $key');
    }
    return value.toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is ArrangementSnapshot &&
      availability == other.availability &&
      viewport == other.viewport &&
      viewSize == other.viewSize &&
      primary == other.primary &&
      secondary == other.secondary;
  @override
  int get hashCode =>
      Object.hash(availability, viewport, viewSize, primary, secondary);
}
