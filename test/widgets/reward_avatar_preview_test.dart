import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/widgets/reward_avatar_preview.dart';

void main() {
  testWidgets(
    'catalog v2 headgear paints pixels distinct from the base avatar',
    (tester) async {
      final base = await _paintBytes(tester, itemId: null, catalogVersion: 2);
      final headgear = await _paintBytes(
        tester,
        itemId: 'headgear_ipa',
        catalogVersion: 2,
      );

      expect(headgear, isNot(orderedEquals(base)));
      expect(
        find.bySemanticsLabel('ตัวละครนักสำรวจสวมหมวก IPA'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'legacy mapping renders supported headgear without network assets',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const RewardAvatarPreview(catalogVersion: 1, itemId: 'headgear_ipa'),
        ),
      );

      expect(
        find.byKey(const ValueKey('reward-avatar-preview/headgear_ipa')),
        findsOneWidget,
      );
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown version and corrupt item fall back to identical base art',
    (tester) async {
      final base = await _paintBytes(tester, itemId: null, catalogVersion: 2);
      final unknownVersion = await _paintBytes(
        tester,
        itemId: 'headgear_ipa',
        catalogVersion: 999,
      );
      expect(unknownVersion, orderedEquals(base));
      expect(
        find.bySemanticsLabel('ตัวละครนักสำรวจ ภาพอุปกรณ์นี้ยังไม่พร้อม'),
        findsOneWidget,
      );

      final corruptItem = await _paintBytes(
        tester,
        itemId: 'headgear_ipa-corrupt',
        catalogVersion: 2,
      );
      expect(corruptItem, orderedEquals(base));
      expect(
        find.byKey(const ValueKey('reward-avatar-preview/base')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large text does not change the fixed artwork bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _app(
          const RewardAvatarPreview(
            catalogVersion: 2,
            itemId: 'headgear_ipa',
            size: 144,
          ),
        ),
      ),
    );

    expect(
      tester.getSize(
        find.byKey(const ValueKey('reward-avatar-preview/headgear_ipa')),
      ),
      const Size.square(144),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<Uint8List> _paintBytes(
  WidgetTester tester, {
  required int catalogVersion,
  required String? itemId,
}) async {
  const boundaryKey = ValueKey('avatar-pixels');
  await tester.pumpWidget(
    _app(
      RepaintBoundary(
        key: boundaryKey,
        child: RewardAvatarPreview(
          catalogVersion: catalogVersion,
          itemId: itemId,
        ),
      ),
    ),
  );
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  final bytes = await tester.runAsync<Uint8List>(() async {
    ui.Image? image;
    try {
      image = await boundary
          .toImage(pixelRatio: 1)
          .timeout(const Duration(seconds: 5));
      final data = await image
          .toByteData(format: ui.ImageByteFormat.rawRgba)
          .timeout(const Duration(seconds: 5));
      if (data == null) throw StateError('avatar raster returned no pixels');
      return Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image?.dispose();
    }
  });
  return bytes!;
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);
