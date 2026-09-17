import 'dart:async';

import 'package:flutter/widgets.dart';

import 'arrangement_bridge.dart';
import 'arrangement_snapshot.dart';

/// Experimental native layout-result bridge with a single Flutter widget tree.
/// Requires finite, nonzero constraints and an unscaled/unrotated viewport.
/// Split never invents region geometry. Span works without a native probe.
class NativeArrangement extends StatefulWidget {
  const NativeArrangement({
    super.key,
    this.mode = NativeArrangementMode.split,
    required this.primary,
    this.secondary,
    this.axis = NativeArrangementAxis.automatic,
    this.unavailableBuilder,
    this.onSnapshotChanged,
    this.onError,
  }) : assert(mode == NativeArrangementMode.span || secondary != null);

  const NativeArrangement.split({
    super.key,
    required this.primary,
    required Widget this.secondary,
    this.axis = NativeArrangementAxis.automatic,
    this.unavailableBuilder,
    this.onSnapshotChanged,
    this.onError,
  }) : mode = NativeArrangementMode.split;

  const NativeArrangement.span({
    super.key,
    required Widget child,
    this.unavailableBuilder,
    this.onSnapshotChanged,
    this.onError,
  }) : primary = child,
       secondary = null,
       mode = NativeArrangementMode.span,
       axis = NativeArrangementAxis.automatic;

  final NativeArrangementMode mode;
  final Widget primary;

  /// Keep this supplied to the main constructor in span mode to preserve its
  /// State offstage while toggling back to split. Different widget types/keys
  /// still follow Flutter's normal state replacement rules.
  final Widget? secondary;
  final NativeArrangementAxis axis;
  final Widget Function(BuildContext, ArrangementSnapshot, Object?)?
  unavailableBuilder;

  /// Reports native split snapshots only. Span is a Flutter layout, not a sample.
  final ValueChanged<ArrangementSnapshot>? onSnapshotChanged;
  final void Function(Object, StackTrace)? onError;

  @override
  State<NativeArrangement> createState() => _NativeArrangementState();
}

