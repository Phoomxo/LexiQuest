import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/application/content_report_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../features/content_reports/content_report_test_support.dart';
import '../support/motivation_presentation_io.dart';
import 'learning_pack_test_support.dart';

void main() {
  for (final supplied in [true, false]) {
    testWidgets(
      'actual reading reports exact passage with ${supplied ? 'supplied' : 'digest'} source identity',
      (tester) async {
        final harness = await motivationPresentationIo(
          tester,
          LearningPackUiHarness.open,
          stage: 'q1-reading-open',
        );
        final queue = MemoryContentReportQueue()
          ..activeOwner = 'synthetic-actions-owner';
        try {
          await _mount(tester, harness, queue, supplied: supplied);
          await _tap(tester, 'content-report-reading');
          await _tap(tester, 'content-report-selection-review');
          await _tap(tester, 'content-report-reason:spelling');
          await _tap(tester, 'content-report-review');
          await _tap(tester, 'content-report-save');
          await _wait(tester, () => queue.rows.length == 1, 'saved-row');
          final row = queue.rows.values.single;
          final target =
              jsonDecode(row.payload.target.snapshotJson)
                  as Map<String, dynamic>;
          expect(row.payload.target.text, 'The synthetic cat rests.');
          final digest = sha256
              .convert(utf8.encode('The synthetic cat rests.'))
              .toString();
          expect(target['source'], {
            'documentId': supplied ? 'synthetic-document' : digest,
            'documentRevision': 3,
            'documentSha256': digest,
            'identityKind': supplied ? 'supplied' : 'contentDigest',
          });
          expect(
            row.payload.reportJson,
            isNot(contains('unselected learner target')),
          );
        } finally {
          await closeMotivationPresentation(tester, harness.close);
        }
      },
    );
  }
  testWidgets(
    'actual Study reading exposes no report action and creates no report',
    (tester) async {
      final harness = await motivationPresentationIo(
        tester,
        LearningPackUiHarness.open,
        stage: 'q1-study-reading-open',
      );
      final queue = MemoryContentReportQueue()
        ..activeOwner = 'synthetic-actions-owner';
      try {
        await _mount(tester, harness, queue, study: true);
        expect(
          find.byKey(const ValueKey('content-report-reading')),
          findsNothing,
        );
        expect(queue.rows, isEmpty);
      } finally {
        await closeMotivationPresentation(tester, harness.close);
      }
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  LearningPackUiHarness harness,
  MemoryContentReportQueue queue, {
  bool supplied = true,
  bool study = false,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await motivationPresentationDeadline(
    tester,
    'q1-reading-mount',
    () => tester.pumpWidget(
      AppDependenciesScope(
        dependencies: AppDependencies(
          runtimeStatus: const AppRuntimeStatus(
            localData: RuntimeAvailability.ready,
            firebase: RuntimeAvailability.unavailable,
            supabase: RuntimeAvailability.unavailable,
            backends: RuntimeAvailability.unavailable,
          ),
          config: null,
          guestSessionService: _Guest(),
          learning: harness.learning,
          progress: ProgressUseCases(
            owners: harness.learning.owners,
            queries: DriftProgressQueries(harness.database),
            nowUtc: () => DateTime.utc(2026),
          ),
          contentReports: ContentReportUseCases(
            queue: queue,
            generateId: () => 'synthetic-reading',
            nowUtc: () => DateTime.utc(2026),
          ),
        ),
        child: MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'B1',
            targetWords: const ['unselected learner target'],
            passageText: 'The synthetic cat rests.',
            documentId: supplied ? 'synthetic-document' : null,
            documentRevision: 3,
            ownerId: 'synthetic-actions-owner',
            timeCallerContext: study
                ? LearningTimeCallerContext.researchControlled
                : LearningTimeCallerContext.ordinary,
          ),
        ),
      ),
    ),
  );
  await _wait(
    tester,
    () => find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย').evaluate().isNotEmpty,
    'reading-ready',
  );
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('Reports cannot create an owner');
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _wait(tester, () {
    if (finder.evaluate().length != 1) return false;
    final widget = tester.widget(finder);
    if (widget is ButtonStyleButton) return widget.onPressed != null;
    if (widget is ChoiceChip) return widget.onSelected != null;
    return tester
        .widgetList<IconButton>(
          find.descendant(of: finder, matching: find.byType(IconButton)),
        )
        .any((button) => button.onPressed != null);
  }, 'enabled-$key');
  await motivationPresentationDeadline(
    tester,
    'entry-transition-$key',
    () => tester.pump(const Duration(milliseconds: 350)),
  );
  if (finder.hitTestable().evaluate().isEmpty) {
    await motivationPresentationIo(
      tester,
      () => Scrollable.ensureVisible(tester.element(finder), alignment: 0.5),
      stage: 'scroll-$key',
    );
  }
  await _wait(
    tester,
    () => finder.hitTestable().evaluate().length == 1,
    'hit-testable-$key',
  );
  await motivationPresentationDeadline(
    tester,
    'pump-$key',
    () => tester.pump(),
  );
  await motivationPresentationDeadline(
    tester,
    'tap-$key',
    () => tester.tap(finder.hitTestable()),
  );
  await motivationPresentationDeadline(
    tester,
    'transition-$key',
    () => tester.pump(const Duration(milliseconds: 350)),
  );
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready,
  String stage,
) async {
  for (var frame = 0; frame < 160; frame++) {
    if (ready()) {
      return;
    }
    await motivationPresentationIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
      stage: 'q1-reading-$stage',
    );
    await motivationPresentationDeadline(
      tester,
      'q1-reading-frame-$stage',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
  }
  fail('Q1 reading did not reach $stage');
}
