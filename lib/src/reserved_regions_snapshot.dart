import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Whether a query could run, independently of whether it found any regions.
enum ReservedRegionsAvailability {
  available,
  inactive,
  unsupportedPlatform,
  osUnavailable,
  viewUnavailable,
  pluginUnavailable,
}

/// Division separates content; occlusion covers part of it.
enum ReservedRegionKind { division, occlusion }

/// An active region in the host Flutter view's logical coordinate space.
@immutable
class ReservedRegion {
  const ReservedRegion({required this.kind, required this.bounds});

  final ReservedRegionKind kind;
  final Rect bounds;

  /// Converts to a translated widget's local space (e.g. after SafeArea).
  ///
  /// Get [originInFlutterView] with RenderBox.localToGlobal(Offset.zero).
  /// This helper does not account for scaled or rotated widget transforms.
  Rect boundsRelativeTo(Offset originInFlutterView) =>
      bounds.shift(-originInFlutterView);
}

/// Immutable result of one native query.
///
/// When [availability] is available, [regions] is non-null: an empty list means
/// the query succeeded and no active regions were found. Otherwise it is null.
/// [viewSize] is the size of the queried Flutter host view, not the whole device.
@immutable
class ReservedRegionsSnapshot {
  ReservedRegionsSnapshot._(
    this.availability,
    this.viewSize,
    List<ReservedRegion>? regions,
  ) : regions = regions == null ? null : List.unmodifiable(regions);

  factory ReservedRegionsSnapshot.unavailable(
    ReservedRegionsAvailability availability,
  ) {
    if (availability == ReservedRegionsAvailability.available) {
      throw ArgumentError('An available result needs a size and region list.');
    }
    return ReservedRegionsSnapshot._(availability, null, null);
  }

  final ReservedRegionsAvailability availability;
  final Size? viewSize;
  final List<ReservedRegion>? regions;

  bool get isAvailable => availability == ReservedRegionsAvailability.available;

  /// Decodes the versioned Swift/channel contract. Malformed results throw.
  factory ReservedRegionsSnapshot.fromMessage(Object? message) {
    if (message is! Map || message['version'] != 1) {
      throw const FormatException('Unsupported reserved-regions message.');
    }
    final statusName = message['availability'];
    final matches = ReservedRegionsAvailability.values.where(
      (value) => value.name == statusName,
    );
    if (matches.isEmpty) {
      throw FormatException('Unknown availability: $statusName');
    }
    final status = matches.single;
    if (status != ReservedRegionsAvailability.available) {
      if (message['regions'] != null) {
        throw const FormatException('Unavailable regions must be null.');
      }
      return ReservedRegionsSnapshot.unavailable(status);
    }
    if (message['coordinateSpace'] != 'flutterView') {
      throw const FormatException('Unsupported region coordinate space.');
    }
    final width = _number(message, 'width', nonnegative: true);
    final height = _number(message, 'height', nonnegative: true);
    final entries = message['regions'];
    if (entries is! List) {
      throw const FormatException('Available regions must be a list.');
    }
    final regions = entries.map((entry) {
      if (entry is! Map) throw const FormatException('Invalid region.');
      final kinds = ReservedRegionKind.values.where(
        (value) => value.name == entry['kind'],
      );
      if (kinds.isEmpty) throw const FormatException('Unknown region kind.');
      final bounds = Rect.fromLTWH(
        _number(entry, 'x'),
        _number(entry, 'y'),
        _number(entry, 'width', nonnegative: true),
        _number(entry, 'height', nonnegative: true),
      );
      if (!bounds.isFinite) {
        throw const FormatException('Non-finite reserved-region rectangle.');
      }
      return ReservedRegion(kind: kinds.single, bounds: bounds);
    }).toList();
    return ReservedRegionsSnapshot._(status, Size(width, height), regions);
  }

  static double _number(
    Map<dynamic, dynamic> map,
    String key, {
    bool nonnegative = false,
  }) {
    final value = map[key];
    if (value is! num || !value.isFinite || (nonnegative && value < 0)) {
      throw FormatException('Invalid region metric: $key');
    }
    return value.toDouble();
  }
}
