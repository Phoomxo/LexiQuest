import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class HandwritingScratchpad extends StatefulWidget {
  const HandwritingScratchpad({
    super.key,
    required this.spelling,
    required this.meaning,
    required this.onDone,
  });

  final String spelling;
  final String meaning;
  final VoidCallback onDone;

  @override
  State<HandwritingScratchpad> createState() => _HandwritingScratchpadState();
}

enum _Stage { write, compare, done }

class _HandwritingScratchpadState extends State<HandwritingScratchpad> {
  final _strokes = <List<Offset>>[];
  final _typed = TextEditingController();
  _Stage _stage = _Stage.write;
  bool _typing = false, _showExample = false;
  int? _pointer;

  @override
  void didUpdateWidget(HandwritingScratchpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spelling != widget.spelling ||
        oldWidget.meaning != widget.meaning) {
      _strokes.clear();
      _pointer = null;
      _typed.clear();
      _typing = _showExample = false;
      _stage = _Stage.write;
    }
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_stage == _Stage.done) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('คุณประเมินว่าตรงกับเฉลย', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('${widget.spelling} · ${widget.meaning}'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: widget.onDone,
            child: const Text('เลือกรูปแบบโจทย์อื่น'),
          ),
        ],
      );
    }
    final comparing = _stage == _Stage.compare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('เขียนคำว่า ${widget.meaning}', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (_typing && !comparing)
          TextField(
            controller: _typed,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'คำภาษาอังกฤษที่พิมพ์',
              border: OutlineInputBorder(),
            ),
          )
        else if (_typing)
          ListTile(
            title: const Text('คำที่คุณพิมพ์'),
            subtitle: Text(_typed.text),
            contentPadding: EdgeInsets.zero,
          )
        else
          _board(theme, editing: !comparing),
        const SizedBox(height: 8),
        if (comparing || _showExample) ...[
          Text(comparing ? 'คำเฉลย' : 'ตัวอย่างการเขียน'),
          Text(widget.spelling, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
        ],
        if (comparing) ...[
          FilledButton(
            onPressed: () => setState(() => _stage = _Stage.done),
            child: const Text('ฉันสะกดตรงกับเฉลย'),
          ),
          TextButton(
            onPressed: () => setState(() => _stage = _Stage.write),
            child: const Text('ลองเขียนอีกครั้ง'),
          ),
        ] else ...[
          if (!_typing)
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _strokes.isEmpty || _pointer != null
                      ? null
                      : () => setState(() {
                          _strokes.removeLast();
                        }),
                  child: const Text('ย้อนการเขียนครั้งล่าสุด'),
                ),
                TextButton(
                  onPressed: _strokes.isEmpty || _pointer != null
                      ? null
                      : () => setState(_strokes.clear),
                  child: const Text('ล้างกระดาน'),
                ),
              ],
            ),
          TextButton(
            onPressed: () => setState(() => _showExample = !_showExample),
            child: Text(_showExample ? 'ซ่อนตัวอย่าง' : 'ดูตัวอย่างการเขียน'),
          ),
          TextButton(
            onPressed: _pointer != null
                ? null
                : () => setState(() => _typing = !_typing),
            child: Text(_typing ? 'กลับไปเขียนด้วยมือ' : 'ใช้ข้อความแทน'),
          ),
          FilledButton(
            onPressed:
                (_typing
                    ? _typed.text.trim().isEmpty
                    : _strokes.isEmpty || _pointer != null)
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    setState(() => _stage = _Stage.compare);
                  },
            child: const Text('เทียบกับคำเฉลย'),
          ),
        ],
      ],
    );
  }

  Widget _board(ThemeData theme, {required bool editing}) {
    return Semantics(
      container: true,
      label: 'พื้นที่ฝึกเขียน',
      child: SizedBox(
        height: 160,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            Offset point(Offset local) => Offset(
              (local.dx / size.width).clamp(0.0, 1.0).toDouble(),
              (local.dy / size.height).clamp(0.0, 1.0).toDouble(),
            );
            final board = DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  size: size,
                  painter: _InkPainter(_strokes, theme.colorScheme.onSurface),
                ),
              ),
            );
            if (!editing) {
              return board;
            }
            // Ink gets the whole gesture, including a vertical stroke inside a scrolling page.
            return RawGestureDetector(
              gestures: {
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      EagerGestureRecognizer
                    >(EagerGestureRecognizer.new, (_) {}),
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  if (_pointer != null || event.buttons != kPrimaryButton) {
                    return;
                  }
                  setState(() {
                    _pointer = event.pointer;
                    _strokes.add([point(event.localPosition)]);
                  });
                },
                onPointerMove: (event) {
                  if (event.pointer == _pointer) {
                    setState(
                      () => _strokes.last.add(point(event.localPosition)),
                    );
                  }
                },
                onPointerUp: (event) {
                  if (event.pointer == _pointer) {
                    setState(() => _pointer = null);
                  }
                },
                onPointerCancel: (event) {
                  if (event.pointer == _pointer) {
                    setState(() {
                      _strokes.removeLast();
                      _pointer = null;
                    });
                  }
                },
                child: board,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  const _InkPainter(this.strokes, this.color);
  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final brush = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    Offset position(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    for (final stroke in strokes) {
      var previous = position(stroke.first);
      canvas.drawCircle(previous, brush.strokeWidth / 2, brush);
      for (final p in stroke.skip(1)) {
        final next = position(p);
        canvas.drawLine(previous, next, brush);
        previous = next;
      }
    }
  }

  @override
  bool shouldRepaint(_InkPainter oldDelegate) => true;
}
