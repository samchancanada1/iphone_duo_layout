import 'dart:async';

import 'package:flutter/widgets.dart';

import 'native_toolbar_configuration.dart';
import 'native_toolbar_controller.dart';

/// App-level host for a native iOS toolbar. Place once in MaterialApp.builder
/// or CupertinoApp.builder and update [configuration] as Flutter routes change.
/// The child remains Flutter-rendered. No Flutter toolbar fallback is drawn.
class NativeToolbarHost extends StatefulWidget {
  const NativeToolbarHost({
    super.key,
    required this.configuration,
    required this.child,
    required this.onAction,
    this.onStatusChanged,
    this.onError,
  });

  final NativeToolbarConfiguration configuration;
  final Widget child;
  final ValueChanged<String> onAction;
  final ValueChanged<NativeToolbarStatus>? onStatusChanged;
  final void Function(Object error, StackTrace stack)? onError;

  @override
  State<NativeToolbarHost> createState() => _NativeToolbarHostState();
}

class _NativeToolbarHostState extends State<NativeToolbarHost>
    with WidgetsBindingObserver {
  late final NativeToolbarController _controller;
  late final StreamSubscription<String> _actions;
  Timer? _retry;
  bool _scheduled = false;
  int _request = 0;
  NativeToolbarAvailability? _lastStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = NativeToolbarController();
    _actions = _controller.actions.listen((id) {
      if (mounted) widget.onAction(id);
    });
    _schedule();
  }

  @override
  void didUpdateWidget(NativeToolbarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configuration != widget.configuration) _schedule();
  }

  bool get _active {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  void _schedule() {
    // Invalidate an older reply as soon as a replacement is requested.
    ++_request;
    _retry?.cancel();
    _retry = null;
    if (!mounted || !_active || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && _active) unawaited(_apply());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _apply() async {
    final request = _request;
    try {
      final status = await _controller.setConfiguration(widget.configuration);
      if (!mounted || request != _request) return;
      if (_lastStatus != status.availability) {
        _lastStatus = status.availability;
        widget.onStatusChanged?.call(status);
      }
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (status.availability == NativeToolbarAvailability.viewUnavailable &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
        _retry = Timer(const Duration(milliseconds: 250), _schedule);
      }
    } catch (error, stack) {
      if (mounted && request == _request) _report(error, stack);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ++_request;
    _retry?.cancel();
    _retry = null;
    if (state == AppLifecycleState.resumed) _schedule();
  }

  void _report(Object error, StackTrace stack) {
    final handler = widget.onError;
    if (handler != null) {
      handler(error, stack);
    } else {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'iphone_duo_layout',
          context: ErrorDescription('while managing a native toolbar'),
        ),
      );
    }
  }

  @override
  void dispose() {
    ++_request;
    _retry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_actions.cancel());
    // A State cannot await disposal; retain the callback without retaining State.
    final onError = widget.onError;
    unawaited(
      _controller.dispose().catchError((Object error, StackTrace stack) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
