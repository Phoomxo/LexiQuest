import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_settings_store.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/gemini/data/secure_gemini_settings_store.dart';

void main() {
  test(
    'profiles and consent are isolated by the current active owner',
    () async {
      final values = <String, String>{};
      var activeOwner = 'owner-a';
      final store = SecureAiTutorSettingsStore(
        _MemorySecureStore(values),
        activeOwnerId: () async => activeOwner,
      );
      await store.writeCredential(_credential('key-a', 'model-a'));

      activeOwner = 'owner-b';
      expect(await store.readCredential(), isNull);
      await store.writeCredential(_credential('key-b', 'model-b'));

      activeOwner = 'owner-a';
      expect((await store.readCredential())?.key, 'key-a');
      activeOwner = 'owner-b';
      expect((await store.readCredential())?.key, 'key-b');
    },
  );

  test('unattributable device-global legacy profile is discarded', () async {
    final values = <String, String>{
      'ai_active_profile_v1': jsonEncode({
        'version': 1,
        'key': 'legacy-secret',
        'providerId': 'gemini',
        'model': 'legacy-model',
        'providerConsent': true,
        'shareLearningSummary': true,
      }),
    };
    final store = SecureAiTutorSettingsStore(
      _MemorySecureStore(values),
      activeOwnerId: () async => 'owner-a',
    );

    expect(await store.readCredential(), isNull);
    expect(values, isNot(contains('ai_active_profile_v1')));
    expect(values.values.join(), isNot(contains('legacy-secret')));
  });

  test(
    'explicit owner deletion removes every scoped value only for that owner',
    () async {
      final values = <String, String>{};
      var activeOwner = 'owner-a';
      final store = SecureAiTutorSettingsStore(
        _MemorySecureStore(values),
        activeOwnerId: () async => activeOwner,
      );
      await store.writeCredential(_credential('key-a', 'model-a'));
      await store.writeProviderConsent(true);
      activeOwner = 'owner-b';
      await store.writeCredential(_credential('key-b', 'model-b'));

      await store.deleteCredentialForOwner('owner-a');

      expect(await store.readCredentialForOwner('owner-a'), isNull);
      expect((await store.readCredentialForOwner('owner-b'))?.key, 'key-b');
      expect(values.values.join(), isNot(contains('key-a')));
    },
  );
}

AiTutorCredential _credential(String key, String model) => AiTutorCredential(
  key: key,
  providerId: AiProviderId.gemini,
  model: model,
  providerConsent: true,
  shareLearningSummary: false,
);

final class _MemorySecureStore implements SecureValueStore {
  _MemorySecureStore(this.values);

  final Map<String, String> values;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
