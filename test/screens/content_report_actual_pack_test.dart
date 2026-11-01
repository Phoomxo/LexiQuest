import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/presentation/learning_pack_catalog_screen.dart';

import '../support/configured_quiz_harness.dart';
import '../support/content_report_caller_harness.dart';
import '../support/content_report_ui_io.dart';
import '../support/motivation_presentation_io.dart';
import 'learning_pack_test_support.dart' show syntheticPackUiContent;

void main() {
  for (final retire in [false, true]) {
    testWidgets(
      'actual pack ${retire ? 'owner change retires report callback' : 'report retains original package entry and visible lexical facts'}',
      (tester) async {
        final h = await motivationPresentationIo(
          tester,
          ContentReportCallerHarness.open,
          stage: 'pack-report-fixture',
        );
        try {
          final pack = _pack();
          await motivationPresentationIo(tester, () async {
            final scope = (await h.packs.captureOwner(
              stillCurrent: () => true,
            ))!;
            await h.packs.importPack(
              h.packs.prepareImport(scope: scope, pack: pack),
            );
          }, stage: 'pack-report-install');
          final stored = await motivationPresentationIo(
            tester,
            () => h.storage.database
                .customSelect(
                  "SELECT package_sha256 FROM learning_pack_versions WHERE owner_id='$configuredOwnerId'",
                )
                .getSingle(),
            stage: 'pack-original-digest',
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpWidget(h.app(const LearningPackCatalogScreen()));
          await reportUiWait(
            tester,
            'pack-row',
            () => find
                .widgetWithText(ListTile, pack.manifest.title)
                .evaluate()
                .isNotEmpty,
          );
          await reportUiTap(
            tester,
            find.widgetWithText(ListTile, pack.manifest.title).first,
            'pack-detail',
          );
          final entryRow = find.byKey(
            ValueKey('pack-word-${pack.entries.first.code}'),
          );
          await reportUiReveal(
            tester,
            entryRow,
            'pack-entry-row',
            scrollable: find.byType(ListView),
          );
          await reportUiTap(tester, entryRow, 'pack-entry');
          final ipa = find.textContaining('/kæt/');
          await reportUiReveal(
            tester,
            ipa,
            'pack-authored-ipa',
            scrollable: find.byType(ListView),
          );
          expect(ipa.hitTestable(), findsOneWidget);
          final entryAction = find.descendant(
            of: find.byKey(const ValueKey('content-report-pack-entry')),
            matching: find.byType(TextButton),
          );
          await reportUiReveal(
            tester,
            entryAction,
            'pack-report',
            scrollable: find.byType(ListView),
          );
          await reportUiWait(
            tester,
            'pack-report-enabled',
            () =>
                entryAction.evaluate().length == 1 &&
                tester.widget<TextButton>(entryAction).onPressed != null,
          );
          if (retire) {
            final retained = tester.widget<TextButton>(entryAction).onPressed!;
            await motivationPresentationIo(
              tester,
              () => h.storage.database.customUpdate(
                'UPDATE local_owners SET is_active = (id = ?)',
                variables: [drift.Variable<String>(configuredOtherOwnerId)],
                updates: {h.storage.database.localOwners},
              ),
              stage: 'pack-owner-change',
            );
            await reportUiWait(
              tester,
              'pack-owner-retired',
              () => entryAction.evaluate().isEmpty,
            );
            retained();
            await tester.pump(const Duration(milliseconds: 350));
            expect(
              find.byKey(const ValueKey('content-report-selection')),
              findsNothing,
            );
            expect(
              await motivationPresentationIo(
                tester,
                () => h.storage.count('content_reports'),
              ),
              0,
            );
            return;
          }
          await reportUiTap(tester, entryAction, 'pack-report');
          await reportUiTapKey(tester, 'content-report-selection-review');
          await reportUiTapKey(tester, 'content-report-reason:spelling');
          await reportUiTapKey(tester, 'content-report-review');
          await reportUiTapKey(tester, 'content-report-save');
          await reportUiWait(
            tester,
            'pack-local-receipt',
            () => find
                .text('บันทึกในเครื่อง ยังไม่มีใบรับเรื่องจากเซิร์ฟเวอร์')
                .evaluate()
                .isNotEmpty,
          );
          final rows = await motivationPresentationIo(
            tester,
            () => h.queue.watchOwner(configuredOwnerId).first,
          );
          final target =
              jsonDecode(rows.single.payload.target.snapshotJson)
                  as Map<String, dynamic>;
          expect(target['kind'], 'packEntry');
          expect(target['source'], {
            'packId': pack.manifest.packId,
            'packVersion': pack.manifest.version,
            'packageSha256': stored.read<String>('package_sha256'),
            'entryCode': pack.entries.first.code,
            'entrySha256': pack.entries.first.contentSha256,
          });
          expect(rows.single.payload.target.text, contains('/kæt/'));
          expect(rows.single.payload.target.text, contains('feline'));
          expect(
            await motivationPresentationIo(
              tester,
              () => h.storage.count('word_reports'),
            ),
            0,
          );
        } finally {
          await closeMotivationPresentation(tester, h.close);
        }
      },
    );
  }
}

LearningPack _pack() {
  final base = syntheticPackUiContent();
  final original = base.entries.first;
  return const LearningPackCodec().decode(
    const LearningPackCodec().encode(
      metadata: base.manifest,
      entries: [
        LearningPackEntry(
          code: original.code,
          spelling: original.spelling,
          meaning: original.meaning,
          partOfSpeech: original.partOfSpeech,
          definition: original.definition,
          examples: original.examples,
          memoryCue: original.memoryCue,
          hint: original.hint,
          strategy: original.strategy,
          definitionQuestion: original.definitionQuestion,
          lexicalDetails: LearningPackLexicalDetails(
            ipa: '/kæt/',
            synonyms: ['feline'],
          ),
        ),
        ...base.entries.skip(1),
      ],
    ),
  );
}
