import 'package:flutter/material.dart';
import 'package:iphone_duo_layout/iphone_duo_layout.dart';

/// Standalone: flutter run -t lib/arrangement_demo.dart
void main() => runApp(
  MaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    builder: (context, child) => NativeToolbarHost(
      configuration: NativeToolbarConfiguration(title: 'Arrangement prototype'),
      onAction: (_) {},
      child: child!,
    ),
    home: const ArrangementDemo(),
  ),
);

class ArrangementDemo extends StatefulWidget {
  const ArrangementDemo({super.key});
  @override
  State<ArrangementDemo> createState() => _ArrangementDemoState();
}

class _ArrangementDemoState extends State<ArrangementDemo> {
  NativeArrangementMode _mode = NativeArrangementMode.split;
  NativeArrangementAxis _axis = NativeArrangementAxis.automatic;
  String _status = 'waiting';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (Navigator.canPop(context))
                  BackButton(onPressed: () => Navigator.maybePop(context)),
                SegmentedButton<NativeArrangementMode>(
                  segments: const [
                    ButtonSegment(
                      value: NativeArrangementMode.split,
                      label: Text('Two widgets'),
                    ),
                    ButtonSegment(
                      value: NativeArrangementMode.span,
                      label: Text('One spanning widget'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) =>
                      setState(() => _mode = selection.single),
                ),
                DropdownButton<NativeArrangementAxis>(
                  value: _axis,
                  items: NativeArrangementAxis.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: _mode == NativeArrangementMode.split
                      ? (axis) => setState(() => _axis = axis!)
                      : null,
                ),
                Text(
                  _mode == NativeArrangementMode.span
                      ? 'Span: Flutter (no native layout query)'
                      : 'Native split: $_status',
                ),
              ],
            ),
          ),
          Expanded(
            child: NativeArrangement(
              mode: _mode,
              axis: _axis,
              // Keeping the same types/keys in both slots preserves their State.
              primary: const _DemoPane(
                key: ValueKey('primary-content'),
                title: 'Primary',
                color: Color(0xFFD5F2EE),
              ),
              secondary: const _DemoPane(
                key: ValueKey('secondary-content'),
                title: 'Secondary',
                color: Color(0xFFFFE7C5),
              ),
              onSnapshotChanged: (snapshot) {
                if (mounted) {
                  setState(() => _status = snapshot.availability.name);
                }
              },
              onError: (error, stack) {
                if (mounted) setState(() => _status = 'error: $error');
              },
              unavailableBuilder: (context, snapshot, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error == null
                        ? 'Native layout: ${snapshot.availability.name}\nNo substitute split is generated. Try Span to use a single Flutter widget.'
                        : 'Native layout error: $error',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DemoPane extends StatefulWidget {
  const _DemoPane({super.key, required this.title, required this.color});
  final String title;
  final Color color;
  @override
  State<_DemoPane> createState() => _DemoPaneState();
}

class _DemoPaneState extends State<_DemoPane> {
  int _count = 0;
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: widget.color,
    child: LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.headlineSmall),
          Text(
            '${constraints.maxWidth.toStringAsFixed(1)} × ${constraints.maxHeight.toStringAsFixed(1)} logical pixels',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => setState(() => _count++),
            child: Text('Count: $_count'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            decoration: const InputDecoration(
              labelText: 'State retained across mode changes',
            ),
          ),
          const SizedBox(height: 500),
          const Text('Scroll position / keyboard / input diagnostic'),
        ],
      ),
    ),
  );
}
