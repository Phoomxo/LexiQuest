import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_cooldown.dart';

void main() {
  test('is immediately submittable before it starts', () {
    final cooldown = AccountCooldown();

    expect(cooldown.canSubmit, isTrue);
    expect(cooldown.remaining, Duration.zero);
  });

  test('cooldown counts down from 60 seconds with an injected clock', () {
    var now = DateTime.utc(2026, 7, 29, 12);
    final cooldown = AccountCooldown(
      duration: const Duration(seconds: 60),
      now: () => now,
    )..start();

    expect(cooldown.remaining.inSeconds, 60);
    now = now.add(const Duration(seconds: 59, milliseconds: 999));
    expect(cooldown.remaining, const Duration(milliseconds: 1));
    expect(cooldown.canSubmit, isFalse);

    now = now.add(const Duration(milliseconds: 1));
    expect(cooldown.canSubmit, isTrue);
    expect(cooldown.remaining, Duration.zero);
  });

  test('restarts its expiry when started again', () {
    var now = DateTime.utc(2026, 7, 29, 12);
    final cooldown = AccountCooldown(
      duration: const Duration(seconds: 60),
      now: () => now,
    )..start();
    now = now.add(const Duration(seconds: 30));

    cooldown.start();

    expect(cooldown.remaining.inSeconds, 60);
  });
}
