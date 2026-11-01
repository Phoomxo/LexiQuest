import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/research/application/controlled_study_archive_use_cases.dart';
import 'package:vocab_learning_app/features/research/domain/study_archive.dart';
import 'package:vocab_learning_app/features/research/presentation/study_archive_screen.dart';

void main() {
  testWidgets('lists authorized cycles and saves only after acknowledgement', (
    tester,
  ) async {
    final owners = StreamController<String?>.broadcast();
    final repository = _ArchiveRepository();
    final store = _Store();
    addTearDown(owners.close);
    await tester.pumpWidget(
      MaterialApp(
        home: StudyArchiveScreen(
          archives: ControlledStudyArchiveUseCases(
            repository: repository,
            store: store,
          ),
          ownerChanges: owners.stream,
        ),
      ),
    );
    owners.add('synthetic-owner');
    await tester.pumpAndSettle();
    expect(find.textContaining('กำลังเก็บข้อมูล'), findsOneWidget);
    expect(find.textContaining('synthetic-cycle'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('study-archive-save')));
    await tester.pump();
    expect(find.textContaining('บันทึกไฟล์แล้ว'), findsNothing);
    store.release.complete();
    await tester.pumpAndSettle();
    expect(store.writes, 1);
    expect(find.textContaining('บันทึกไฟล์แล้ว'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'changing owner during picker cancels and hides the previous cycle',
    (tester) async {
      final owners = StreamController<String?>.broadcast();
      final repository = _ArchiveRepository();
      final store = _Store();
      addTearDown(owners.close);
      await tester.pumpWidget(
        MaterialApp(
          home: StudyArchiveScreen(
            archives: ControlledStudyArchiveUseCases(
              repository: repository,
              store: store,
            ),
            ownerChanges: owners.stream,
          ),
        ),
      );
      owners.add('synthetic-owner');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('study-archive-save')));
      await tester.pump();
      owners.add(null);
      await tester.pump();
      expect(find.textContaining('กำลังเก็บข้อมูล'), findsNothing);
      store.release.complete();
      await tester.pumpAndSettle();
      expect(store.writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _ArchiveRepository implements StudyArchiveRepository {
  final preview = StudyArchivePreview(
    target: const StudyArchiveTarget(
      expectedOwnerId: 'synthetic-owner',
      studyCycleId: 'synthetic-cycle',
    ),
    state: 'active',
    startedAtUtc: DateTime.utc(2026, 11, 1),
    motivationResponseCount: 2,
    assessmentPhases: const ['pre'],
    missingPhases: const ['post'],
  );
  @override
  Future<List<StudyArchivePreview>> listCycles({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async {
    if (!stillCurrent() || expectedOwnerId != preview.target.expectedOwnerId) {
      throw const ExportException(ExportFailureCode.unavailable);
    }
    return [preview];
  }

  @override
  Future<PreparedStudyArchive> prepare(
    StudyArchiveTarget target, {
    required bool Function() stillCurrent,
  }) async {
    if (!stillCurrent()) {
      throw const ExportException(ExportFailureCode.unavailable);
    }
    return _Prepared(preview);
  }

  @override
  Future<void> requireCurrent(
    PreparedStudyArchive prepared, {
    required bool Function() stillCurrent,
  }) async {
    if (!stillCurrent()) {
      throw const ExportException(ExportFailureCode.unavailable);
    }
  }
}

class _Prepared implements PreparedStudyArchive {
  _Prepared(this.preview);
  @override
  final StudyArchivePreview preview;
  @override
  ExportArtifact get artifact => ExportArtifact(
    format: ExportFormat.researchJson,
    suggestedFileName: 'controlled-study.json',
    mimeType: 'application/json',
    bytes: Uint8List.fromList([123, 125]),
    recordCount: 1,
    schemaVersion: 1,
    algorithmVersion: 1,
    generatedAtUtc: DateTime.utc(2026, 11, 1),
    timeZone: 'UTC',
    exclusions: const [],
  );
}

class _Store implements ExportArtifactStore {
  final release = Completer<void>();
  int writes = 0;
  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required ExportWriteRevalidator revalidateBeforeWrite,
  }) async {
    await release.future;
    cancellation.throwIfCancelled();
    await revalidateBeforeWrite();
    writes++;
    return const ExportSaveResult(
      path: 'controlled-study.json',
      bytesWritten: 2,
    );
  }
}
