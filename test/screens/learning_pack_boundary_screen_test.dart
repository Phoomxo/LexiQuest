import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/learning_packs/data/http_learning_pack_source.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_download.dart';

import 'learning_pack_test_support.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'runtime replacement permanently retires a retained preview action',
    (tester) => _using(tester, (h) async {
      final pack = syntheticPackUiContent();
      Future<XFile?> picker() async =>
          XFile.fromData(pack.bytes, name: 'synthetic.json');
      await tester.pumpWidget(h.app(pickFile: picker));
      await packUiReady(tester);
      await tapPackUi(tester, 'pack-import');
      await untilPackUi(
        tester,
        () => find
            .byKey(const ValueKey('pack-confirm-install'))
            .evaluate()
            .isNotEmpty,
      );
      final retained = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('pack-confirm-install')),
          )
          .onPressed!;
      // This replaces the runtime object while retaining the same live pack service.
      await tester.pumpWidget(h.app(pickFile: picker));
      await untilPackUi(
        tester,
        () => find.text('แพ็กบทเรียนยังไม่พร้อมใช้งาน').evaluate().isNotEmpty,
      );
      retained();
      await tester.pump(const Duration(milliseconds: 32));
      expect(await tester.runAsync(() => h.count('learning_pack_versions')), 0);
      expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
      expect(await tester.runAsync(() => h.count('local_owners')), 2);
      expect(tester.takeException(), isNull);
    }),
  );

  testWidgets(
    'a changed canonical word rejects retained speech with visible stale feedback',
    (tester) => _using(tester, (h) async {
      await tester.runAsync(() => h.seed(syntheticPackUiContent()));
      await tester.pumpWidget(h.app());
      await openPackUiDetail(tester);
      await tapPackUi(tester, 'pack-word-cat');
      await untilPackUi(
        tester,
        () => find.text('A small pet that meows.').evaluate().isNotEmpty,
      );
      await revealPackUi(tester, 'pack-word-speak');
      final retained = tester
          .widget<FilledButton>(find.byKey(const ValueKey('pack-word-speak')))
          .onPressed!;
      await tester.runAsync(
        () => h.database.customUpdate(
          'UPDATE vocabulary_words SET local_revision=local_revision+1',
          updates: {h.database.vocabularyWords},
        ),
      );
      retained();
      await idlePackUi(tester);
      expect(h.voice.requests, isEmpty);
      await untilPackUi(
        tester,
        () => find
            .text('คำศัพท์เปลี่ยนแล้ว ไม่ใช้คำอธิบายเดิมกับการฝึกใหม่')
            .evaluate()
            .isNotEmpty,
      );
      expect(await tester.runAsync(() => h.count('saved_words')), 0);
      expect(await tester.runAsync(() => h.count('word_reports')), 0);
      expect(await tester.runAsync(() => h.count('learning_sessions')), 0);
      expect(tester.takeException(), isNull);
    }),
  );

  testWidgets(
    'configured anonymous HTTPS download verifies before explicit installation',
    (tester) => _using(tester, (h) async {
      final pack = syntheticPackUiContent();
      final descriptor = _descriptor(pack);
      final requests = <http.Request>[];
      final source = HttpLearningPackSource(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response.bytes(pack.bytes, 200);
        }),
        catalog: [descriptor],
      );
      try {
        await tester.pumpWidget(h.app(downloads: source));
        await _openRemote(tester);
        await tapPackUi(tester, 'pack-download');
        await untilPackUi(
          tester,
          () => find
              .text('ตรวจไฟล์แล้ว เลือกติดตั้งหรือเก็บไฟล์ออฟไลน์')
              .evaluate()
              .isNotEmpty,
        );
        expect(
          await tester.runAsync(() => h.count('learning_pack_versions')),
          0,
        );
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
        expect(requests, hasLength(1));
        expect(requests.single.url, descriptor.uri);
        expect(requests.single.method, 'GET');
        expect(
          requests.single.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')),
        );
        await tapPackUi(tester, 'pack-confirm-install');
        await idlePackUi(tester);
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 1);
        final stored = (await tester.runAsync(h.stored))!;
        expect(stored.source.kind, 'configuredCatalog');
        expect(stored.source.catalogId, descriptor.catalogId);
        expect(stored.packageSha256, pack.packageSha256);
        expect(tester.takeException(), isNull);
      } finally {
        source.dispose();
      }
    }),
  );

  testWidgets(
    'owner ABA during configured download cannot expose or install the old result',
    (tester) => _using(tester, (h) async {
      final pack = syntheticPackUiContent();
      final response = Completer<http.Response>();
      var calls = 0;
      final source = HttpLearningPackSource(
        client: MockClient((_) {
          calls++;
          return response.future;
        }),
        catalog: [_descriptor(pack)],
      );
      try {
        await tester.pumpWidget(h.app(downloads: source));
        await _openRemote(tester);
        await tapPackUi(tester, 'pack-download');
        await untilPackUi(tester, () => calls == 1);
        await tester.runAsync(() => h.switchOwner('synthetic-actions-other'));
        await packUiReady(tester);
        await tester.runAsync(() => h.switchOwner('synthetic-actions-owner'));
        await packUiReady(tester);
        response.complete(http.Response.bytes(pack.bytes, 200));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump(const Duration(milliseconds: 80));
        await idlePackUi(tester);
        expect(
          find.byKey(const ValueKey('pack-confirm-install')),
          findsNothing,
        );
        expect(
          await tester.runAsync(() => h.count('learning_pack_versions')),
          0,
        );
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
        expect(tester.takeException(), isNull);
      } finally {
        if (!response.isCompleted) {
          response.complete(http.Response('synthetic cancellation', 500));
        }
        source.dispose();
      }
    }),
  );

  testWidgets(
    'oversized file is rejected from length without opening its bytes',
    (tester) => _using(tester, (h) async {
      final file = _OversizedFile();
      await tester.pumpWidget(h.app(pickFile: () async => file));
      await packUiReady(tester);
      await tapPackUi(tester, 'pack-import');
      await untilPackUi(
        tester,
        () => find
            .text('ไฟล์แพ็กหรือรูปมีขนาดเกินขอบเขตที่รองรับ')
            .evaluate()
            .isNotEmpty,
      );
      expect(file.lengthReads, 1);
      expect(file.streamReads, 0);
      expect(await tester.runAsync(() => h.count('learning_pack_versions')), 0);
      expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
      expect(tester.takeException(), isNull);
    }),
  );

  testWidgets(
    'cancelled file picker leaves normal catalog usable without creating rows',
    (tester) => _using(tester, (h) async {
      await tester.pumpWidget(h.app(pickFile: () async => null));
      await packUiReady(tester);
      await tapPackUi(tester, 'pack-import');
      await packUiReady(tester);
      expect(find.byKey(const ValueKey('pack-confirm-install')), findsNothing);
      expect(await tester.runAsync(() => h.count('learning_pack_versions')), 0);
      expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
      expect(await tester.runAsync(() => h.count('local_owners')), 2);
      expect(tester.takeException(), isNull);
    }),
  );
}

