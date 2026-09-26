import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/application/learner_intent_use_cases.dart';
import 'package:vocab_learning_app/features/review/data/drift_learner_intent_repository.dart';
import 'package:vocab_learning_app/features/review/data/drift_content_quality_report_repository.dart';
import 'package:vocab_learning_app/features/review/domain/learner_intent.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/review/presentation/bookmark_learning_item_button.dart';
import 'package:vocab_learning_app/features/review/presentation/content_report_sheet.dart';
import 'package:vocab_learning_app/features/review/application/content_report_use_cases.dart';
import 'package:vocab_learning_app/runtime/registries/consent_registry.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/review/domain/review_mutation_context.dart';

const identity = ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: 'word:ar',
  revision: 3,
);
final now = DateTime.utc(2026, 9, 25);
SaveLearningItemCommand command(String id) =>
    SaveLearningItemCommand(id: id, contentIdentity: identity, savedAtUtc: now);
ContentQualityReport report() => ContentQualityReport(
  id: 'report:ar',
  contentIdentity: identity,
  reason: ContentReportReason.text,
  comment: null,
  submittedAtUtc: now,
);

void main() {
  group('isolated owner resolution', () {
    late db.AppDatabase database;
    late DriftLocalOwnerRepository canonical;
    late _PausedOwners owners;
    late DriftLearnerIntentRepository intents;
    var serial = 0;
    setUp(() async {
      database = db.AppDatabase(NativeDatabase.memory());
      canonical = DriftLocalOwnerRepository(
        database,
        generateId: () => 'owner:${serial++}',
        nowUtc: () => now,
      );
      await canonical.getOrCreateActiveOwner();
      owners = _PausedOwners(canonical);
      intents = DriftLearnerIntentRepository(
        database,
        owners: owners,
        nowUtc: () => now,
      );
    });
    tearDown(() => database.close());

    Future<void> replaceOwner() async {
      await database.transaction(() async {
        await database
            .update(database.localOwners)
            .write(const db.LocalOwnersCompanion(isActive: Value(false)));
      });
      await canonical.getOrCreateActiveOwner();
    }

    for (final action in ['save', 'unsave', 'report']) {
      test(
        'AR $action cannot redirect after initial owner resolution',
        () async {
          await intents.save(command('saved:original'));
          final before = await database
              .select(database.savedLearningItems)
              .get();
          owners.pause = true;
          final pending = switch (action) {
            'save' => intents.save(command('saved:pending')),
            'unsave' => intents.unsave(identity),
            _ => DriftContentQualityReportRepository(
              database,
              owners: owners,
            ).submit(report()),
          };
          final observed = expectLater(pending, throwsStateError);
          await owners.entered.future;
          await replaceOwner();
          owners.release.complete();
          await observed;
          expect(
            await database.select(database.savedLearningItems).get(),
            before,
          );
          expect(
            await database.select(database.contentQualityReports).get(),
            isEmpty,
          );
          expect(
            await database.select(database.outboxOperations).get(),
            hasLength(1),
          );
        },
      );
    }
    for (final action in ['save', 'unsave', 'report']) {
      test(
        'AR $action rejects displayed owner replaced before repository entry',
        () async {
          final original = await canonical.getOrCreateActiveOwner();
          await replaceOwner();
          await expectLater(
            ReviewMutationContext.run(
              () => switch (action) {
                'save' => intents.save(command('saved:stale')),
                'unsave' => intents.unsave(identity),
                _ => DriftContentQualityReportRepository(
                  database,
                  owners: owners,
                ).submit(report()),
              },
              isCurrent: () => true,
              expectedOwnerId: original.id,
            ),
            throwsStateError,
          );
          expect(
            await database.select(database.savedLearningItems).get(),
            isEmpty,
          );
          expect(
            await database.select(database.contentQualityReports).get(),
            isEmpty,
          );
          expect(
            await database.select(database.outboxOperations).get(),
            isEmpty,
          );
        },
      );
    }
  });

  for (final action in ['unsave', 'resave']) {
    for (final boundary in ['saved_learning_items', 'outbox_operations']) {
      test(
        'AR $action rollback after $boundary retains original revision and tombstone',
        () async {
          final pause = _WritePause(boundary);
          final database = db.AppDatabase(
            NativeDatabase.memory().interceptWith(pause),
          );
          addTearDown(database.close);
          final owners = DriftLocalOwnerRepository(
            database,
            generateId: () => 'rollback',
            nowUtc: () => now,
          );
          final intents = DriftLearnerIntentRepository(
            database,
            owners: owners,
            nowUtc: () => now,
          );
          await intents.save(command('saved:original'));
          if (action == 'resave') await intents.unsave(identity);
          final before = await database
              .select(database.savedLearningItems)
              .get();
          final outbox = await database.select(database.outboxOperations).get();
          var current = true;
          pause.armed = true;
          final pending = ReviewMutationContext.run(
            () => action == 'unsave'
                ? intents.unsave(identity)
                : intents.save(command('saved:resave')),
            isCurrent: () => current,
          );
          final observed = expectLater(pending, throwsStateError);
          await pause.entered.future;
          current = false;
          pause.release.complete();
          await observed;
          expect(
            await database.select(database.savedLearningItems).get(),
            before,
          );
          expect(
            await database.select(database.outboxOperations).get(),
            outbox,
          );
        },
      );
    }
  }

  testWidgets(
    'AR post-commit bookmark notifier failure is uncertain and manual retry is idempotent',
    (tester) async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'notifier',
        nowUtc: () => now,
      );
      var notices = 0;
      var calls = 0;
      final cases = LearnerIntentUseCases(
        repository: DriftLearnerIntentRepository(
          database,
          owners: owners,
          nowUtc: () => now,
          onLocalMutation: () async {
            notices++;
            throw StateError('notification lost after commit');
          },
        ),
        generateId: () => 'saved:${calls++}',
        nowUtc: () => now,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookmarkLearningItemButton(
              identity: identity,
              onSave: cases.bookmark,
            ),
          ),
        ),
      );
      await tester.tap(find.text('บันทึกไว้ทบทวน'));
      await tester.pumpAndSettle();
      expect(find.text('ยังยืนยันการบันทึกไม่ได้ ลองอีกครั้ง'), findsOneWidget);
      expect(find.text('บันทึกไว้ในเครื่องแล้ว'), findsNothing);
      expect(
        await database.select(database.savedLearningItems).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.outboxOperations).get(),
        hasLength(1),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(calls, 1);
      await tester.tap(find.text('บันทึกไว้ทบทวน'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(notices, 1);
      expect(find.text('บันทึกไว้ในเครื่องแล้ว'), findsOneWidget);
      expect(
        await database.select(database.savedLearningItems).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.outboxOperations).get(),
        hasLength(1),
      );
    },
  );

  for (final retirement in ['tab', 'cover', 'pop', 'lifecycle', 'dependency']) {
    testWidgets(
      'AR report $retirement while consent pending cannot commit after return',
      (tester) async {
        final database = db.AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'report',
          nowUtc: () => now,
        );
        await owners.getOrCreateActiveOwner();
        final consent = _PausedConsent()..pause = true;
        final cases = ContentReportUseCases(
          repository: DriftContentQualityReportRepository(
            database,
            owners: owners,
            consentRegistry: consent,
            uploadPolicy: const ContentReportUploadPolicy.v1(
              deployedRulesRevision: contentQualityReportV1RulesRevision,
              consentVersion: 1,
            ),
          ),
          generateId: () => 'report:pending',
          nowUtc: () => now,
        );
        ContentReportSheetSubmit action = ({required reason, comment}) =>
            cases.report(identity: identity, reason: reason, comment: comment);
        var enabled = true;
        late StateSetter update;
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('parent')),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Scaffold(
                  body: TickerMode(
                    enabled: enabled,
                    child: ContentReportSheet(
                      identity: identity,
                      onSubmit: action,
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('ปัญหาข้อความ'));
        await tester.pump();
        await tester.tap(find.text('ส่งรายงาน'));
        await tester.pumpAndSettle();
        expect(consent.entered.isCompleted, isTrue);
        if (retirement == 'tab') {
          update(() => enabled = false);
          await tester.pump();
          update(() => enabled = true);
          await tester.pump();
        } else if (retirement == 'cover') {
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          );
          await tester.pumpAndSettle();
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
        } else if (retirement == 'pop') {
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
        } else if (retirement == 'lifecycle') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
        } else {
          update(() => action = ({required reason, comment}) async {});
          await tester.pump();
        }
        consent.release.complete();
        await tester.pumpAndSettle();
        expect(
          await database.select(database.contentQualityReports).get(),
          isEmpty,
        );
        expect(await database.select(database.outboxOperations).get(), isEmpty);
        expect(
          find.text('บันทึกรายงานในเครื่องแล้ว ยังไม่ยืนยันการส่งถึงปลายทาง'),
          findsNothing,
        );
      },
    );
  }

  testWidgets(
    'AR post-commit report notifier failure preserves draft and explicit semantic retry',
    (tester) async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'notifier',
        nowUtc: () => now,
      );
      var notices = 0;
      var calls = 0;
      final cases = ContentReportUseCases(
        repository: DriftContentQualityReportRepository(
          database,
          owners: owners,
          consentRegistry: _PausedConsent(),
          uploadPolicy: const ContentReportUploadPolicy.v1(
            deployedRulesRevision: contentQualityReportV1RulesRevision,
            consentVersion: 1,
          ),
          onLocalMutation: () async {
            notices++;
            throw StateError('notification lost after commit');
          },
        ),
        generateId: () => 'report:${calls++}',
        nowUtc: () => now,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentReportSheet(
              identity: identity,
              onSubmit: ({required reason, comment}) => cases.report(
                identity: identity,
                reason: reason,
                comment: comment,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ปัญหาข้อความ'));
      await tester.enterText(find.byType(TextField), 'Keep my draft');
      await tester.pump();
      await tester.tap(find.text('ส่งรายงาน'));
      await tester.pumpAndSettle();
      expect(find.text('ยังยืนยันการส่งรายงานไม่ได้'), findsOneWidget);
      expect(find.text('Keep my draft'), findsOneWidget);
      expect(
        await database.select(database.contentQualityReports).get(),
        hasLength(1),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(calls, 1);
      await tester.tap(find.text('ส่งรายงาน'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(notices, 1);
      expect(
        find.text('บันทึกรายงานในเครื่องแล้ว ยังไม่ยืนยันการส่งถึงปลายทาง'),
        findsOneWidget,
      );
      expect(
        await database.select(database.contentQualityReports).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.outboxOperations).get(),
        hasLength(1),
      );
    },
  );

  testWidgets('AR disposed bookmark rolls back admitted pending save', (
    tester,
  ) async {
    // Construct this connection and its serialized owner future in the widget
    // test zone; setUp's real-zone future cannot be advanced by fake pumping.
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final canonical = DriftLocalOwnerRepository(
      database,
      generateId: () => 'widget',
      nowUtc: () => now,
    );
    await canonical.getOrCreateActiveOwner();
    final owners = _PausedOwners(canonical);
    final intents = DriftLearnerIntentRepository(
      database,
      owners: owners,
      nowUtc: () => now,
    );
    owners.pause = true;
    final cases = LearnerIntentUseCases(
      repository: intents,
      generateId: () => 'saved:ui',
      nowUtc: () => now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookmarkLearningItemButton(
            identity: identity,
            onSave: cases.bookmark,
          ),
        ),
      ),
    );
    await tester.tap(find.text('บันทึกไว้ทบทวน'));
    await tester.pumpAndSettle();
    expect(owners.entered.isCompleted, isTrue);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    owners.release.complete();
    await tester.pumpAndSettle();
    final rows = await database.select(database.savedLearningItems).get();
    expect(rows, isEmpty);
    expect(await database.select(database.outboxOperations).get(), isEmpty);
  });

  for (final retirement in ['tab', 'cover', 'lifecycle', 'dependency']) {
    testWidgets(
      'AR bookmark $retirement retirement stays cancelled after return',
      (tester) async {
        final database = db.AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final canonical = DriftLocalOwnerRepository(
          database,
          generateId: () => 'widget',
          nowUtc: () => now,
        );
        await canonical.getOrCreateActiveOwner();
        final owners = _PausedOwners(canonical)..pause = true;
        final intents = DriftLearnerIntentRepository(
          database,
          owners: owners,
          nowUtc: () => now,
        );
        final cases = LearnerIntentUseCases(
          repository: intents,
          generateId: () => 'saved:ui',
          nowUtc: () => now,
        );
        var enabled = true;
        BookmarkLearningItemAction action = cases.bookmark;
        late StateSetter update;
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Scaffold(
                  body: TickerMode(
                    enabled: enabled,
                    child: BookmarkLearningItemButton(
                      identity: identity,
                      onSave: action,
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('บันทึกไว้ทบทวน'));
        await tester.pumpAndSettle();
        expect(owners.entered.isCompleted, isTrue);
        if (retirement == 'tab') {
          update(() => enabled = false);
          await tester.pump();
          update(() => enabled = true);
          await tester.pump();
        } else if (retirement == 'cover') {
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          );
          await tester.pumpAndSettle();
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
        } else if (retirement == 'lifecycle') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
        } else {
          update(() => action = (_) async {});
          await tester.pump();
        }
        owners.release.complete();
        await tester.pumpAndSettle();
        expect(
          await database.select(database.savedLearningItems).get(),
          isEmpty,
        );
        expect(await database.select(database.outboxOperations).get(), isEmpty);
      },
    );
  }

  for (final boundary in ['saved_learning_items', 'outbox_operations']) {
    testWidgets(
      'AR bookmark disposal after $boundary write rolls back both rows',
      (tester) async {
        final pause = _WritePause(boundary);
        final database = db.AppDatabase(
          NativeDatabase.memory().interceptWith(pause),
        );
        addTearDown(database.close);
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'partial',
          nowUtc: () => now,
        );
        await owners.getOrCreateActiveOwner();
        final cases = LearnerIntentUseCases(
          repository: DriftLearnerIntentRepository(
            database,
            owners: owners,
            nowUtc: () => now,
          ),
          generateId: () => 'saved:partial',
          nowUtc: () => now,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BookmarkLearningItemButton(
                identity: identity,
                onSave: cases.bookmark,
              ),
            ),
          ),
        );
        pause.armed = true;
        await tester.tap(find.text('บันทึกไว้ทบทวน'));
        await tester.pumpAndSettle();
        expect(pause.entered.isCompleted, isTrue);
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        pause.release.complete();
        await tester.pumpAndSettle();
        expect(
          await database.select(database.savedLearningItems).get(),
          isEmpty,
        );
        expect(await database.select(database.outboxOperations).get(), isEmpty);
      },
    );
  }

  for (final boundary in [
    'consent',
    'content_quality_reports',
    'outbox_operations',
  ]) {
    testWidgets(
      'AR report retirement during $boundary rolls back local and queued data',
      (tester) async {
        final pause = _WritePause(boundary);
        final consent = _PausedConsent()..pause = boundary == 'consent';
        final database = db.AppDatabase(
          NativeDatabase.memory().interceptWith(pause),
        );
        addTearDown(database.close);
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'report',
          nowUtc: () => now,
        );
        await owners.getOrCreateActiveOwner();
        final cases = ContentReportUseCases(
          repository: DriftContentQualityReportRepository(
            database,
            owners: owners,
            consentRegistry: consent,
            uploadPolicy: const ContentReportUploadPolicy.v1(
              deployedRulesRevision: contentQualityReportV1RulesRevision,
              consentVersion: 1,
            ),
          ),
          generateId: () => 'report:partial',
          nowUtc: () => now,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ContentReportSheet(
                identity: identity,
                onSubmit: ({required reason, comment}) => cases.report(
                  identity: identity,
                  reason: reason,
                  comment: comment,
                ),
              ),
            ),
          ),
        );
        pause.armed = boundary != 'consent';
        await tester.tap(find.text('ปัญหาข้อความ'));
        await tester.pump();
        await tester.tap(find.text('ส่งรายงาน'));
        await tester.pumpAndSettle();
        expect(
          boundary == 'consent'
              ? consent.entered.isCompleted
              : pause.entered.isCompleted,
          isTrue,
        );
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        if (boundary == 'consent') {
          consent.release.complete();
        } else {
          pause.release.complete();
        }
        await tester.pumpAndSettle();
        expect(
          await database.select(database.contentQualityReports).get(),
          isEmpty,
        );
        expect(await database.select(database.outboxOperations).get(), isEmpty);
      },
    );
  }
}

final class _WritePause extends QueryInterceptor {
  _WritePause(this.table);
  final String table;
  bool armed = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<void> _pause(String statement) async {
    if (armed && statement.contains('"$table"')) {
      armed = false;
      entered.complete();
      await release.future;
    }
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await super.runUpdate(executor, statement, args);
    await _pause(statement);
    return result;
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await super.runInsert(executor, statement, args);
    await _pause(statement);
    return result;
  }
}

final class _PausedConsent implements ConsentRegistry {
  bool pause = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ConsentSnapshot> snapshot({
    required ConsentPurpose purpose,
    required String ownerId,
    required int consentVersion,
  }) async {
    if (pause) {
      entered.complete();
      await release.future;
    }
    return ConsentSnapshot(
      purpose: purpose,
      ownerId: ownerId,
      consentVersion: consentVersion,
      state: ConsentState.granted,
      decisionUtc: now,
      withdrawalUtc: null,
    );
  }
}

final class _PausedOwners implements LocalOwnerRepository {
  _PausedOwners(this.delegate);
  final LocalOwnerRepository delegate;
  bool pause = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    final owner = await delegate.getOrCreateActiveOwner();
    if (pause) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return owner;
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      delegate.bindFirebaseUid(ownerId, firebaseUid);
}
