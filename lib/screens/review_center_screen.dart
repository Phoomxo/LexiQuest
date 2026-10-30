import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/progress/application/review_center_use_cases.dart';
import '../features/progress/domain/review_center_models.dart';
import '../features/vocabulary/application/saved_words_use_cases.dart';
import '../features/vocabulary/application/word_report_use_cases.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import '../widgets/word_report_sheet.dart';
import 'learning_history_screen.dart';
import 'quiz_screen.dart';
import 'saved_words_screen.dart';
import 'srs_flashcards_screen.dart';
import 'word_reports_screen.dart';

/// Owner-bound composition of existing review reads. Practice uses the existing
/// canonical activity screens; this screen never writes learning or queue facts.
class ReviewCenterScreen extends StatefulWidget {
  const ReviewCenterScreen({
    super.key,
    required this.expectedOwnerId,
    this.reviewCenter,
    this.ownerChanges,
    this.learning,
    this.savedWords,
    this.wordReports,
    this.voice,
    this.featureRegistry,
    this.languageCode = 'th',
  });

  final String expectedOwnerId;
  final ReviewCenterUseCases? reviewCenter;
  final Stream<String?>? ownerChanges;
  final LearningUseCases? learning;
  final SavedWordsUseCases? savedWords;
  final WordReportUseCases? wordReports;
  final VoiceUseCases? voice;
  final FieldFeatureRegistry? featureRegistry;
  final String languageCode;

  @override
  State<ReviewCenterScreen> createState() => _ReviewCenterScreenState();
}

/// A transient return intent, distinct from the lifetime of private read rows.
final class _ReviewLaunch {
  _ReviewLaunch({required this.generation, required this.quiz});
  final int generation;
  final bool quiz;
  Route<dynamic>? route;
  Route<dynamic>? score;
  bool returnCurrent = true;
  bool contextCurrent = true;
}

