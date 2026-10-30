import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class HandwritingScratchpad extends StatefulWidget {
  const HandwritingScratchpad({
    super.key,
    required this.canEdit,
    this.languageCode = 'th',
  });

  final bool Function() canEdit;
  final String languageCode;

  @override
  State<HandwritingScratchpad> createState() => _HandwritingScratchpadState();
}

class _HandwritingScratchpadState extends State<HandwritingScratchpad> {
  static const _maxStrokes = 64;
  static const _maxPoints = 4096;
  final _strokes = <List<Offset>>[];
  int? _pointer;
  int _pointCount = 0;
  int _paintVersion = 0;
  bool _expanded = false;
  bool _redrawScheduled = false;
  Size _canvasSize = Size.zero;

  String _copy(String th, String en) => widget.languageCode == 'th' ? th : en;
  bool get _editable => mounted && _expanded && widget.canEdit();
  bool get _atLimit =>
      _strokes.length >= _maxStrokes || _pointCount >= _maxPoints;

  void _redraw() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_redrawScheduled) return;
      _redrawScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _redrawScheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant HandwritingScratchpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.canEdit()) _pointer = null;
  }

  Offset? _normalized(Offset point) {
    if (!point.dx.isFinite ||
        !point.dy.isFinite ||
        !_canvasSize.width.isFinite ||
        !_canvasSize.height.isFinite ||
        _canvasSize.width <= 0 ||
        _canvasSize.height <= 0) {
      return null;
    }
    return Offset(
      (point.dx / _canvasSize.width).clamp(0.0, 1.0).toDouble(),
      (point.dy / _canvasSize.height).clamp(0.0, 1.0).toDouble(),
    );
  }

  void _down(PointerDownEvent event) {
    if (!_editable) {
      _pointer = null;
      return;
    }
    if (_pointer != null ||
        _strokes.length >= _maxStrokes ||
        _pointCount >= _maxPoints ||
        (event.kind == PointerDeviceKind.mouse &&
            (event.buttons & kPrimaryButton) == 0)) {
      return;
    }
    final point = _normalized(event.localPosition);
    if (point == null) return;
    _pointer = event.pointer;
    _strokes.add([point]);
    _pointCount++;
    _paintVersion++;
    _redraw();
  }

  void _move(PointerMoveEvent event) {
    if (!_editable) {
      _pointer = null;
      return;
    }
    if (_pointer != event.pointer) return;
    if (_pointCount >= _maxPoints) {
      _pointer = null;
      return;
    }
    final point = _normalized(event.localPosition);
    if (point == null) return;
    _strokes.last.add(point);
    _pointCount++;
    _paintVersion++;
    _redraw();
  }

  void _end(PointerEvent event) {
    if (!_editable || _pointer == event.pointer) _pointer = null;
  }

  void _undo() {
    if (!_editable) {
      _pointer = null;
      return;
    }
    if (_strokes.isEmpty) return;
    _pointer = null;
    _pointCount -= _strokes.removeLast().length;
    _paintVersion++;
    _redraw();
  }

  void _clear() {
    if (!_editable) {
      _pointer = null;
      return;
    }
    if (_strokes.isEmpty) return;
    _pointer = null;
    _strokes.clear();
    _pointCount = 0;
    _paintVersion++;
    _redraw();
  }

  void _toggle() {
    if (!mounted) return;
    _pointer = null;
    _expanded = !_expanded;
    _redraw();
  }

  @override
  void dispose() {
    _pointer = null;
    _strokes.clear();
    _pointCount = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.canEdit();
    final count = _strokes.isEmpty
        ? _copy('ยังไม่มีเส้น', 'No strokes')
        : _copy(
            '${_strokes.length} เส้น',
            '${_strokes.length} ${_strokes.length == 1 ? 'stroke' : 'strokes'}',
          );
    final status = [
      count,
      if (!editable) _copy('ร่างแบบอ่านอย่างเดียว', 'Read-only draft'),
      if (_atLimit)
        editable
            ? _copy(
                'พื้นที่เขียนเต็ม ย้อนกลับหรือล้างเส้นเพื่อเขียนต่อ',
                'Drawing limit reached. Undo or clear strokes to continue.',
              )
            : _copy('พื้นที่เขียนเต็ม', 'Drawing limit reached.'),
      _copy('ร่างนี้อยู่เฉพาะในรอบนี้', 'Only kept in this round.'),
    ].join(' · ');
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('scratchpad-toggle'),
              onPressed: _toggle,
              icon: Icon(_expanded ? Icons.expand_less : Icons.draw_outlined),
              label: Text(
                _expanded
                    ? _copy('พับพื้นที่เขียนร่าง', 'Hide scratchpad')
                    : _copy('เปิดพื้นที่เขียนร่าง', 'Open scratchpad'),
              ),
            ),
            Semantics(
              liveRegion: true,
              child: Text(status, key: const ValueKey('scratchpad-status')),
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Text(
                _copy(
                  'พื้นที่นี้ไม่แปลงลายมือเป็นข้อความ ส่งคำตอบด้วยช่องพิมพ์',
                  'Ink is not recognized. Submit your answer using the text field.',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 180,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _canvasSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        border: Border.all(color: colors.outline),
                      ),
                      child: ClipRect(
                        child: RawGestureDetector(
                          behavior: HitTestBehavior.opaque,
                          gestures: editable
                              ? <Type, GestureRecognizerFactory>{
                                  EagerGestureRecognizer:
                                      GestureRecognizerFactoryWithHandlers<
                                        EagerGestureRecognizer
                                      >(EagerGestureRecognizer.new, (_) {}),
                                }
                              : const <Type, GestureRecognizerFactory>{},
                          child: Listener(
                            key: const ValueKey('scratchpad-canvas'),
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: _down,
                            onPointerMove: _move,
                            onPointerUp: _end,
                            onPointerCancel: _end,
                            child: Semantics(
                              label: _copy(
                                'พื้นที่เขียนร่าง ใช้ช่องพิมพ์ส่งคำตอบแทนได้',
                                'Temporary writing area. Use the text field to submit.',
                              ),
                              child: ExcludeSemantics(
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: _StrokePainter(
                                    strokes: List<List<Offset>>.unmodifiable([
                                      for (final stroke in _strokes)
                                        List<Offset>.unmodifiable(stroke),
                                    ]),
                                    color: colors.onSurface,
                                    version: _paintVersion,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('scratchpad-undo'),
                    onPressed: editable && _strokes.isNotEmpty ? _undo : null,
                    icon: const Icon(Icons.undo),
                    label: Text(_copy('ย้อนเส้นล่าสุด', 'Undo stroke')),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('scratchpad-clear'),
                    onPressed: editable && _strokes.isNotEmpty ? _clear : null,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(_copy('ล้างเส้น', 'Clear strokes')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter({
    required this.strokes,
    required this.color,
    required this.version,
  });

  final List<List<Offset>> strokes;
  final Color color;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dot = Paint()..color = color;
    Offset position(Offset point) =>
        Offset(point.dx * size.width, point.dy * size.height);
    for (final stroke in strokes) {
      if (stroke.isNotEmpty) {
        canvas.drawCircle(position(stroke.first), 1.5, dot);
      }
      if (stroke.length > 1) {
        final path = Path()
          ..moveTo(position(stroke.first).dx, position(stroke.first).dy);
        for (final point in stroke.skip(1)) {
          final value = position(point);
          path.lineTo(value.dx, value.dy);
        }
        canvas.drawPath(path, line);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) =>
      version != oldDelegate.version || color != oldDelegate.color;
}