Future<void> _using(
  WidgetTester tester,
  Future<void> Function(LearningPackUiHarness) body,
) async {
  final h = (await tester.runAsync(LearningPackUiHarness.open))!;
  try {
    await body(h);
  } catch (error, stack) {
    h.recordFailure(error, stack, tester);
    rethrow;
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await closePackUi(tester, h);
  }
}

Future<void> _openRemote(WidgetTester tester) async {
  await packUiReady(tester);
  final row = find.widgetWithText(ListTile, 'Synthetic actions pack');
  await tester.ensureVisible(row);
  await tester.pump(const Duration(milliseconds: 16));
  await tester.tap(row);
  await tester.pump(const Duration(milliseconds: 16));
}

LearningPackDownloadDescriptor _descriptor(LearningPack pack) =>
    LearningPackDownloadDescriptor(
      catalogId: 'synthetic-ui-catalog',
      manifest: pack.manifest,
      uri: Uri.parse('https://packs.example.test/one.json'),
      packageSha256: pack.packageSha256,
      packageByteCount: pack.byteCount,
    );

final class _OversizedFile extends XFile {
  _OversizedFile() : super('synthetic-oversized-file');
  var lengthReads = 0;
  var streamReads = 0;
  @override
  Future<int> length() async {
    lengthReads++;
    return maxLearningPackBytes + 1;
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    streamReads++;
    throw StateError('An oversized synthetic file must not allocate bytes');
  }
}
