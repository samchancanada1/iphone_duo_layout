import 'package:flutter/foundation.dart';

enum NativeToolbarPlacement { leading, trailing, bottom }

enum NativeToolbarPriority { automatic, low, high }

enum NativeToolbarAxis { automatic, horizontalOnly, verticalPreferred }

/// A native action. The title remains available to accessibility and overflow
/// menus even when iOS chooses an icon-only representation.
@immutable
class NativeToolbarItem {
  const NativeToolbarItem({
    required this.id,
    required this.title,
    this.systemImage,
    this.enabled = true,
    this.visible = true,
    this.placement = NativeToolbarPlacement.trailing,
    this.priority = NativeToolbarPriority.automatic,
    this.axis = NativeToolbarAxis.automatic,
  });

  final String id;
  final String title;
  final String? systemImage;
  final bool enabled;
  final bool visible;
  final NativeToolbarPlacement placement;
  final NativeToolbarPriority priority;
  final NativeToolbarAxis axis;

  @override
  bool operator ==(Object other) =>
      other is NativeToolbarItem &&
      id == other.id &&
      title == other.title &&
      systemImage == other.systemImage &&
      enabled == other.enabled &&
      visible == other.visible &&
      placement == other.placement &&
      priority == other.priority &&
      axis == other.axis;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    systemImage,
    enabled,
    visible,
    placement,
    priority,
    axis,
  );

  Map<String, Object?> toMessage() => {
    'id': id,
    'title': title,
    'systemImage': systemImage,
    'enabled': enabled,
    'visible': visible,
    'placement': placement.name,
    'priority': priority.name,
    'axis': axis.name,
  };
}

/// Immutable description of a system-managed toolbar, not a Flutter AppBar.
@immutable
class NativeToolbarConfiguration {
  NativeToolbarConfiguration({
    required this.title,
    Iterable<NativeToolbarItem> items = const [],
    Iterable<NativeToolbarItem> overflowItems = const [],
  }) : items = List.unmodifiable(items),
       overflowItems = List.unmodifiable(overflowItems) {
    final ids = <String>{};
    for (final item in [...this.items, ...this.overflowItems]) {
      if (item.id.trim().isEmpty || item.title.trim().isEmpty) {
        throw ArgumentError('Toolbar actions need a non-empty id and title.');
      }
      if (!ids.add(item.id)) {
        throw ArgumentError('Duplicate toolbar action id: ${item.id}');
      }
      if (item.systemImage != null && item.systemImage!.trim().isEmpty) {
        throw ArgumentError('Use null for an action without a system image.');
      }
    }
  }

  final String title;
  final List<NativeToolbarItem> items;

  /// Persistent entries in the system overflow menu. Placement, axis and
  /// visibility priority apply only to [items], not these menu-only actions.
  final List<NativeToolbarItem> overflowItems;

  @override
  bool operator ==(Object other) =>
      other is NativeToolbarConfiguration &&
      title == other.title &&
      listEquals(items, other.items) &&
      listEquals(overflowItems, other.overflowItems);

  @override
  int get hashCode =>
      Object.hash(title, Object.hashAll(items), Object.hashAll(overflowItems));

  Map<String, Object?> toMessage() => {
    'title': title,
    'items': items.map((item) => item.toMessage()).toList(),
    'overflowItems': overflowItems.map((item) => item.toMessage()).toList(),
  };
}

enum NativeToolbarAvailability {
  available,
  unsupportedPlatform,
  osUnavailable,
  viewUnavailable,
  hostUnsupported,
  busy,
  detached,
}

@immutable
class NativeToolbarStatus {
  const NativeToolbarStatus(this.availability);
  final NativeToolbarAvailability availability;
  bool get isAvailable => availability == NativeToolbarAvailability.available;

  factory NativeToolbarStatus.fromMessage(Object? message) {
    if (message is! Map || message['version'] != 1) {
      throw const FormatException('Unsupported toolbar message.');
    }
    final matches = NativeToolbarAvailability.values.where(
      (status) => status.name == message['availability'],
    );
    if (matches.isEmpty) {
      throw const FormatException('Unknown toolbar availability.');
    }
    return NativeToolbarStatus(matches.single);
  }
}
