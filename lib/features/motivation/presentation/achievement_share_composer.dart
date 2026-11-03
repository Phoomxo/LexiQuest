import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../runtime/app_dependencies.dart';

import '../../export/data/file_selector_export_store.dart';
import '../../export/domain/export_contracts.dart';
import '../../progress/domain/progress_models.dart';
import '../../../widgets/adaptive_content_pane.dart';

typedef AchievementImageSaver =
    Future<void> Function(
      Uint8List pngBytes,
      ExportCancellation cancellation,
      Future<void> Function() revalidate,
    );
typedef AchievementImageSharer =
    Future<void> Function(
      Uint8List pngBytes,
      Future<void> Function() revalidate,
    );

String? shareableAchievementTitle(AchievementEvidence evidence) {
  if (evidence.definitionVersion != 1 ||
      evidence.sourceEventId.trim().isEmpty ||
      !evidence.unlockedAtUtc.isUtc ||
      evidence.unlockedAtUtc.millisecondsSinceEpoch < 0) {
    return null;
  }
  return switch (evidence.id) {
    'first_answer' => 'บันทึกคำตอบครั้งแรก',
    'first_correct' => 'ตอบถูกครั้งแรก',
    'ten_correct' => 'ตอบถูกครบ 10 ครั้ง',
    'first_session' => 'เรียนจบรอบแรก',
    'perfect_session' => 'ตอบถูกครบทั้งรอบ',
    _ => null,
  };
}

String achievementCardDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year} UTC';

Future<Uint8List> renderAchievementCard(
  AchievementEvidence evidence, {
  required bool includeDate,
  required ColorScheme colors,
}) async {
  final title = shareableAchievementTitle(evidence);
  if (title == null) throw const ExportException(ExportFailureCode.noData);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(colors.surface, BlendMode.src);
  final texts = [
    ('LexiQuest', 34.0, FontWeight.w600, colors.primary),
    ('ความสำเร็จจากการฝึก', 30.0, FontWeight.w400, colors.onSurface),
    (title, 50.0, FontWeight.w700, colors.onSurface),
    if (includeDate)
      (
        'ปลดล็อก ${achievementCardDate(evidence.unlockedAtUtc)}',
        28.0,
        FontWeight.w400,
        colors.onSurface,
      ),
    (
      'จากกิจกรรมที่บันทึกไว้ใน LexiQuest',
      26.0,
      FontWeight.w400,
      colors.onSurface,
    ),
  ];
  var top = 48.0;
  for (final (text, size, weight, color) in texts) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontFamily: 'NotoSansThai',
          fontSize: size,
          fontWeight: weight,
          height: 1.45,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 780);
    painter.paint(canvas, Offset(60, top));
    top += painter.height + 24;
    painter.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(900, 640);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null || bytes.lengthInBytes > 2 * 1024 * 1024) {
      throw const ExportException(ExportFailureCode.writeFailed);
    }
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

final class NativeAchievementSharer {
  const NativeAchievementSharer();
  static const _channel = MethodChannel('com.lexiquest.app/achievement_share');

  Future<void> share(
    Uint8List pngBytes,
    Future<void> Function() revalidate,
  ) async {
    String? token;
    try {
      await revalidate();
      token = await _channel.invokeMethod<String>('prepareAchievementShare', {
        'bytes': pngBytes,
      });
      if (token == null || token.isEmpty) {
        throw const ExportException(ExportFailureCode.unavailable);
      }
      await revalidate();
      await _channel.invokeMethod<void>('launchAchievementShare', {
        'token': token,
      });
    } on ExportException {
      rethrow;
    } on Object {
      throw const ExportException(ExportFailureCode.unavailable);
    } finally {
      if (token != null) {
        try {
          await _channel.invokeMethod<void>('discardAchievementShare', {
            'token': token,
          });
        } on Object {
          // Native preparation also removes abandoned, unshared cache files.
        }
      }
    }
  }
}

class AchievementShareComposer extends StatefulWidget {
  const AchievementShareComposer({
    super.key,
    required this.achievement,
    required this.stillCurrent,
    required this.revalidate,
    required this.scopeChanges,
    required this.onExternalOperation,
    this.saveImage,
    this.shareImage,
  });
  final AchievementEvidence achievement;
  final bool Function() stillCurrent;
  final Future<void> Function() revalidate;
  final Listenable scopeChanges;
  final ValueChanged<bool> onExternalOperation;
  final AchievementImageSaver? saveImage;
  final AchievementImageSharer? shareImage;
  @override
  State<AchievementShareComposer> createState() =>
      _AchievementShareComposerState();
}