class _NativeArrangementState extends State<NativeArrangement>
    with WidgetsBindingObserver {
  final _viewportKey = GlobalKey();
  ArrangementBridge? _bridge;
  Timer? _timer;
  bool _scheduled = false;
  bool _reading = false;
  bool _tickerEnabled = false;
  int _epoch = 0;
  ArrangementSnapshot _snapshot = ArrangementSnapshot.unavailable(
    ArrangementAvailability.waiting,
  );
  Object? _error;
  Rect? _measuredRect;
  Size? _measuredViewSize;

  bool get _active {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled == _tickerEnabled) return;
    _tickerEnabled = enabled;
    ++_epoch;
    // Ancestor route/TickerMode changes happen during build. Clear stale geometry
    // here without notifying a parent callback from within the build phase.
    _snapshot = ArrangementSnapshot.unavailable(
      ArrangementAvailability.waiting,
    );
    _error = null;
    if (enabled) {
      _start();
    } else {
      _stop();
    }
  }

  void _start() {
    if (widget.mode != NativeArrangementMode.split ||
        !_active ||
        !_tickerEnabled) {
      return;
    }
    _bridge ??= ArrangementBridge();
    _timer ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _schedule(),
    );
    _schedule();
  }

  @override
  void didUpdateWidget(NativeArrangement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode != oldWidget.mode || widget.axis != oldWidget.axis) {
      ++_epoch;
      _snapshot = ArrangementSnapshot.unavailable(
        ArrangementAvailability.waiting,
      );
      _error = null;
      if (widget.mode == NativeArrangementMode.span) {
        _stop();
      } else {
        _start();
        _schedule();
      }
    }
  }

  void _schedule() {
    if (!mounted ||
        widget.mode != NativeArrangementMode.split ||
        !_active ||
        !_tickerEnabled ||
        _scheduled) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted &&
          widget.mode == NativeArrangementMode.split &&
          _active &&
          _tickerEnabled) {
        unawaited(_sample());
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  (Rect, Size)? _geometry() {
    final box = _viewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) {
      return null;
    }
    final origin = box.localToGlobal(Offset.zero);
    final right = box.localToGlobal(Offset(box.size.width, 0));
    final bottom = box.localToGlobal(Offset(0, box.size.height));
    final corner = box.localToGlobal(Offset(box.size.width, box.size.height));
    bool near(Offset a, Offset b) => (a - b).distance < 0.01;
    if (!origin.dx.isFinite ||
        !origin.dy.isFinite ||
        !near(right, origin + Offset(box.size.width, 0)) ||
        !near(bottom, origin + Offset(0, box.size.height)) ||
        !near(corner, origin + Offset(box.size.width, box.size.height))) {
      return null;
    }
    final view = View.of(context);
    final size = view.physicalSize / view.devicePixelRatio;
    return (origin & box.size, size);
  }

  Future<void> _sample() async {
    if (_reading) return;
    final bridge = _bridge;
    if (bridge == null) return;
    final geometry = _geometry();
    if (geometry == null) {
      _publish(
        ArrangementSnapshot.unavailable(
          ArrangementAvailability.unsupportedGeometry,
        ),
      );
      return;
    }
    final (rect, viewSize) = geometry;
    if (_measuredRect != rect || _measuredViewSize != viewSize) {
      _measuredRect = rect;
      _measuredViewSize = viewSize;
      // Discard the old frame before querying a relocated/resized native probe.
      _publish(
        ArrangementSnapshot.unavailable(ArrangementAvailability.waiting),
      );
    }
    final epoch = _epoch;
    _reading = true;
    try {
      final snapshot = await bridge.read(
        viewport: rect,
        viewSize: viewSize,
        axis: widget.axis,
      );
      if (!mounted || epoch != _epoch || !identical(bridge, _bridge)) return;
      if (_geometry() != geometry) {
        _publish(
          ArrangementSnapshot.unavailable(
            ArrangementAvailability.geometryMismatch,
          ),
        );
        return;
      }
      _publish(snapshot);
      if (snapshot.availability == ArrangementAvailability.osUnavailable ||
          snapshot.availability ==
              ArrangementAvailability.unsupportedPlatform) {
        _timer?.cancel();
        _timer = null;
      }
    } catch (error, stack) {
      if (!mounted || epoch != _epoch || !identical(bridge, _bridge)) return;
      setState(() {
        _error = error;
        _snapshot = ArrangementSnapshot.unavailable(
          ArrangementAvailability.waiting,
        );
      });
      // Do not repeatedly invoke a missing or failing implementation every tick.
      _timer?.cancel();
      _timer = null;
      _report(error, stack);
    } finally {
      _reading = false;
    }
  }

  void _publish(ArrangementSnapshot snapshot) {
    if (_snapshot == snapshot && _error == null) return;
    setState(() {
      _snapshot = snapshot;
      _error = null;
    });
    widget.onSnapshotChanged?.call(snapshot);
  }

  void _report(Object error, StackTrace stack) {
    if (widget.onError != null) {
      widget.onError!(error, stack);
    } else {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'iphone_duo_layout',
          context: ErrorDescription(
            'while observing native arrangement geometry',
          ),
        ),
      );
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    final bridge = _bridge;
    _bridge = null;
    if (bridge != null) {
      final onError = widget.onError;
      unawaited(
        bridge.dispose().catchError((Object error, StackTrace stack) {
          if (onError != null) {
            onError(error, stack);
          } else {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stack,
                library: 'iphone_duo_layout',
              ),
            );
          }
        }),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ++_epoch;
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _stop();
      if (widget.mode == NativeArrangementMode.split) {
        _publish(
          ArrangementSnapshot.unavailable(ArrangementAvailability.inactive),
        );
      }
    }
  }

  @override
  void dispose() {
    ++_epoch;
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  Widget _pane(String id, Widget child, Rect rect, bool visible) =>
      Positioned.fromRect(
        key: ValueKey(id),
        rect: rect,
        child: Offstage(
          offstage: !visible,
          child: TickerMode(
            enabled: visible,
            child: ExcludeFocus(
              excluding: !visible,
              child: ExcludeSemantics(
                excluding: !visible,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: ClipRect(child: child),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
        throw FlutterError(
          'NativeArrangement requires bounded width and height. Use Expanded or SizedBox.',
        );
      }
      if (widget.mode == NativeArrangementMode.split &&
          widget.secondary == null) {
        throw FlutterError('Split mode requires a secondary widget.');
      }
      final full = Offset.zero & constraints.biggest;
      final span = widget.mode == NativeArrangementMode.span;
      final usable =
          _snapshot.isAvailable &&
          _snapshot.viewport!.size == full.size &&
          _error == null;
      final primaryVisible = span || (usable && _snapshot.primary!.visible);
      final secondaryVisible = !span && usable && _snapshot.secondary!.visible;
      final panes = <Widget>[
        _pane(
          'primary',
          widget.primary,
          !span && primaryVisible ? _snapshot.primary!.bounds : full,
          primaryVisible,
        ),
        if (widget.secondary != null)
          _pane(
            'secondary',
            widget.secondary!,
            secondaryVisible ? _snapshot.secondary!.bounds : full,
            secondaryVisible,
          ),
      ];
      if (!span &&
          usable &&
          _snapshot.primary!.zIndex > _snapshot.secondary!.zIndex) {
        final first = panes.removeAt(0);
        panes.add(first);
      }
      if (!span && !usable) {
        final displaySnapshot = _snapshot.isAvailable
            ? ArrangementSnapshot.unavailable(
                ArrangementAvailability.geometryMismatch,
              )
            : _snapshot;
        panes.add(
          Positioned.fill(
            child:
                widget.unavailableBuilder?.call(
                  context,
                  displaySnapshot,
                  _error,
                ) ??
                Center(
                  child: Text(
                    _error == null
                        ? 'Arrangement: ${displaySnapshot.availability.name}'
                        : 'Arrangement error: $_error',
                  ),
                ),
          ),
        );
      }
      return SizedBox(
        key: _viewportKey,
        width: full.width,
        height: full.height,
        child: Stack(clipBehavior: Clip.hardEdge, children: panes),
      );
    },
  );
}
