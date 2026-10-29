import 'package:flutter/material.dart';

import '../../learning/domain/learning_models.dart';
import '../../research/application/study_runtime.dart';
import '../domain/adventure_entry.dart';

class StudyPresentations extends StatefulWidget {
  const StudyPresentations({
    super.key,
    required this.catalog,
    required this.presentation,
    required this.onStart,
    required this.canStart,
    this.index,
    this.busy = false,
    this.languageCode = 'th',
  });

  final StudyPresentationCatalog catalog;
  final TodayExperiencePresentation presentation;
  final ConfiguredQuizState? index;
  final bool canStart;
  final bool busy;
  final Future<void> Function() onStart;
  final String languageCode;

  @override
  State<StudyPresentations> createState() => _StudyPresentationsState();
}

class _StudyPresentationsState extends State<StudyPresentations> {
  final _nodeFocus = FocusNode();
  final _detailFocus = FocusNode();
  final _detailKey = GlobalKey();
  bool _detailOpen = false;

  bool get _thai => widget.languageCode != 'en';
  String _text(String th, String en) => _thai ? th : en;
  String get _title => widget.catalog.title(widget.languageCode);
  String get _description => widget.catalog.description(widget.languageCode);
  bool get _active => widget.index?.state == 'active';
  bool get _closed => widget.index != null && !_active;
  String get _status => switch (widget.index?.state) {
    'active' => _text('กำลังฝึก', 'In progress'),
    'completed' => _text('จบภารกิจแล้ว', 'Completed'),
    'abandoned' => _text('รอบนี้หยุดแล้ว', 'Session ended'),
    null => _text('ยังไม่เริ่ม', 'Not started'),
    _ => _text('ยังไม่พร้อม', 'Unavailable'),
  };

  @override
  void didUpdateWidget(covariant StudyPresentations oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog.version != widget.catalog.version ||
        oldWidget.catalog.missionId != widget.catalog.missionId ||
        oldWidget.presentation != widget.presentation) {
      _detailOpen = false;
    }
  }

  @override
  void dispose() {
    _nodeFocus.dispose();
    _detailFocus.dispose();
    super.dispose();
  }

  void _openDetail() {
    setState(() => _detailOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_detailOpen) return;
      _detailFocus.requestFocus();
      final context = _detailKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context, duration: Duration.zero);
      }
    });
  }

  Widget _startButton() => FilledButton(
    key: const ValueKey('study-mission-start'),
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    onPressed: widget.canStart && !widget.busy && !_closed
        ? widget.onStart
        : null,
    child: Text(
      _active
          ? _text('ฝึกต่อรอบเดิม', 'Continue this session')
          : _text('เริ่มภารกิจ', 'Start mission'),
    ),
  );

  Widget _statusText() => Semantics(
    liveRegion: true,
    child: Text(_status, style: Theme.of(context).textTheme.labelLarge),
  );

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: switch (widget.presentation) {
          TodayExperiencePresentation.standard => _standard(context),
          TodayExperiencePresentation.adventure => _adventure(context),
        },
      ),
    ),
  );

  Widget _standard(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(
          _text('ภารกิจของคุณ', 'Your mission'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      const SizedBox(height: 20),
      Card(
        key: const ValueKey('study-standard-mission'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              _statusText(),
              const SizedBox(height: 16),
              Text(_description),
              const SizedBox(height: 20),
              _startButton(),
            ],
          ),
        ),
      ),
      if (widget.busy) _busyIndicator(),
    ],
  );

  Widget _adventure(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            _text('เส้นทางการฝึก', 'Your learning path'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 12),
        Text(_title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _statusText(),
        const SizedBox(height: 20),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SizedBox(
            height: 180,
            child: CustomPaint(
              painter: _MissionRoutePainter(colors.outlineVariant),
              child: Center(
                child: FilledButton.tonalIcon(
                  key: const ValueKey('study-adventure-node'),
                  focusNode: _nodeFocus,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 64),
                  ),
                  onPressed: widget.busy ? null : _openDetail,
                  icon: Icon(
                    widget.index?.state == 'completed'
                        ? Icons.flag_outlined
                        : Icons.place_outlined,
                  ),
                  label: Text(_text('เปิดภารกิจ', 'Open mission')),
                ),
              ),
            ),
          ),
        ),
        if (_detailOpen) ...[
          const SizedBox(height: 20),
          Focus(
            key: _detailKey,
            focusNode: _detailFocus,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    _title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 12),
                Text(_description),
                const SizedBox(height: 20),
                _startButton(),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    setState(() => _detailOpen = false);
                    _nodeFocus.requestFocus();
                  },
                  child: Text(_text('กลับไปยังแผนที่', 'Back to the map')),
                ),
              ],
            ),
          ),
        ],
        if (widget.busy) _busyIndicator(),
      ],
    );
  }

  Widget _busyIndicator() => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: LinearProgressIndicator(
      semanticsLabel: _text('กำลังเตรียมภารกิจ', 'Preparing the mission'),
    ),
  );
}

class _MissionRoutePainter extends CustomPainter {
  const _MissionRoutePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .18, 20)
      ..cubicTo(size.width * .82, 16, size.width * .84, 68, size.width * .5, 90)
      ..cubicTo(
        size.width * .18,
        116,
        size.width * .2,
        160,
        size.width * .82,
        160,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MissionRoutePainter oldDelegate) =>
      color != oldDelegate.color;
}
