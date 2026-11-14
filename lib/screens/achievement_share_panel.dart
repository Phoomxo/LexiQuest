import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../config/m3_theme.dart';
import '../features/export/domain/export_contracts.dart';
import '../features/motivation/domain/streak_policy.dart';
import '../features/quest/domain/quest_models.dart';
import '../features/quest/domain/quest_progress_models.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/registries/feature_registry.dart';

Future<void> showAchievementShare(
  BuildContext context, {
  required AppDependencies scope,
  required String ownerId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: false,
  enableDrag: false,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.9,
    child: _AchievementSharePanel(scope: scope, ownerId: ownerId),
  ),
);

enum _Page { motivation, edit, preview }

class _AchievementSharePanel extends StatefulWidget {
  const _AchievementSharePanel({required this.scope, required this.ownerId});

  final AppDependencies scope;
  final String ownerId;

  @override
  State<_AchievementSharePanel> createState() => _AchievementSharePanelState();
}

class _AchievementSharePanelState extends State<_AchievementSharePanel> {
  static const _channel = MethodChannel('com.lexiquest.app/achievement_share');
  final _art = GlobalKey();
  StreamSubscription<void>? _ownerWrites;
  _Page _page = _Page.motivation;
  bool _ownerChanged = false;
  bool _loading = false;
  bool _readStarted = false;
  bool _showDate = false;
  ExportCancellation? _operation;
  String? _error;
  String? _notice;
  String? _headline;
  DateTime? _learnedDay;
  QuestProgressCard? _dailyQuest;