class _AchievementShareComposerState extends State<AchievementShareComposer>
    with WidgetsBindingObserver {
  final _cancellation = ExportCancellation();
  Uint8List? _png;
  ModalRoute<dynamic>? _route;
  Completer<void>? _resumed;
  var _includeDate = false;
  var _busy = false;
  var _invalid = false;
  var _foreground = true;
  var _render = 0;
  String? _status;
  ColorScheme? _colors;
  AppDependencies? _dependencies;
  var _bound = false;
  bool get _current =>
      mounted &&
      !_invalid &&
      _foreground &&
      widget.stillCurrent() &&
      (_route?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.scopeChanges.addListener(_scopeChanged);
  }

  void _scopeChanged() {
    if (!mounted || widget.stillCurrent()) return;
    setState(_invalidate);
  }

  void _invalidate() {
    _render++;
    _invalid = true;
    _png = null;
    _cancellation.cancel();
    _resumed?.complete();
    _resumed = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    ModalRoute.isCurrentOf(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    if ((_bound && !identical(dependencies, _dependencies)) ||
        _route?.isCurrent == false) {
      _invalidate();
    }
    _bound = true;
    _dependencies = dependencies;
    final colors = Theme.of(context).colorScheme;
    if (_colors != colors) {
      _colors = colors;
      unawaited(_renderCard());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _resumed?.complete();
      _resumed = null;
    }
    _scopeChanged();
    if (mounted) setState(() {});
  }

  Future<void> _renderCard() async {
    final render = ++_render;
    try {
      final png = await renderAchievementCard(
        widget.achievement,
        includeDate: _includeDate,
        colors: _colors!,
      );
      if (!mounted || render != _render || _invalid) return;
      setState(() => _png = png);
    } on Object {
      if (mounted && render == _render) {
        setState(() => _status = 'ยังสร้างภาพไม่ได้ ปิดแล้วลองใหม่ได้');
      }
    }
  }

  Future<void> _revalidate() async {
    if (!_foreground) {
      _resumed ??= Completer<void>();
      await _resumed!.future;
    }
    _cancellation.throwIfCancelled();
    if (!_current) throw const ExportException(ExportFailureCode.cancelled);
    await widget.revalidate();
    if (!_current) throw const ExportException(ExportFailureCode.cancelled);
  }

  Future<void> _output({required bool share}) async {
    final png = _png;
    if (!_current || _busy || png == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    widget.onExternalOperation(true);
    try {
      await _revalidate();
      if (share) {
        await (widget.shareImage ?? const NativeAchievementSharer().share)(
          Uint8List.fromList(png),
          _revalidate,
        );
      } else {
        final saver = widget.saveImage;
        if (saver != null) {
          await saver(Uint8List.fromList(png), _cancellation, _revalidate);
        } else {
          await const FileSelectorExportStore().saveImage(
            pngBytes: png,
            cancellation: _cancellation,
            revalidateBeforeWrite: _revalidate,
          );
        }
      }
      await _revalidate();
      if (_current) {
        setState(
          () => _status = share
              ? 'เปิดเมนูแชร์แล้ว แอปไม่ยืนยันว่าภาพถูกส่ง'
              : 'บันทึกภาพในตำแหน่งที่เลือกแล้ว',
        );
      }
    } on ExportException catch (error) {
      if (mounted) {
        setState(
          () => _status = error.code == ExportFailureCode.cancelled
              ? 'คำขอนี้สิ้นสุดแล้ว กลับไปเลือกความสำเร็จอีกครั้ง'
              : 'ยังบันทึกหรือแชร์ภาพไม่ได้ ลองใหม่หรือบันทึกภาพแทนได้',
        );
      }
    } on Object {
      if (mounted) {
        setState(() => _status = 'ยังบันทึกหรือแชร์ภาพไม่ได้ ลองใหม่ได้');
      }
    } finally {
      widget.onExternalOperation(false);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = shareableAchievementTitle(widget.achievement);
    final ready = _current && !_busy && _png != null && title != null;
    return Scaffold(
      appBar: AppBar(title: const Text('ตัวอย่างการ์ดความสำเร็จ')),
      body: AdaptiveContentPane(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'ภาพมีเฉพาะชื่อความสำเร็จและวันที่หากคุณเลือก '
              'ไม่มีชื่อ บัญชี คำตอบ หรือข้อมูลวิจัย',
            ),
            const SizedBox(height: 16),
            if (_invalid)
              const Text(
                'ข้อมูลหรือหน้าจอเปลี่ยนแล้ว ปิดหน้านี้และเปิดความสำเร็จใหม่',
              )
            else if (_png != null)
              Semantics(
                key: const ValueKey('achievement-card-preview'),
                image: true,
                label:
                    '$title${_includeDate ? ' ${achievementCardDate(widget.achievement.unlockedAtUtc)}' : ''}',
                child: ExcludeSemantics(
                  child: Image.memory(_png!, gaplessPlayback: false),
                ),
              )
            else
              const Text('กำลังสร้างภาพตัวอย่าง'),
            const SizedBox(height: 12),
            CheckboxListTile(
              key: const ValueKey('achievement-include-date'),
              contentPadding: EdgeInsets.zero,
              title: const Text('ใส่วันที่ปลดล็อกในภาพ'),
              subtitle: const Text('ปิดไว้ก่อนเพื่อแชร์ข้อมูลให้น้อยที่สุด'),
              value: _includeDate,
              onChanged: _current && !_busy
                  ? (value) {
                      setState(() {
                        _includeDate = value == true;
                        _png = null;
                        _status = null;
                      });
                      unawaited(_renderCard());
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('achievement-save-image'),
                  onPressed: ready ? () => _output(share: false) : null,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('บันทึกภาพ PNG'),
                ),
                FilledButton.icon(
                  key: const ValueKey('achievement-share-image'),
                  onPressed: ready ? () => _output(share: true) : null,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('เปิดเมนูแชร์ภาพ'),
                ),
                TextButton(
                  key: const ValueKey('achievement-cancel'),
                  onPressed: () {
                    _cancellation.cancel();
                    Navigator.of(context).pop();
                  },
                  child: const Text('ยกเลิกและปิด'),
                ),
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('กำลังเตรียมภาพที่คุณเลือก'),
              ),
            if (_status != null)
              Semantics(liveRegion: true, child: Text(_status!)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _render++;
    _cancellation.cancel();
    _resumed?.complete();
    _resumed = null;
    widget.scopeChanges.removeListener(_scopeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
