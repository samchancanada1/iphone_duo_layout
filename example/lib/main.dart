import 'package:flutter/material.dart';
import 'package:iphone_duo_layout/iphone_duo_layout.dart';

import 'arrangement_demo.dart';

void main() => runApp(const RegionsExample());

class RegionsExample extends StatefulWidget {
  const RegionsExample({super.key});

  @override
  State<RegionsExample> createState() => _RegionsExampleState();
}

class _RegionsExampleState extends State<RegionsExample> {
  String _toolbarStatus = 'waiting';
  String _lastAction = 'none';
  int _actionCount = 0;
  bool _shareEnabled = true;

  late final _hingeChanges = const NativeHinge().watch();
  late final _changes = const NativeReservedRegions().watch();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      builder: (context, child) => NativeToolbarHost(
        configuration: NativeToolbarConfiguration(
          title: 'Native capabilities',
          items: [
            NativeToolbarItem(
              id: 'share',
              title: 'Share',
              systemImage: 'square.and.arrow.up',
              enabled: _shareEnabled,
              priority: NativeToolbarPriority.high,
            ),
            const NativeToolbarItem(
              id: 'refresh',
              title: 'Refresh',
              systemImage: 'arrow.clockwise',
              placement: NativeToolbarPlacement.bottom,
              axis: NativeToolbarAxis.verticalPreferred,
            ),
          ],
          overflowItems: const [
            NativeToolbarItem(
              id: 'settings',
              title: 'Settings',
              systemImage: 'gearshape',
            ),
          ],
        ),
        onAction: (id) {
          // Demo actions report the round trip; no actual share is sent.
          if (mounted) {
            setState(() {
              _lastAction = id;
              _actionCount++;
            });
          }
        },
        onStatusChanged: (status) {
          if (mounted) {
            setState(() => _toolbarStatus = status.availability.name);
          }
        },
        onError: (error, stack) {
          if (mounted) setState(() => _toolbarStatus = 'error: $error');
        },
        child: child!,
      ),
      home: StreamBuilder<ReservedRegionsSnapshot>(
        stream: _changes,
        builder: (context, event) {
          final data = event.data;
          return Scaffold(
            // This Stack occupies the whole Flutter view. Only the text is
            // inset, so native region coordinates can be drawn without offset.
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (data?.isAvailable ?? false)
                  for (final region in data!.regions!)
                    Positioned.fromRect(
                      rect: region.bounds,
                      child: IgnorePointer(
                        child: ColoredBox(
                          color:
                              (region.kind == ReservedRegionKind.division
                                      ? Colors.orange
                                      : Colors.purple)
                                  .withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ListView(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Native reserved regions',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              event.hasError
                                  ? 'Channel error: ${event.error}'
                                  : 'Status: ${data?.availability.name ?? "waiting"}',
                            ),
                            const SizedBox(height: 12),
                            if (data?.isAvailable ?? false) ...[
                              Text('Active regions: ${data!.regions!.length}'),
                              Text('Flutter view: ${data.viewSize}'),
                              const Text(
                                'Orange: division · Purple: occlusion',
                              ),
                            ] else
                              const Text(
                                'Native region data is unavailable. '
                                'No fold or camera rectangles are simulated.',
                              ),
                            const SizedBox(height: 24),
                            Text(
                              'Native toolbar',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text('Toolbar: $_toolbarStatus'),
                            Text(
                              'Last native action: $_lastAction ($_actionCount)',
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Enable native Share button'),
                              value: _shareEnabled,
                              onChanged: (value) =>
                                  setState(() => _shareEnabled = value),
                            ),
                            const Text(
                              'The native bar is outside the Flutter content area.',
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ArrangementDemo(),
                                ),
                              ),
                              child: const Text('Open split / span prototype'),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Native hinge',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            StreamBuilder<HingeSnapshot>(
                              stream: _hingeChanges,
                              builder: (context, event) {
                                final hinge = event.data;
                                if (event.hasError) {
                                  return Text('Hinge error: ${event.error}');
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hinge: ${hinge?.availability.name ?? "waiting"}',
                                    ),
                                    if (hinge?.isAvailable ?? false) ...[
                                      Text('State: ${hinge!.status!.name}'),
                                      Text(
                                        'Angle: ${hinge.angleDegrees!.toStringAsFixed(1)}°',
                                      ),
                                    ] else
                                      const Text('No live angle available.'),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