  bool get _current =>
      mounted &&
      !_ownerChanged &&
      identical(AppDependenciesScope.maybeOf(context), widget.scope) &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _ownerWrites = widget.scope.watchLocalOwnerWrites()?.listen(
      (_) => _invalidate(),
      onError: (Object _) => _invalidate(),
    );
  }

  void _invalidate() {
    _operation?.cancel();
    if (mounted && !_ownerChanged) {
      setState(() {
        _ownerChanged = true;
        _headline = null;
        _learnedDay = null;
        _dailyQuest = null;
      });
    }
  }

  Future<void> _requireOwner() async {
    if (!_current) throw StateError('Achievement card is no longer active');
    final ownerId = await widget.scope.readActiveOwnerId();
    if (!_current) throw StateError('Achievement card is no longer active');
    if (ownerId != widget.ownerId) {
      _invalidate();
      throw StateError('Achievement owner changed');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_readStarted) return;
    _readStarted = true;
    unawaited(_loadProgress());
  }

  Future<void> _loadProgress() async {
    if (!_current || _loading) return;
    setState(() {
      _loading = true;
      _headline = null;
      _learnedDay = null;
      _dailyQuest = null;
      _error = null;
      _notice = null;
    });
    try {
      await _requireOwner();
      final progress = await widget.scope.progress!.load();
      await _requireOwner();
      if (progress.ownerId != widget.ownerId) {
        _invalidate();
        return;
      }
      if (widget.scope.features.isVisible(Feature.questV2)) {
        final cards = progress.quests?.current;
        final daily = cards?.where((card) => card.cadence == QuestType.daily);
        setState(() => _dailyQuest = daily?.firstOrNull);
      }
      final streak = progress.learningDays;
      if (streak == null ||
          streak.state.ownerId != widget.ownerId ||
          streak.status != StreakFoldStatus.ready ||
          streak.uncertainHistory) {
        setState(() => _error = 'ยังยืนยันวันที่ฝึกต่อเนื่องไม่ได้');
      } else if (streak.currentStreakDays > 0) {
        DateTime? latest;
        for (final marker in streak.days) {
          if (marker.studied &&
              (latest == null || marker.day.isAfter(latest))) {
            latest = marker.day;
          }
        }
        setState(() {
          _headline = 'ฝึกต่อเนื่อง ${streak.currentStreakDays} วัน';
          _learnedDay = latest;
        });
      }
    } catch (_) {
      if (_current) setState(() => _error = 'อ่านความสำเร็จไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Uint8List> _capture() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _art.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
      throw StateError('Achievement artwork is not rendered');
    }
    final size = boundary.size;
    final longest = size.longestSide;
    final image = await boundary.toImage(
      pixelRatio: (960 / longest).clamp(0.25, 3.0),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Achievement artwork is not encoded');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  Future<void> _output({required bool save}) async {
    if (!_current || _operation != null || _page != _Page.preview) return;
    final cancellation = ExportCancellation();
    setState(() {
      _operation = cancellation;
      _error = null;
      _notice = null;
    });
    Future<void> revalidate() async {
      cancellation.throwIfCancelled();
      await _requireOwner();
      cancellation.throwIfCancelled();
      if (_page != _Page.preview) {
        throw const ExportException(ExportFailureCode.cancelled);
      }
    }

    try {
      await revalidate();
      final bytes = await _capture();
      await revalidate();
      if (save) {
        final saveCard = widget.scope.saveAchievementCard;
        if (saveCard == null) {
          throw const ExportException(ExportFailureCode.unavailable);
        }
        await saveCard(
          bytes,
          cancellation: cancellation,
          revalidateBeforeWrite: revalidate,
        );
        if (_current) setState(() => _notice = 'บันทึกรูปการ์ดแล้ว');
      } else {
        await _channel.invokeMethod<void>('sharePng', bytes);
      }
    } catch (error) {
      if (_current &&
          !(error is ExportException &&
              error.code == ExportFailureCode.cancelled)) {
        setState(() {
          _error = save
              ? 'บันทึกรูปการ์ดไม่สำเร็จ กรุณาลองใหม่'
              : 'เปิดเมนูแชร์ไม่สำเร็จ กรุณาลองใหม่';
        });
      }
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  void _go(_Page page) => setState(() {
    _page = page;
    if (_headline != null) _error = null;
    _notice = null;
  });

  void _openEditor() {
    setState(() => _showDate = false);
    _go(_Page.edit);
  }

  Widget _questStatus(BuildContext context) {
    final quest = _dailyQuest;
    final correct = quest?.correctCount;
    final target = quest?.targetCount;
    final status = switch (quest?.state) {
      QuestProgressState.active => 'กำลังทำภารกิจ',
      QuestProgressState.completedUnclaimed => 'ทำครบแล้ว พร้อมรับรางวัล',
      QuestProgressState.claimed => 'รับรางวัลแล้ว',
      QuestProgressState.expired => 'จบช่วงภารกิจแล้ว',
      _ => 'ยังยืนยันภารกิจวันนี้ไม่ได้',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ภารกิจรายวัน',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_loading)
              const Text('กำลังอ่านภารกิจ')
            else ...[
              if (correct != null && target != null)
                Text('ตอบถูก $correct / $target ข้อ'),
              Text(status),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _operation?.cancel();
    unawaited(_ownerWrites?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid =
        !_ownerChanged &&
        identical(AppDependenciesScope.maybeOf(context), widget.scope);
    final busy = _operation != null;
    final headline = _headline;
    final learnedDay = _learnedDay;
    final date = _showDate && learnedDay != null
        ? 'วันที่ฝึก ${MaterialLocalizations.of(context).formatCompactDate(learnedDay)}'
        : null;
    final android = Theme.of(context).platform == TargetPlatform.android;
    final maySave =
        widget.scope.saveAchievementCard != null &&
        widget.scope.features.isVisible(Feature.export) &&
        widget.scope.fieldFeatures.isVisible(FieldFeature.export);
    final title = switch (_page) {
      _Page.motivation => 'ภารกิจและเพื่อนฝึก',
      _Page.edit => 'ทำการ์ดสิ่งที่ทำสำเร็จ',
      _Page.preview => 'ตรวจภาพก่อนแชร์',
    };
    return PopScope<void>(
      canPop: _page == _Page.motivation && !busy || !valid,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy && _page != _Page.motivation) {
          _go(_page == _Page.preview ? _Page.edit : _Page.motivation);
        }
      },
      child: SafeArea(
        child: SingleChildScrollView(
          key: ValueKey(_page),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!valid) ...[
                    const Text('บัญชีผู้เรียนเปลี่ยนแล้ว'),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('กลับไปแผนฝึก'),
                    ),
                  ] else if (_page == _Page.motivation) ...[
                    if (widget.scope.features.isVisible(Feature.questV2))
                      _questStatus(context),
                    FilledButton(
                      onPressed: _loading ? null : _openEditor,
                      child: const Text('การ์ดสิ่งที่ทำสำเร็จ'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('กลับไปแผนฝึก'),
                    ),
                  ] else ...[
                    if (_loading || busy)
                      LinearProgressIndicator(
                        semanticsLabel: busy
                            ? 'กำลังเตรียมรูปการ์ด'
                            : 'กำลังอ่านความสำเร็จ',
                      ),
                    if (headline != null) ...[
                      RepaintBoundary(
                        key: _art,
                        child: _Artwork(headline: headline, date: date),
                      ),
                      const SizedBox(height: 12),
                    ] else if (!_loading && _error == null)
                      const Text('ฝึกให้มีวันเรียนที่บันทึกก่อนสร้างการ์ด'),
                    if (_error != null)
                      Semantics(liveRegion: true, child: Text(_error!)),
                    if (_notice != null)
                      Semantics(liveRegion: true, child: Text(_notice!)),
                    if (_page == _Page.edit) ...[
                      if (headline != null) ...[
                        if (learnedDay != null)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('แสดงวันที่ฝึก'),
                            value: _showDate,
                            onChanged: (value) =>
                                setState(() => _showDate = value),
                          ),
                        const Text('การ์ดไม่มีชื่อ บัญชี หรือคำตอบของผู้เรียน'),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: () => _go(_Page.preview),
                          child: const Text('ดูตัวอย่างการแชร์'),
                        ),
                      ] else if (_error != null)
                        TextButton(
                          onPressed: _loading ? null : _loadProgress,
                          child: const Text('ลองใหม่'),
                        ),
                      TextButton(
                        onPressed: () => _go(_Page.motivation),
                        child: const Text('ยกเลิก'),
                      ),
                    ] else ...[
                      if (date == null) const Text('ซ่อนวันที่ฝึกแล้ว'),
                      if (android) ...[
                        FilledButton(
                          onPressed: busy ? null : () => _output(save: false),
                          child: const Text('แชร์ภาพ'),
                        ),
                        if (maySave)
                          OutlinedButton(
                            onPressed: busy ? null : () => _output(save: true),
                            child: const Text('บันทึกรูปการ์ด'),
                          ),
                      ] else
                        const Text('เปิดเมนูแชร์หรือบันทึกรูปได้บน Android'),
                      TextButton(
                        onPressed: busy ? null : () => _go(_Page.edit),
                        child: const Text('กลับไปแก้การ์ด'),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => _go(_Page.motivation),
                        child: const Text('จบการดูตัวอย่าง'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.headline, required this.date});

  final String headline;
  final String? date;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: M3Theme.primary,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.emoji_events, color: Color(0xFFFFE09B), size: 52),
          const SizedBox(height: 16),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            date ?? 'LexiQuest',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFFE09B)),
          ),
        ],
      ),
    ),
  );
}
