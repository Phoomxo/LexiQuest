import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/offline_content/application/offline_content_manager.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_state.dart';
import 'package:vocab_learning_app/screens/offline_content_manager_screen.dart';

void main() {
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

      expect(find.text('pack-a'), findsOneWidget);
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
      expect(
        find.bySemanticsLabel(
          'offlineArtifact pack-a revision 1 required by active learning',
        ),
        findsOneWidget,
      );
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

OfflineContentState _state(OfflineContentStatus status, {String? localPath}) =>
    OfflineContentState(
      manifestId: 'manifest:pack-a:r1',
      identity: _identity,
      status: status,
      localPath: status == OfflineContentStatus.verified
          ? localPath ?? '${List<String>.filled(64, 'a').join()}.content'
          : localPath,
      downloadedBytes: status == OfflineContentStatus.verified ? 4 : 0,
      verifiedChecksumSha256: status == OfflineContentStatus.verified
          ? List<String>.filled(64, 'a').join()
          : null,
      failureCode: status == OfflineContentStatus.quarantined
          ? OfflineContentFailureCode.checksumMismatch
          : null,
      updatedAtUtc: DateTime.utc(2026, 8, 30),
    );

final class _FakeManager implements OfflineContentManager {
  _FakeManager(this.values);

  final List<OfflineContentState> values;
  final downloaded = <ContentIdentity>[];
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
