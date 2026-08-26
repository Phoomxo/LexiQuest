import 'package:flutter/material.dart';

import '../application/handwriting_self_check_adapter.dart';
import 'unified_lesson_shell.dart';

final class HandwritingStroke {
  const HandwritingStroke._(this.points);

  final List<Offset> points;
}

/// Local, bounded stroke storage. It exposes no image, serialization, or raw
/// typed-response API, so callers cannot accidentally persist scratch work.
final class HandwritingScratchpadController extends ChangeNotifier {
  static const int maxStrokes = 32;
  static const int maxPointsPerStroke = 128;

  final List<List<Offset>> _strokes = <List<Offset>>[];
  int _revision = 0;

  int get revision => _revision;
  int get strokeCount => _strokes.length;
  bool get hasHandwriting => _strokes.isNotEmpty;
  List<HandwritingStroke> get strokes => List<HandwritingStroke>.unmodifiable(
    _strokes.map(
      (points) => HandwritingStroke._(List<Offset>.unmodifiable(points)),
    ),
  );

  void beginStroke(Offset point) {
    if (_strokes.length == maxStrokes) _strokes.removeAt(0);
    _strokes.add(<Offset>[point]);
    _changed();
  }

  void appendPoint(Offset point) {
    if (_strokes.isEmpty) return;
    final points = _strokes.last;
    if (points.length == maxPointsPerStroke) return;
    points.add(point);
    _changed();
  }

  void endStroke() {}

  void undo() {
    if (_strokes.isEmpty) return;
    _strokes.removeLast();
    _changed();
  }

  void clear({bool notify = true}) {
    if (_strokes.isNotEmpty) _strokes.clear();
    _revision++;
    if (notify) notifyListeners();
  }

  void _changed() {
    _revision++;
    notifyListeners();
  }
}

typedef HandwritingSelfCheckCallback =
    void Function(HandwritingSelfCheckOutcome outcome);

final class HandwritingScratchpad extends StatefulWidget {
  const HandwritingScratchpad({super.key, this.controller, this.onSelfCheck});

  final HandwritingScratchpadController? controller;
  final HandwritingSelfCheckCallback? onSelfCheck;

  @override
  State<HandwritingScratchpad> createState() => _HandwritingScratchpadState();
}

final class _HandwritingScratchpadState extends State<HandwritingScratchpad>
    with WidgetsBindingObserver
    implements EphemeralLessonState {
  late final HandwritingScratchpadController _ownedController;
  late final TextEditingController _typedAlternative;
  UnifiedLessonSessionLifecycleScope? _sessionLifecycleScope;
  int _typedRevision = 0;
  int? _submittedStrokeRevision;
  int? _submittedTypedRevision;
  HandwritingSelfCheckSelection? _submittedSelection;
  HandwritingSelfCheckOutcome? _lastOutcome;

  HandwritingScratchpadController get _controller =>
      widget.controller ?? _ownedController;

  @override
  void initState() {
    super.initState();
    _ownedController = HandwritingScratchpadController();
    _typedAlternative = TextEditingController();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = UnifiedLessonSessionLifecycleScope.maybeScopeOf(context);
    if (!identical(next, _sessionLifecycleScope)) {
      _sessionLifecycleScope?.unregisterEphemeralState(this);
      _sessionLifecycleScope = next;
      next?.registerEphemeralState(this);
    }
  }

  @override
  void didUpdateWidget(HandwritingScratchpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _clearEphemeralStateFor(oldWidget.controller ?? _ownedController);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        clearEphemeralState();
    }
  }

  @override
  void clearEphemeralState() {
    _clearEphemeralStateFor(_controller);
  }

  void _clearEphemeralStateFor(
    HandwritingScratchpadController controller, {
    bool notify = true,
  }) {
    controller.clear(notify: notify);
    _typedAlternative.clear();
    _typedRevision++;
    _submittedStrokeRevision = null;
    _submittedTypedRevision = null;
    _submittedSelection = null;
    _lastOutcome = null;
  }

  void _onTypedAlternativeChanged(String _) {
    _typedRevision++;
    _lastOutcome = null;
  }

  void _selfCheck(HandwritingSelfCheckSelection selection) {
    final strokeRevision = _controller.revision;
    final typedRevision = _typedRevision;
    final isDuplicate =
        _submittedStrokeRevision == strokeRevision &&
        _submittedTypedRevision == typedRevision &&
        _submittedSelection == selection &&
        _lastOutcome != null;
    if (isDuplicate) return;
    final outcome = const HandwritingSelfCheckAdapter().selfCheck(
      selection: selection,
      hasHandwriting: _controller.hasHandwriting,
      hasTypedAlternative: _typedAlternative.text.trim().isNotEmpty,
    );
    _submittedStrokeRevision = strokeRevision;
    _submittedTypedRevision = typedRevision;
    _submittedSelection = selection;
    _lastOutcome = outcome;
    widget.onSelfCheck?.call(outcome);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label:
        'Handwriting scratchpad. Draw locally; handwriting is not recognized.',
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Practice writing',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Draw your answer for your own review. This stays on this device only and is never recognized automatically.',
          ),
          const SizedBox(height: 12),
          RepaintBoundary(
            child: SizedBox(
              height: 240,
              child: Semantics(
                label: 'Local handwriting canvas',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) =>
                      _controller.beginStroke(details.localPosition),
                  onPanUpdate: (details) =>
                      _controller.appendPoint(details.localPosition),
                  onPanEnd: (_) => _controller.endStroke(),
                  child: CustomPaint(
                    painter: _HandwritingPainter(_controller),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _controller.hasHandwriting
                      ? _controller.undo
                      : null,
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo stroke'),
                ),
                OutlinedButton.icon(
                  onPressed: clearEphemeralState,
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear local work'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Typed accessibility alternative',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Typing is an alternative for your own self-check, not handwriting recognition.',
          ),
          TextField(
            controller: _typedAlternative,
            maxLength: 120,
            onChanged: _onTypedAlternativeChanged,
            decoration: const InputDecoration(
              labelText: 'Type your answer instead',
              helperText: 'Your text stays only while this scratchpad is open.',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose your own result. This does not update progress or rewards.',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                onPressed: () =>
                    _selfCheck(HandwritingSelfCheckSelection.looksCorrect),
                child: const Text('I checked it'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _selfCheck(HandwritingSelfCheckSelection.needsMorePractice),
                child: const Text('I need more practice'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _clearEphemeralStateFor(_controller, notify: false);
    _sessionLifecycleScope?.unregisterEphemeralState(this);
    WidgetsBinding.instance.removeObserver(this);
    _typedAlternative.dispose();
    _ownedController.dispose();
    super.dispose();
  }
}

final class _HandwritingPainter extends CustomPainter {
  const _HandwritingPainter(this.controller) : super(repaint: controller);

  final HandwritingScratchpadController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke;
    final ink = Paint()
      ..color = Colors.blueGrey
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, border);
    for (final stroke in controller.strokes) {
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.single, 1.5, ink);
        continue;
      }
      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(_HandwritingPainter oldDelegate) =>
      !identical(controller, oldDelegate.controller);
}
