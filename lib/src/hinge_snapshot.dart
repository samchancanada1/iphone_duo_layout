import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Whether this snapshot carries a live native hinge measurement.
enum HingeAvailability {
  available,
  waiting,
  noHinge,
  inactive,
  viewUnavailable,
  osUnavailable,
  unsupportedPlatform,
}

/// Native state; unknown preserves forward compatibility with future states.
enum HingeStatus { closed, partiallyOpen, fullyOpen, unknown }

@immutable
class HingeSnapshot {
  const HingeSnapshot._(this.availability, this.status, this.angleDegrees);

  factory HingeSnapshot.unavailable(HingeAvailability availability) {
    if (availability == HingeAvailability.available) {
      throw ArgumentError('An available hinge needs a status and angle.');
    }
    return HingeSnapshot._(availability, null, null);
  }

  final HingeAvailability availability;
  final HingeStatus? status;

  /// Degrees reported by the native API, without clamping or normalization.
  /// Null when a live measurement is unavailable; zero is a real measurement.
  final double? angleDegrees;
  double? get angleRadians =>
      angleDegrees == null ? null : angleDegrees! * math.pi / 180;
  bool get isAvailable => availability == HingeAvailability.available;

  factory HingeSnapshot.fromMessage(Object? message) {
    if (message is! Map || message['version'] != 1) {
      throw const FormatException('Unsupported hinge message.');
    }
    final availabilityName = message['availability'];
    final matches = HingeAvailability.values.where(
      (value) => value.name == availabilityName,
    );
    if (matches.isEmpty) {
      throw FormatException('Unknown hinge availability: $availabilityName');
    }
    final availability = matches.single;
    if (availability != HingeAvailability.available) {
      if (message['status'] != null || message['angleDegrees'] != null) {
        throw const FormatException('Unavailable hinge data must be null.');
      }
      return HingeSnapshot.unavailable(availability);
    }
    final statusName = message['status'];
    final statuses = HingeStatus.values.where(
      (value) => value.name == statusName,
    );
    final angle = message['angleDegrees'];
    if (statuses.isEmpty || angle is! num || !angle.isFinite) {
      throw const FormatException('Invalid native hinge status or angle.');
    }
    return HingeSnapshot._(availability, statuses.single, angle.toDouble());
  }
}
