import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/motivation/presentation/achievement_share_composer.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final colors = ColorScheme.fromSeed(seedColor: Colors.indigo);
  AchievementEvidence earned(
    String source,
    DateTime at, {
    String id = 'first_session',
    int version = 1,
  }) => AchievementEvidence(
    id: id,
    definitionVersion: version,
    sourceEventId: source,
    unlockedAtUtc: at,
  );

  test(
    'real PNG contains the same public image for different private event identities',
    () async {
      final first = earned(
        'synthetic-owner-a-private-answer',
        DateTime.utc(2026, 10, 28),
      );
      final second = earned(
        'synthetic-owner-b-private-research',
        DateTime.utc(2026, 10, 28),
      );
      final a = await renderAchievementCard(
        first,
        includeDate: false,
        colors: colors,
      );
      final b = await renderAchievementCard(
        second,
        includeDate: false,
        colors: colors,
      );
      final otherDate = await renderAchievementCard(
        earned('synthetic-other', DateTime.utc(2025, 1, 1)),
        includeDate: false,
        colors: colors,
      );
      expect(a, orderedEquals(b));
      expect(a, orderedEquals(otherDate));
      expect(a.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final codec = await ui.instantiateImageCodec(a);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 900);
      expect(frame.image.height, 640);
      frame.image.dispose();
      codec.dispose();
      final withDate = await renderAchievementCard(
        first,
        includeDate: true,
        colors: colors,
      );
      expect(withDate, isNot(orderedEquals(a)));
    },
  );

  test(
    'unknown definitions and malformed evidence cannot become share cards',
    () {
      final date = DateTime.utc(2026, 10, 28);
      expect(shareableAchievementTitle(earned('', date)), isNull);
      expect(
        shareableAchievementTitle(earned('source', date, version: 2)),
        isNull,
      );
      expect(
        shareableAchievementTitle(
          earned('source', date, id: 'private_unknown'),
        ),
        isNull,
      );
      expect(
        shareableAchievementTitle(earned('source', DateTime(2026, 10, 28))),
        isNull,
      );
      expect(
        shareableAchievementTitle(earned('source', date)),
        'เรียนจบรอบแรก',
      );
    },
  );
}