class _ReviewCenterScreenState extends State<ReviewCenterScreen>
    with WidgetsBindingObserver {
  AppDependencies? _dependencies;
  ReviewCenterUseCases? _review;
  LearningUseCases? _learning;
  SavedWordsUseCases? _saved;
  WordReportUseCases? _reports;
  VoiceUseCases? _voice;
  FieldFeatureRegistry? _features;
  Stream<String?>? _owners;
  StreamSubscription<String?>? _ownerSubscription;
  StreamSubscription<ReviewCenterSnapshot>? _read;
  ReviewCenterSnapshot? _snapshot;
  ModalRoute<dynamic>? _route;
  ReviewQueue? _filter;
  _ReviewLaunch? _launch;
  final _changes = ValueNotifier<int>(0);
  bool _bound = false;
  bool _invalidated = false;
  bool _ownerKnown = false;
  bool _foreground = false;
  bool _paneVisible = true;
  bool _readFailed = false;
  bool _notificationScheduled = false;
  int _readEpoch = 0;
  int _launchGeneration = 0;

  String _text(String th, String en) => widget.languageCode == 'en' ? en : th;
  bool get _contextCurrent =>
      mounted && !_invalidated && _ownerKnown && _foreground && _paneVisible;
  bool get _readVisible =>
      _contextCurrent && _route?.isCurrent == true && _launch == null;
  bool get _ready => _readVisible && _snapshot != null && !_readFailed;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final route = ModalRoute.of(context);
    final current = ModalRoute.isCurrentOf(context) == true;
    final visible = Visibility.of(context);
    if (!_bound) {
      _bound = true;
      _route = route;
      _dependencies = dependencies;
      _review = widget.reviewCenter ?? dependencies?.reviewCenter;
      _learning = widget.learning ?? dependencies?.learning;
      _saved =
          widget.savedWords ?? dependencies?.savedWords ?? _review?.savedWords;
      _reports =
          widget.wordReports ??
          dependencies?.wordReports ??
          _review?.wordReports;
      _voice = widget.voice ?? dependencies?.voice;
      _features = widget.featureRegistry ?? dependencies?.fieldFeatures;
      _owners =
          widget.ownerChanges ??
          dependencies?.progress?.watchActiveOwnerId() ??
          _review?.progress.watchActiveOwnerId();
      _paneVisible = visible;
      WidgetsBinding.instance.addPostFrameCallback((_) => _observeOwner());
      return;
    }
    if (!identical(route, _route) ||
        !identical(dependencies, _dependencies) ||
        !visible) {
      _paneVisible = visible;
      _invalidate();
      return;
    }
    _paneVisible = visible;
    if (!current) {
      _clearRead();
      if (_launch == null) {
        _invalidate();
      }
    } else if (_readVisible && _read == null && !_readFailed) {
      _startRead();
    }
  }

  @override
  void didUpdateWidget(covariant ReviewCenterScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        !identical(oldWidget.reviewCenter, widget.reviewCenter) ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges) ||
        !identical(oldWidget.learning, widget.learning) ||
        !identical(oldWidget.savedWords, widget.savedWords) ||
        !identical(oldWidget.wordReports, widget.wordReports) ||
        !identical(oldWidget.voice, widget.voice) ||
        !identical(oldWidget.featureRegistry, widget.featureRegistry)) {
      _invalidate();
    }
  }

  void _observeOwner() {
    if (!mounted || _invalidated) {
      return;
    }
    final owners = _owners;
    if (_review == null || owners == null) {
      _invalidate();
      return;
    }
    _ownerSubscription = owners.listen(
      (owner) {
        if (!mounted || _invalidated) {
          return;
        }
        if (owner != widget.expectedOwnerId) {
          _invalidate();
          return;
        }
        _ownerKnown = true;
        if (_readVisible && _read == null && !_readFailed) {
          _startRead();
        }
      },
      onError: (Object _, StackTrace _) => _invalidate(),
      onDone: _invalidate,
    );
  }

  void _clearRead() {
    _readEpoch++;
    final read = _read;
    _read = null;
    _snapshot = null;
    _filter = null;
    _readFailed = false;
    unawaited(read?.cancel());
    _changed();
  }

  void _invalidate() {
    if (!mounted || _invalidated) {
      return;
    }
    _invalidated = true;
    _ownerKnown = false;
    _launchGeneration++;
    _launch?.returnCurrent = false;
    _launch?.contextCurrent = false;
    unawaited(_ownerSubscription?.cancel());
    _ownerSubscription = null;
    _clearRead();
  }

  void _changed() {
    if (!mounted || _notificationScheduled) {
      return;
    }
    _notificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      if (!mounted) {
        return;
      }
      _changes.value++;
      setState(() {});
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _startRead() {
    final review = _review;
    if (!_readVisible || review == null || _read != null) {
      return;
    }
    final epoch = ++_readEpoch;
    _readFailed = false;
    _changed();
    bool current() => _readVisible && epoch == _readEpoch;
    final subscription = review
        .watchOwner(
          expectedOwnerId: widget.expectedOwnerId,
          stillCurrent: current,
        )
        .listen(
          (snapshot) {
            if (!current()) {
              return;
            }
            if (snapshot.ownerId != widget.expectedOwnerId) {
              _invalidate();
              return;
            }
            _snapshot = snapshot;
            _changed();
          },
          onError: (Object error, StackTrace _) {
            if (!current()) {
              return;
            }
            if (error is ReviewCenterReadException &&
                error.code == ReviewReadFailureCode.ownerInvalidated) {
              _invalidate();
              return;
            }
            _retireRead(epoch);
          },
          onDone: () {
            if (!current()) {
              return;
            }
            _retireRead(epoch);
          },
        );
    if (current()) {
      _read = subscription;
    } else {
      unawaited(subscription.cancel());
    }
  }

  void _retireRead(int epoch) {
    if (!_readVisible || epoch != _readEpoch) {
      return;
    }
    _readEpoch++;
    final read = _read;
    _read = null;
    _snapshot = null;
    _filter = null;
    _readFailed = true;
    unawaited(read?.cancel());
    _changed();
  }

  void _refresh() {
    if (!_readVisible) {
      return;
    }
    _clearRead();
    _startRead();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _invalidate();
    }
  }

  bool _launchCurrent(_ReviewLaunch launch) =>
      _contextCurrent &&
      launch.contextCurrent &&
      launch.generation == _launchGeneration &&
      identical(launch, _launch);

  void _watchChild(_ReviewLaunch launch, bool current) {
    final route = launch.route;
    if (!_launchCurrent(launch) ||
        current ||
        route?.isActive != true ||
        _route?.isCurrent == true) {
      return;
    }
    // The exact Score route may legitimately cover its own Quiz. A further
    // cover is handled by its callback, without unmounting new mistake practice.
    if (launch.quiz && launch.score != null) {
      return;
    }
    launch.returnCurrent = false;
  }

  void _scoreChanged(
    _ReviewLaunch launch,
    Route<dynamic>? route,
    bool current,
  ) {
    if (!_launchCurrent(launch)) {
      return;
    }
    launch.score = route;
    if (route != null &&
        route.isActive &&
        !current &&
        launch.route?.isCurrent != true) {
      launch.returnCurrent = false;
    }
  }

  Future<void> _openChild({
    required String name,
    required int epoch,
    required Widget Function(_ReviewLaunch) builder,
    bool quiz = false,
  }) async {
    if (!_ready || epoch != _readEpoch) {
      return;
    }
    final launch = _ReviewLaunch(generation: _launchGeneration, quiz: quiz);
    _launch = launch;
    _clearRead();
    try {
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: name,
          builder: (childContext) => ValueListenableBuilder<int>(
            valueListenable: _changes,
            builder: (context, _, child) {
              final current = ModalRoute.isCurrentOf(context) == true;
              _watchChild(launch, current);
              if (!_launchCurrent(launch)) {
                return _unavailableChild(launch);
              }
              return child!;
            },
            child: builder(launch),
          ),
        ),
        onRouteCreated: (route) => launch.route = route,
      );
    } finally {
      if (identical(_launch, launch)) {
        final resume =
            _launchCurrent(launch) &&
            launch.returnCurrent &&
            _route?.isCurrent == true;
        _launch = null;
        if (resume) {
          _startRead();
        } else {
          _invalidate();
        }
      }
    }
  }

  Widget _unavailableChild(_ReviewLaunch launch) => Scaffold(
    appBar: AppBar(
      leading: BackButton(
        onPressed: () {
          if (launch.route?.isCurrent == true) {
            launch.route?.navigator?.pop();
          }
        },
      ),
    ),
    body: Center(
      child: Text(_text('กิจกรรมไม่พร้อมใช้งาน', 'Activity unavailable')),
    ),
  );

  bool _feature(FieldFeature feature) =>
      _features == null || _features!.isVisible(feature);

  List<String> _targets(ReviewCenterSnapshot snapshot, ReviewQueue queue) =>
      List.unmodifiable(
        snapshot.wordRows
            .where((row) => row.isEligible && row.queues.contains(queue))
            .take(20)
            .map((row) => row.wordId),
      );

  void _practice(
    ReviewCenterSnapshot snapshot,
    ReviewQueue queue,
    int epoch, {
    ReviewWordRow? row,
    ReviewQueue? filter,
  }) {
    if (!_ready ||
        epoch != _readEpoch ||
        !identical(snapshot, _snapshot) ||
        (row != null && (!identical(filter, _filter) || !row.isEligible)) ||
        _learning == null) {
      return;
    }
    final learning = _learning!;
    final owners = _owners!;
    final owner = widget.expectedOwnerId;
    if (queue == ReviewQueue.due) {
      if (!_feature(FieldFeature.srs) || _targets(snapshot, queue).isEmpty) {
        return;
      }
      unawaited(
        _openChild(
          name: 'review-center/due',
          epoch: epoch,
          builder: (_) => SrsFlashcardsScreen(
            expectedOwnerId: owner,
            ownerChanges: owners,
            learning: learning,
            voice: _voice,
            languageCode: widget.languageCode,
          ),
        ),
      );
      return;
    }
    if (!_feature(FieldFeature.quiz)) {
      return;
    }
    final ids = row == null
        ? _targets(snapshot, queue)
        : List<String>.unmodifiable([row.wordId]);
    if (ids.isEmpty) {
      return;
    }
    unawaited(
      _openChild(
        name: 'review-center/${queue.name}',
        epoch: epoch,
        quiz: true,
        builder: (launch) => QuizScreen(
          expectedOwnerId: owner,
          ownerChanges: owners,
          learning: learning,
          wordIds: ids,
          selectionMode: queue == ReviewQueue.saved
              ? QuizWordSelectionMode.sourcePractice
              : QuizWordSelectionMode.weakness,
          onScoreRouteChanged: (route, current) =>
              _scoreChanged(launch, route, current),
        ),
      ),
    );
  }

  void _manage(String destination, int epoch) {
    final owner = widget.expectedOwnerId;
    final owners = _owners;
    final review = _review;
    if (owners == null || review == null) {
      return;
    }
    unawaited(
      _openChild(
        name: 'review-center/$destination',
        epoch: epoch,
        builder: (launch) => switch (destination) {
          'saved' => SavedWordsScreen(
            expectedOwnerId: owner,
            ownerChanges: owners,
            savedWords: _saved,
            learning: _learning,
            languageCode: widget.languageCode,
          ),
          'reports' => WordReportsScreen(
            expectedOwnerId: owner,
            ownerChanges: owners,
            wordReports: _reports,
            languageCode: widget.languageCode,
          ),
          _ => LearningHistoryScreen(
            ownerChanges: owners,
            loader: ({before}) => review.progress.loadHistoryForOwner(
              expectedOwnerId: owner,
              stillCurrent: () =>
                  _launchCurrent(launch) && launch.returnCurrent,
              before: before,
            ),
          ),
        },
      ),
    );
  }

  @override
  void dispose() {
    _invalidated = true;
    _readEpoch++;
    _launchGeneration++;
    unawaited(_ownerSubscription?.cancel());
    unawaited(_read?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _changes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: _route?.canPop == true
          ? BackButton(
              onPressed: () {
                if (_route?.isCurrent == true) {
                  Navigator.of(context).pop();
                }
              },
            )
          : null,
      toolbarHeight: M3Theme.appBarToolbarHeight(context),
      title: M3Theme.appBarTitle(context, _text('ศูนย์ทบทวน', 'Review Center')),
    ),
    body: AdaptiveContentPane(child: _body()),
  );

  Widget _body() {
    if (_invalidated || (!_readVisible && _ownerKnown)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _text('ศูนย์ทบทวนไม่พร้อมใช้งาน', 'Review Center unavailable'),
            key: const ValueKey('review-center-status'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return Center(
        child: _readFailed
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _text(
                        'อ่านข้อมูลไม่สำเร็จ',
                        'Could not load review queues.',
                      ),
                    ),
                    OutlinedButton(
                      key: const ValueKey('review-center-refresh'),
                      onPressed: _refresh,
                      child: Text(_text('ลองใหม่', 'Retry')),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(
                key: ValueKey('review-center-status'),
              ),
      );
    }
    final epoch = _readEpoch;
    final filter = _filter;
    final words = filter == ReviewQueue.reported
        ? const <ReviewWordRow>[]
        : snapshot.wordRows
              .where((row) => filter == null || row.queues.contains(filter))
              .toList(growable: false);
    final reports = filter == null || filter == ReviewQueue.reported
        ? snapshot.reportRows
        : const <ReviewReportRow>[];
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 1 + words.length + reports.length,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _header(snapshot, epoch);
        }
        if (index <= words.length) {
          return _wordRow(snapshot, words[index - 1], epoch, filter);
        }
        return _reportRow(reports[index - words.length - 1], epoch, filter);
      },
    );
  }

  String _queueName(ReviewQueue queue) => switch (queue) {
    ReviewQueue.due => _text('ถึงกำหนด', 'Due'),
    ReviewQueue.incorrect => _text('ประวัติตอบผิด', 'Incorrect history'),
    ReviewQueue.saved => _text('บันทึกไว้', 'Saved'),
    ReviewQueue.reported => _text('รายงานในเครื่อง', 'Local reports'),
  };

  Widget _header(ReviewCenterSnapshot snapshot, int epoch) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final queue in ReviewQueue.values)
        Text(
          '${_queueName(queue)}: ${switch (snapshot.queueStates[queue]!) {
            ReviewQueueReady(:final count) => '$count',
            ReviewQueueLoading() => _text('กำลังอ่าน', 'Loading'),
            ReviewQueueUnavailable() => _text('ไม่พร้อมใช้งาน', 'Unavailable'),
          }}',
          key: ValueKey('review-center-count-${queue.name}'),
        ),
      const SizedBox(height: 12),
      Text(
        _text(
          'คำในคิวที่อ่านสำเร็จ: ${snapshot.distinctWordCount}',
          'Words in ready queues: ${snapshot.distinctWordCount}',
        ),
        key: const ValueKey('review-center-word-count'),
      ),
      Text(
        _text(
          'พร้อมฝึก ${snapshot.eligibleWordCount} คำ · ไม่พร้อมใช้ ${snapshot.unavailableWordCount} คำ',
          '${snapshot.eligibleWordCount} available · ${snapshot.unavailableWordCount} unavailable words',
        ),
      ),
      Text(
        _text(
          'ประเมินเวลา UTC: ${snapshot.evaluatedAtUtc.toIso8601String()}',
          'Evaluated at UTC: ${snapshot.evaluatedAtUtc.toIso8601String()}',
        ),
        key: const ValueKey('review-center-evaluated-at'),
      ),
      OutlinedButton.icon(
        key: const ValueKey('review-center-refresh'),
        onPressed: _ready && epoch == _readEpoch ? _refresh : null,
        icon: const Icon(Icons.refresh),
        label: Text(_text('อ่านสถานะล่าสุด', 'Refresh queues')),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final queue in <ReviewQueue?>[null, ...ReviewQueue.values])
            ChoiceChip(
              key: ValueKey('review-center-filter-${queue?.name ?? 'all'}'),
              label: Text(
                queue == null
                    ? _text('ทั้งหมด', 'All')
                    : queue == ReviewQueue.incorrect
                    ? _text('ตอบผิด', 'Incorrect')
                    : _queueName(queue),
              ),
              selected: _filter == queue,
              onSelected: (_) {
                if (_ready &&
                    epoch == _readEpoch &&
                    identical(snapshot, _snapshot)) {
                  setState(() => _filter = queue);
                }
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        _text(
          'ฝึกครั้งละไม่เกิน 20 คำที่พร้อมใช้ รายการด้านล่างแสดงครบทุกคำ เหตุผลอาจซ้ำคำเดียวกันได้',
          'Practice up to 20 available words per round. The full list below keeps every reason; queue counts can overlap.',
        ),
      ),
      for (final queue in [
        ReviewQueue.due,
        ReviewQueue.saved,
        ReviewQueue.incorrect,
      ])
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: ValueKey('review-center-${queue.name}-practice'),
              onPressed:
                  _learning == null ||
                      !_feature(
                        queue == ReviewQueue.due
                            ? FieldFeature.srs
                            : FieldFeature.quiz,
                      ) ||
                      _targets(snapshot, queue).isEmpty
                  ? null
                  : () => _practice(snapshot, queue, epoch),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _text(
                    'ฝึก${_queueName(queue)} (สูงสุด ${queue == ReviewQueue.due ? 20 : _targets(snapshot, queue).length} คำ)',
                    'Practice ${_queueName(queue)} (up to ${queue == ReviewQueue.due ? 20 : _targets(snapshot, queue).length} words)',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      for (final (destination, key, label, enabled) in [
        (
          'saved',
          'review-center-manage-saved',
          _text('จัดการคำที่บันทึก', 'Manage saved words'),
          _saved != null,
        ),
        (
          'reports',
          'review-center-reports',
          _text('ประวัติรายงานในเครื่อง', 'Local report history'),
          _reports != null,
        ),
        (
          'history',
          'review-center-history',
          _text('ประวัติการเรียน', 'Learning history'),
          _review != null,
        ),
      ])
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: ValueKey(key),
            onPressed: enabled ? () => _manage(destination, epoch) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(label, textAlign: TextAlign.center),
            ),
          ),
        ),
      const SizedBox(height: 16),
      if (snapshot.wordRows.isEmpty &&
          snapshot.reportRows.isEmpty &&
          snapshot.queueStates.values.every(
            (state) => state is ReviewQueueReady,
          ))
        Text(_text('ยังไม่มีรายการให้ทบทวน', 'No review items yet.')),
    ],
  );

  Widget _wordRow(
    ReviewCenterSnapshot snapshot,
    ReviewWordRow row,
    int epoch,
    ReviewQueue? filter,
  ) => Card(
    key: ValueKey('review-center-word:${row.wordId}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.word case final word?) ...[
            Text(word.spelling, style: Theme.of(context).textTheme.titleLarge),
            Text(word.meaning),
            Text('${word.partOfSpeech} · ${row.categoryName}'),
          ] else
            Text(
              _text('คำนี้ไม่พร้อมใช้งาน', 'This word is unavailable'),
              key: ValueKey('review-center-unavailable:${row.wordId}'),
            ),
          const SizedBox(height: 8),
          for (final reason in row.reasons)
            Text(
              switch (reason) {
                DueReason(:final dueAtUtc) => _text(
                  'ถึงกำหนด UTC: ${dueAtUtc.toIso8601String()}',
                  'Due at UTC: ${dueAtUtc.toIso8601String()}',
                ),
                IncorrectReason(
                  :final incorrectCount,
                  :final lastIncorrectAtUtc,
                ) =>
                  _text(
                    'ประวัติตอบผิด $incorrectCount ครั้ง · ล่าสุด UTC ${lastIncorrectAtUtc.toIso8601String()}',
                    'Incorrect history: $incorrectCount · last at UTC ${lastIncorrectAtUtc.toIso8601String()}',
                  ),
                SavedReason(:final state) => _text(
                  'บันทึกไว้เมื่อ UTC ${state.firstSavedAtUtc.toIso8601String()}',
                  'Saved at UTC ${state.firstSavedAtUtc.toIso8601String()}',
                ),
              },
              key: ValueKey(
                'review-center-reason:${reason.queue.name}:${row.wordId}',
              ),
            ),
          if (row.isEligible &&
              _learning != null &&
              _feature(FieldFeature.quiz))
            for (final queue in [ReviewQueue.saved, ReviewQueue.incorrect])
              if (row.queues.contains(queue))
                OutlinedButton(
                  key: ValueKey(
                    'review-center-practice-${queue.name}:${row.wordId}',
                  ),
                  onPressed: () => _practice(
                    snapshot,
                    queue,
                    epoch,
                    row: row,
                    filter: filter,
                  ),
                  child: Text(
                    _text(
                      'ฝึกคำนี้ (${_queueName(queue)})',
                      'Practice this word (${_queueName(queue)})',
                    ),
                  ),
                ),
        ],
      ),
    ),
  );

  Widget _reportRow(ReviewReportRow row, int epoch, ReviewQueue? filter) =>
      Card(
        child: ExpansionTile(
          key: ValueKey('review-center-report:${row.reportId}'),
          title: Text(
            _text('รายงานในเครื่อง · ยังไม่ได้ส่ง', 'Local report · Not sent.'),
          ),
          subtitle: Text(row.report.target.spelling),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            if (_ready && epoch == _readEpoch && filter == _filter)
              WordReportDetails(
                report: row.report,
                languageCode: widget.languageCode,
              ),
          ],
        ),
      );
}
