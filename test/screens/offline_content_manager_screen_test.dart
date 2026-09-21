import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_detail.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/offline_content/application/offline_content_manager.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_state.dart';
import 'package:vocab_learning_app/screens/offline_content_manager_screen.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  for (final status in OfflineContentStatus.values) {
    testWidgets('optional offline context reports actual ${status.name}', (
      tester,
    ) async {
      final state = _state(status, bytes: 8192);
      final registry = MenuActionRegistry(currentOwner: () => 'test');
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(
            home: OfflineContentManagerScreen(
              manager: _FakeManager([state]),
              canInvoke: () => false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final data = jsonDecode(
        (registry.snapshot()['context'] as List).single['value'] as String,
      );
      expect(data['status'], status.name);
      expect(data['verified'], state.hasVerifiedBytes);
      expect(data['downloadedBytes'], state.downloadedBytes);
      expect(data['manifestBytes'], 4096);
      expect(data.containsKey('requiredBytes'), false);
      expect(
        data['byteCountMeaning'],
        state.hasVerifiedBytes
            ? 'installed-total-including-adapter-files'
            : 'downloaded-so-far-not-verified',
      );
      expect(data['byteCountsComparableAsProgress'], false);
      expect(data['nativeActionsEnabled'], false);
      expect(data['revision'], state.identity.revision);
      expect(data.containsKey('path'), false);
      expect(registry.snapshot()['actions'], isEmpty);
    });
  }

  testWidgets('B08 shows manifest size and cancels a pending download', (
    tester,
  ) async {
    final manager = _FakeManager([_state(OfflineContentStatus.notDownloaded)])
      ..waitDownload = true;
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('พื้นที่ไฟล์อย่างน้อย 4.0 KB'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('offline-content/download/pack-a')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('offline-content/cancel/pack-a')),
    );
    await tester.pumpAndSettle();
    expect(manager.cancelled, [_identity]);
    expect(find.text('การดาวน์โหลดถูกขัดจังหวะ'), findsOneWidget);
    expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsNothing);
  });

  testWidgets(
    'offline primary label is faithful with exact identity available in details',
    (tester) async {
      final manager = _FakeManager([
        _state(OfflineContentStatus.verified, bytes: 4096),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('pack-a'), findsNothing);
      expect(find.textContaining('4.0 KB'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('offline-content/details/pack-a')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('pack-a'), findsOneWidget);
      expect(find.textContaining('รุ่น 1'), findsOneWidget);
      expect(find.textContaining('4096 ไบต์'), findsOneWidget);
    },
  );

  for (final mismatch in [false, true]) {
    testWidgets(
      'offline pack title requires matching verified revision mismatch=$mismatch',
      (tester) async {
        const identity = ContentIdentity(
          type: ContentType.learningPack,
          id: 'pack-a',
          revision: 1,
        );
        final manager = _FakeManager([
          _state(OfflineContentStatus.notDownloaded, identity: identity),
        ]);
        final pack = LearningPackSummary(
          packId: 'pack-a',
          revision: mismatch ? 2 : 1,
          title: 'คำศัพท์สำหรับการเดินทาง',
          cefrLevel: 'A1',
          topic: 'travel',
          skill: 'recognition',
          goal: 'practice',
          contentIdentity: ContentIdentity(
            type: ContentType.learningPack,
            id: 'pack-a',
            revision: mismatch ? 2 : 1,
          ),
        );
        await tester.pumpWidget(_withPackMetadata(manager, pack));
        await tester.pumpAndSettle();
        expect(
          find.text('คำศัพท์สำหรับการเดินทาง'),
          mismatch ? findsNothing : findsOneWidget,
        );
        if (mismatch) expect(find.text('ชุดเนื้อหาการเรียน'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('offline-content/download/pack-a')),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'f44 screen renders verified state and removes only local bytes',
    (tester) async {
      final manager = _FakeManager(<OfflineContentState>[
        _state(
          OfflineContentStatus.verified,
          localPath: '${List<String>.filled(64, 'a').join()}.content',
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ไฟล์สำหรับใช้งานออฟไลน์'), findsOneWidget);
      expect(find.textContaining('พร้อมใช้งานออฟไลน์'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('offline-content/remove/pack-a')),
      );
      await tester.pumpAndSettle();

      expect(manager.removed, <ContentIdentity>[_identity]);
      expect(find.textContaining('ยังไม่ได้ดาวน์โหลด'), findsOneWidget);
    },
  );

  testWidgets('f44 quarantine offers repair and serializes item actions', (
    tester,
  ) async {
    final manager = _FakeManager(<OfflineContentState>[
      _state(OfflineContentStatus.quarantined),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('offline-content/repair/pack-a')),
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('offline-content/busy/pack-a')),
          )
          .onPressed,
      isNull,
    );
    manager.repairCompleter.complete(_state(OfflineContentStatus.verified));
    await tester.pumpAndSettle();
    expect(manager.repaired, <ContentIdentity>[_identity]);
  });

  testWidgets('f44 kill switch fences a stale action before invocation', (
    tester,
  ) async {
    var enabled = true;
    final manager = _FakeManager(<OfflineContentState>[
      _state(OfflineContentStatus.notDownloaded),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineContentManagerScreen(
          manager: manager,
          canInvoke: () => enabled,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final stale = tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('offline-content/download/pack-a')),
        )
        .onPressed!;

    enabled = false;
    stale();
    await tester.pump();
    expect(manager.downloaded, isEmpty);
  });

  testWidgets(
    'f44 review pinned revision exposes exact identity and no remove action',
    (tester) async {
      final manager = _FakeManager(<OfflineContentState>[
        _state(
          OfflineContentStatus.verified,
          localPath: '${List<String>.filled(64, 'a').join()}.content',
        ),
      ])..pinned.add(_identity);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final details = find.byKey(
        const ValueKey('offline-content/details/pack-a'),
      );
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('รหัส: pack-a · รุ่น 1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('offline-content/remove/pack-a')),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel('จำเป็นต่อการเรียนที่กำลังดำเนินอยู่'),
        findsOneWidget,
      );
    },
  );
}

const _identity = ContentIdentity(
  type: ContentType.offlineArtifact,
  id: 'pack-a',
  revision: 1,
);

OfflineContentState _state(
  OfflineContentStatus status, {
  String? localPath,
  int bytes = 4,
  ContentIdentity identity = _identity,
}) => OfflineContentState(
  manifestId: 'manifest:pack-a:r1',
  identity: identity,
  status: status,
  localPath: status == OfflineContentStatus.verified
      ? localPath ?? '${List<String>.filled(64, 'a').join()}.content'
      : localPath,
  downloadedBytes: status == OfflineContentStatus.verified ? bytes : 0,
  verifiedChecksumSha256: status == OfflineContentStatus.verified
      ? List<String>.filled(64, 'a').join()
      : null,
  failureCode: status == OfflineContentStatus.quarantined
      ? OfflineContentFailureCode.checksumMismatch
      : status == OfflineContentStatus.interrupted
      ? OfflineContentFailureCode.interrupted
      : null,
  updatedAtUtc: DateTime.utc(2026, 8, 30),
);

Widget _withPackMetadata(
  OfflineContentManager manager,
  LearningPackSummary pack,
) {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final research = InertResearchDependencies(database);
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'synthetic:offline-title',
    nowUtc: () => DateTime.utc(2026, 9, 8),
  );
  final dependencies = AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _Guest(),
    quest: testQuestUseCases(),
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    features: const BuildFeatureRegistry({
      Feature.studyPlanning: FeatureState.enabled,
    }),
    studyPlanning: StudyPlanningUseCases(
      packs: _PackRepository(pack),
      progress: ProgressUseCases(
        owners: owners,
        queries: DriftProgressQueries(database),
        nowUtc: () => DateTime.utc(2026, 9, 8),
      ),
    ),
  );
  return AppDependenciesScope(
    dependencies: dependencies,
    child: MaterialApp(
      home: OfflineContentManagerScreen(
        manager: manager,
        canInvoke: () => true,
      ),
    ),
  );
}

final class _PackRepository implements LearningPackRepository {
  _PackRepository(this.summary);
  final LearningPackSummary summary;
  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async => [
    summary,
  ];
  @override
  Future<LearningPackDetail> getVersion(String packId, int revision) async =>
      LearningPackDetail(summary: summary, vocabularyWordIds: const []);
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-offline');
}

final class _FakeManager
    implements OfflineContentManager, OfflineContentDownloadControl {
  _FakeManager(this.values);

  final List<OfflineContentState> values;
  final downloaded = <ContentIdentity>[];
  final cancelled = <ContentIdentity>[];
  bool waitDownload = false;
  final downloadCompleter = Completer<OfflineContentState>();

  @override
  Future<int> requiredBytes(ContentIdentity identity) async => 4096;

  @override
  Future<bool> cancelDownload(ContentIdentity identity) async {
    cancelled.add(identity);
    downloadCompleter.complete(
      _replace(identity, OfflineContentStatus.interrupted),
    );
    return true;
  }

  final removed = <ContentIdentity>[];
  final repaired = <ContentIdentity>[];
  final pinned = <ContentIdentity>{};
  final repairCompleter = Completer<OfflineContentState>();

  @override
  Future<List<OfflineContentState>> catalog() async => List.of(values);

  @override
  Future<bool> canRemove(ContentIdentity identity) async =>
      !pinned.contains(identity);

  @override
  Future<OfflineContentState> download(ContentIdentity identity) async {
    downloaded.add(identity);
    if (waitDownload) return downloadCompleter.future;
    return _replace(identity, OfflineContentStatus.verified);
  }

  @override
  Future<OfflineContentState> repair(ContentIdentity identity) async {
    repaired.add(identity);
    final result = await repairCompleter.future;
    _replace(identity, result.status);
    return result;
  }

  @override
  Future<int> removeBytes(ContentIdentity identity) async {
    removed.add(identity);
    _replace(identity, OfflineContentStatus.notDownloaded);
    return 0;
  }

  @override
  Future<OfflineContentState> verify(ContentIdentity identity) async =>
      values.singleWhere((state) => state.identity == identity);

  @override
  Future<int> cleanupForDiskPressure({required int bytesToFree}) async => 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> reconcile() async {}

  OfflineContentState _replace(
    ContentIdentity identity,
    OfflineContentStatus status,
  ) {
    final index = values.indexWhere((state) => state.identity == identity);
    final next = _state(
      status,
      localPath: status == OfflineContentStatus.verified
          ? '${List<String>.filled(64, 'a').join()}.content'
          : null,
    );
    values[index] = next;
    return next;
  }
}
