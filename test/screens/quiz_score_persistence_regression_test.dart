import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production has no client score or reward writers outside the disabled '
      'shop debit allowlist', () {
    final forbiddenWriters = <String>[];
    final scoreOrRewardField = RegExp(
      r'''['"](points|totalPoints|score|coins|coinReward|rewardXp|rewardCoins|balance|xp)['"]\s*:''',
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!source.contains('cloud_firestore')) continue;

      final relativePath = entity.path.replaceAll(r'\', '/');
      final lines = source.split('\n');
      for (var index = 0; index < lines.length; index++) {
        final normalized = lines[index].trim();
        if (!scoreOrRewardField.hasMatch(normalized) &&
            !normalized.contains('FieldValue.increment')) {
          continue;
        }

        final isLegacyZeroInitialization =
            relativePath == 'lib/services/user_service.dart' &&
            normalized == "'points': 0,";
        final isDefaultDisabledPurchaseDebit =
            relativePath == 'lib/screens/shop_page.dart' &&
            normalized == "'totalPoints': FieldValue.increment(-productPrice),";

        if (!isLegacyZeroInitialization && !isDefaultDisabledPurchaseDebit) {
          forbiddenWriters.add('$relativePath:${index + 1}: $normalized');
        }
      }
    }

    final policySource = File(
      'lib/config/remote_economy_policy.dart',
    ).readAsStringSync();
    final shopSource = File('lib/screens/shop_page.dart').readAsStringSync();

    expect(forbiddenWriters, isEmpty);
    expect(policySource, contains('this.shopAndPurchasesEnabled = false'));
    expect(
      shopSource,
      contains('!_policyFor(context).shopAndPurchasesEnabled'),
    );
  });
}
