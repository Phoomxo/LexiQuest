import 'dart:convert';

import '../../gemini/data/secure_gemini_settings_store.dart';
import '../domain/ai_tutor_contracts.dart';
import 'ai_credential_version_index.dart';

typedef ActiveAiTutorOwnerIdProvider = Future<String> Function();

/// Stores the single active BYOK profile as one secure value so provider,
/// model, consent, endpoint and key cannot be partially switched.
final class SecureAiTutorSettingsStore implements AiTutorSettingsStore {
  SecureAiTutorSettingsStore(
    this._storage, {
    required this.activeOwnerId,
    AiCredentialVersionIndex? versionIndex,
  }) : _versionIndex = versionIndex ?? VolatileAiCredentialVersionIndex();

  factory SecureAiTutorSettingsStore.production({
    required ActiveAiTutorOwnerIdProvider activeOwnerId,
    required AiCredentialVersionIndex versionIndex,
  }) => SecureAiTutorSettingsStore(
    FlutterSecureValueStore(),
    activeOwnerId: activeOwnerId,
    versionIndex: versionIndex,
  );

  final SecureValueStore _storage;
  final AiCredentialVersionIndex _versionIndex;
  final ActiveAiTutorOwnerIdProvider activeOwnerId;

  static const _profile = 'ai_active_profile_v2';
  static const _apiKey = 'ai_api_key_v2';
  static const _providerConsent = 'ai_provider_consent_v2';
  static const _summaryConsent = 'ai_learning_summary_consent_v2';
  static const _providerId = 'ai_provider_id_v2';
  static const _model = 'ai_model_v2';
  static const _customBaseUrl = 'ai_custom_base_url_v2';
  static const _scopedKeys = <String>[
    _profile,
    _apiKey,
    _providerConsent,
    _summaryConsent,
    _providerId,
    _model,
    _customBaseUrl,
  ];
  static const _legacyKeys = <String>[
    'ai_active_profile_v1',
    'ai_api_key',
    'gemini_api_key',
    'ai_provider_consent',
    'ai_learning_summary_consent',
    'ai_provider_id',
    'ai_model',
    'ai_custom_base_url',
  ];

  bool _legacyDiscarded = false;

  @override
  Future<AiTutorCredential?> readCredential() async {
    return readCredentialForOwner(await resolveActiveOwnerId());
  }

  @override
  Future<String> resolveActiveOwnerId() async {
    return _requireOwnerId(await activeOwnerId());
  }

  @override
  Future<AiTutorCredential?> readCredentialForOwner(String ownerId) async {
    await _discardUnscopedLegacyValues();
    final ownerToken = _ownerToken(_requireOwnerId(ownerId));
    final pointer = await _readPointer(ownerToken);
    if (pointer?.isDeleted == true) return null;
    final version = pointer?.version;
    final raw = version != null
        ? await _read(_versionedProfileKey(ownerToken, version))
        : await _read('$_profile:$ownerToken');
    if (raw == null) return null;
    return _decodeCredential(raw);
  }

  AiTutorCredential _decodeCredential(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> || json['version'] != 1) {
        throw const FormatException();
      }
      final key = json['key'];
      final providerRaw = json['providerId'];
      final model = json['model'];
      final provider = AiProviderId.values
          .where((value) => value.name == providerRaw)
          .firstOrNull;
      if (key is! String ||
          key.trim().isEmpty ||
          provider == null ||
          model is! String ||
          json['providerConsent'] is! bool ||
          json['shareLearningSummary'] is! bool) {
        throw const FormatException();
      }
      final customBaseUrl = json['customBaseUrl'];
      return AiTutorCredential(
        key: key,
        providerId: provider,
        model: model,
        providerConsent: json['providerConsent'] as bool,
        shareLearningSummary: json['shareLearningSummary'] as bool,
        customBaseUrl: customBaseUrl is String ? customBaseUrl : null,
      );
    } on Object {
      throw const AiTutorException(AiFailureCode.secureStorage);
    }
  }

  @override
  Future<void> writeCredential(AiTutorCredential credential) async {
    await writeCredentialForOwner(await resolveActiveOwnerId(), credential);
  }

  @override
  Future<void> writeCredentialForOwner(
    String ownerId,
    AiTutorCredential credential,
  ) async {
    await _discardUnscopedLegacyValues();
    await _writeForOwner(
      _profile,
      _requireOwnerId(ownerId),
      _encodeCredential(credential),
    );
  }

  String _encodeCredential(AiTutorCredential credential) {
    final key = credential.key.trim();
    final model = credential.model.trim();
    if (key.isEmpty || key.length > 512) {
      throw const AiTutorException(AiFailureCode.invalidKey);
    }
    if (model.isEmpty || model.length > 200) {
      throw const AiTutorException(AiFailureCode.missingModel);
    }
    String? customBaseUrl;
    if (credential.providerId == AiProviderId.customOpenAi) {
      final raw = credential.customBaseUrl;
      if (raw == null || raw.trim().isEmpty) {
        throw const AiTutorException(AiFailureCode.unsafeEndpoint);
      }
      customBaseUrl = parseAndValidateCustomAiBaseUri(raw).toString();
    }
    return jsonEncode({
      'version': 1,
      'key': key,
      'providerId': credential.providerId.name,
      'model': model,
      'providerConsent': credential.providerConsent,
      'shareLearningSummary':
          credential.providerConsent && credential.shareLearningSummary,
      'customBaseUrl': ?customBaseUrl,
    });
  }

  @override
  Future<void> replaceCredentialForOwnerFenced(
    String ownerId,
    AiTutorCredential? credential, {
    required String operationVersion,
    required Future<bool> Function() leaseIsOwned,
    required DateTime Function() nowUtc,
  }) async {
    await _discardUnscopedLegacyValues();
    final canonicalOwner = _requireOwnerId(ownerId);
    final ownerToken = _ownerToken(canonicalOwner);
    final leaseToken = operationVersion.trim();
    final legacyKey = '$_profile:$ownerToken';
    final legacyExists = await _read(legacyKey) != null;
    if (!await _owned(leaseIsOwned)) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    final kind = credential == null
        ? AiCredentialMutationKind.delete
        : AiCredentialMutationKind.replace;
    late AiCredentialPreparedMutation prepared;
    try {
      prepared = await _versionIndex.prepareMutation(
        ownerToken: ownerToken,
        operationVersion: operationVersion,
        kind: kind,
        legacyBlobExists: legacyExists,
        leaseToken: leaseToken,
        nowUtc: _requiredUtc(nowUtc()),
      );
    } on Object {
      if (!await _owned(leaseIsOwned)) {
        throw const AiTutorException(AiFailureCode.cancelled);
      }
      throw const AiTutorException(AiFailureCode.localPersistence);
    }

    final previousPointer = prepared.expectedPointer;
    final obsoleteBlobVersion = prepared.obsoleteBlobVersion;
    final operationBlobKey = _versionedProfileKey(ownerToken, operationVersion);

    if (credential != null) {
      final encoded = _encodeCredential(credential);
      final existing = await _read(operationBlobKey);
      if (existing == null) {
        await _write(operationBlobKey, encoded);
      } else if (existing != encoded) {
        throw const AiTutorException(AiFailureCode.secureStorage);
      }
    } else {
      if (!await _owned(leaseIsOwned)) {
        throw const AiTutorException(AiFailureCode.cancelled);
      }
      // Delete is intentionally privacy-first. If the gate is lost during
      // platform erasure, reads fail closed on a missing immutable blob and
      // the durable prepared intent is tombstoned by gated recovery.
      await _eraseDeletionSecrets(
        ownerToken: ownerToken,
        obsoleteBlobVersion: obsoleteBlobVersion,
      );
    }

    if (!await _owned(leaseIsOwned)) {
      if (credential != null) await _delete(operationBlobKey);
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    var pointerCommitted = false;
    try {
      await _versionIndex.commitMutation(
        ownerToken: ownerToken,
        operationVersion: operationVersion,
        kind: kind,
        expectedPointer: previousPointer,
        leaseToken: leaseToken,
        nowUtc: _requiredUtc(nowUtc()),
      );
      pointerCommitted = true;
    } on Object {
      final current = await _readPointer(ownerToken);
      pointerCommitted = credential != null
          ? current?.version == operationVersion
          : current?.source ==
                AiCredentialPointer.deleted(operationVersion).source;
      if (!pointerCommitted &&
          credential != null &&
          current?.version != operationVersion) {
        await _delete(operationBlobKey);
      }
      if (pointerCommitted) {
        // The transaction committed but its completion signal was lost.
      } else if (!await _owned(leaseIsOwned)) {
        throw const AiTutorException(AiFailureCode.cancelled);
      } else {
        throw const AiTutorException(AiFailureCode.localPersistence);
      }
    }

    // The pointer commit is the irreversible boundary. Cleanup is best effort;
    // a retained intent makes it retryable on the next gated AI operation.
    try {
      if (kind == AiCredentialMutationKind.replace) {
        await _cleanupObsoleteBlobIfNonCurrent(
          ownerToken: ownerToken,
          obsoleteBlobVersion: obsoleteBlobVersion,
        );
      }
      if (await _owned(leaseIsOwned)) {
        await _versionIndex.completeMutation(
          ownerToken: ownerToken,
          operationVersion: operationVersion,
          leaseToken: leaseToken,
          nowUtc: _requiredUtc(nowUtc()),
        );
      }
    } on Object {
      // Pointer is already committed and reads are fail-closed. Recovery owns
      // the non-current cleanup intent; do not discard the successful change.
    }
  }

  @override
  Future<int> recoverCredentialMutations({
    required String leaseToken,
    required DateTime Function() nowUtc,
  }) async {
    late List<AiCredentialMutationIntent> intents;
    try {
      intents = await _versionIndex.pendingMutations(
        leaseToken: leaseToken,
        nowUtc: _requiredUtc(nowUtc()),
      );
    } on Object {
      throw const AiTutorException(AiFailureCode.localPersistence);
    }
    var completed = 0;
    for (final intent in intents) {
      try {
        var current = await _readPointer(intent.ownerToken);
        if (intent.kind == AiCredentialMutationKind.delete &&
            !intent.committed &&
            current?.source == intent.expectedPointer?.source) {
          current = await _readPointer(intent.ownerToken);
          if (current?.source != intent.expectedPointer?.source) continue;
          await _eraseDeletionSecrets(
            ownerToken: intent.ownerToken,
            obsoleteBlobVersion: intent.obsoleteBlobVersion,
          );
          await _versionIndex.commitMutation(
            ownerToken: intent.ownerToken,
            operationVersion: intent.operationVersion,
            kind: intent.kind,
            expectedPointer: intent.expectedPointer,
            leaseToken: leaseToken,
            nowUtc: _requiredUtc(nowUtc()),
          );
          current = await _readPointer(intent.ownerToken);
        }
        if (intent.kind == AiCredentialMutationKind.replace) {
          if (intent.committed) {
            await _cleanupObsoleteBlobIfNonCurrent(
              ownerToken: intent.ownerToken,
              obsoleteBlobVersion: intent.obsoleteBlobVersion,
            );
            if (current?.version != intent.operationVersion) {
              await _delete(
                _versionedProfileKey(
                  intent.ownerToken,
                  intent.operationVersion,
                ),
              );
            }
          } else if (current?.version != intent.operationVersion) {
            current = await _readPointer(intent.ownerToken);
            if (current?.version != intent.operationVersion) {
              await _delete(
                _versionedProfileKey(
                  intent.ownerToken,
                  intent.operationVersion,
                ),
              );
            }
          }
        } else if (current?.source ==
            AiCredentialPointer.deleted(intent.operationVersion).source) {
          await _eraseDeletionSecrets(
            ownerToken: intent.ownerToken,
            obsoleteBlobVersion: intent.obsoleteBlobVersion,
          );
        }
        await _versionIndex.completeMutation(
          ownerToken: intent.ownerToken,
          operationVersion: intent.operationVersion,
          leaseToken: leaseToken,
          nowUtc: _requiredUtc(nowUtc()),
        );
        completed += 1;
      } on Object {
        // Keep the intent durable for a later gated recovery attempt.
      }
    }
    return completed;
  }

  @override
  Future<void> eraseOwnerCredentialsFenced(
    String ownerId, {
    required String leaseToken,
    required Future<bool> Function() leaseIsOwned,
    required DateTime Function() nowUtc,
  }) async {
    await _discardUnscopedLegacyValues();
    final ownerToken = _ownerToken(_requireOwnerId(ownerId));
    if (!await _owned(leaseIsOwned)) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    late List<AiCredentialMutationIntent> intents;
    try {
      intents = (await _versionIndex.pendingMutations(
        leaseToken: leaseToken,
        nowUtc: _requiredUtc(nowUtc()),
      )).where((intent) => intent.ownerToken == ownerToken).toList();
    } on Object {
      throw const AiTutorException(AiFailureCode.localPersistence);
    }
    final pointer = await _readPointer(ownerToken);
    final versions = <String>{
      ?pointer?.version,
      for (final intent in intents)
        if (intent.kind == AiCredentialMutationKind.replace)
          intent.operationVersion,
      for (final intent in intents)
        if (intent.obsoleteBlobVersion case final version?)
          if (version != 'legacy') version,
    };
    for (final version in versions) {
      if (!await _owned(leaseIsOwned)) {
        throw const AiTutorException(AiFailureCode.cancelled);
      }
      await _delete(_versionedProfileKey(ownerToken, version));
    }
    await _deleteLegacyScopedValues(ownerToken);
    if (!await _owned(leaseIsOwned)) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    try {
      await _versionIndex.eraseOwnerMetadata(
        ownerToken: ownerToken,
        leaseToken: leaseToken,
        nowUtc: _requiredUtc(nowUtc()),
      );
    } on Object {
      if (!await _owned(leaseIsOwned)) {
        throw const AiTutorException(AiFailureCode.cancelled);
      }
      throw const AiTutorException(AiFailureCode.localPersistence);
    }
  }

  @override
  Future<void> deleteCredential() async {
    await deleteCredentialForOwner(await resolveActiveOwnerId());
  }

  @override
  Future<void> deleteCredentialForOwner(String ownerId) async {
    await _discardUnscopedLegacyValues();
    final ownerToken = _ownerToken(_requireOwnerId(ownerId));
    final pointer = await _readPointer(ownerToken);
    if (pointer?.version case final version?) {
      await _delete(_versionedProfileKey(ownerToken, version));
    }
    await _deleteLegacyScopedValues(ownerToken);
  }

  @override
  Future<String?> readKey() async => (await readCredential())?.key;

  @override
  Future<void> writeKey(String key) async {
    final ownerId = await resolveActiveOwnerId();
    final current = await readCredentialForOwner(ownerId);
    if (current != null && current.model.isNotEmpty) {
      await writeCredentialForOwner(ownerId, current.copyWith(key: key));
      return;
    }
    await _writeForOwner(_apiKey, ownerId, key);
  }

  @override
  Future<void> deleteKey() => deleteCredential();

  @override
  Future<bool> readProviderConsent() async {
    final ownerId = await resolveActiveOwnerId();
    return (await readCredentialForOwner(ownerId))?.providerConsent ??
        await _readForOwner(_providerConsent, ownerId) == 'true';
  }

  @override
  Future<void> writeProviderConsent(bool value) async {
    final ownerId = await resolveActiveOwnerId();
    final current = await readCredentialForOwner(ownerId);
    if (current != null && current.model.isNotEmpty) {
      await writeCredentialForOwner(
        ownerId,
        current.copyWith(
          providerConsent: value,
          shareLearningSummary: value && current.shareLearningSummary,
        ),
      );
      return;
    }
    await _writeForOwner(_providerConsent, ownerId, value.toString());
  }

  @override
  Future<bool> readLearningSummaryConsent() async {
    final ownerId = await resolveActiveOwnerId();
    return (await readCredentialForOwner(ownerId))?.shareLearningSummary ??
        await _readForOwner(_summaryConsent, ownerId) == 'true';
  }

  @override
  Future<void> writeLearningSummaryConsent(bool value) async {
    final ownerId = await resolveActiveOwnerId();
    final current = await readCredentialForOwner(ownerId);
    if (current != null && current.model.isNotEmpty) {
      await writeCredentialForOwner(
        ownerId,
        current.copyWith(shareLearningSummary: value),
      );
      return;
    }
    await _writeForOwner(_summaryConsent, ownerId, value.toString());
  }

  @override
  Future<AiProviderId> readProviderId() async {
    final ownerId = await resolveActiveOwnerId();
    final credential = await readCredentialForOwner(ownerId);
    if (credential != null) return credential.providerId;
    final raw = await _readForOwner(_providerId, ownerId);
    return AiProviderId.values
            .where((provider) => provider.name == raw)
            .firstOrNull ??
        AiProviderId.gemini;
  }

  @override
  Future<void> writeProviderId(AiProviderId provider) async {
    final ownerId = await resolveActiveOwnerId();
    final current = await readCredentialForOwner(ownerId);
    if (current != null && current.model.isNotEmpty) {
      await writeCredentialForOwner(
        ownerId,
        current.copyWith(providerId: provider),
      );
      return;
    }
    await _writeForOwner(_providerId, ownerId, provider.name);
  }

  @override
  Future<String?> readModel() async {
    final ownerId = await resolveActiveOwnerId();
    return (await readCredentialForOwner(ownerId))?.model.nullIfEmpty ??
        await _readForOwner(_model, ownerId);
  }

  @override
  Future<void> writeModel(String model) async {
    final ownerId = await resolveActiveOwnerId();
    final current = await readCredentialForOwner(ownerId);
    if (current != null) {
      await writeCredentialForOwner(ownerId, current.copyWith(model: model));
      return;
    }
    await _writeForOwner(_model, ownerId, model);
  }

  @override
  Future<String?> readCustomBaseUrl() async {
    final ownerId = await resolveActiveOwnerId();
    return (await readCredentialForOwner(ownerId))?.customBaseUrl ??
        await _readForOwner(_customBaseUrl, ownerId);
  }

  @override
  Future<void> writeCustomBaseUrl(String url) async {
    final ownerId = await resolveActiveOwnerId();
    final current = await readCredentialForOwner(ownerId);
    if (current != null && current.providerId == AiProviderId.customOpenAi) {
      await writeCredentialForOwner(
        ownerId,
        current.copyWith(customBaseUrl: url),
      );
      return;
    }
    await _writeForOwner(_customBaseUrl, ownerId, url);
  }

  Future<void> _discardUnscopedLegacyValues() async {
    if (_legacyDiscarded) return;
    for (final key in _legacyKeys) {
      await _delete(key);
    }
    _legacyDiscarded = true;
  }

  Future<String?> _readForOwner(String baseKey, String ownerId) async {
    return _read(_scopedKey(baseKey, ownerId));
  }

  Future<void> _writeForOwner(
    String baseKey,
    String ownerId,
    String value,
  ) async {
    await _write(_scopedKey(baseKey, ownerId), value);
  }

  String _requireOwnerId(String value) {
    final ownerId = value.trim();
    if (ownerId.isEmpty) {
      throw StateError('Active owner id must not be empty.');
    }
    return ownerId;
  }

  String _scopedKey(String baseKey, String ownerId) {
    return '$baseKey:${_ownerToken(_requireOwnerId(ownerId))}';
  }

  String _ownerToken(String ownerId) =>
      base64Url.encode(utf8.encode(ownerId)).replaceAll('=', '');

  String _versionedProfileKey(String ownerToken, String version) =>
      '$_profile:$ownerToken:version:${version.trim()}';

  Future<AiCredentialPointer?> _readPointer(String ownerToken) async {
    try {
      return await _versionIndex.readPointer(ownerToken);
    } on Object {
      throw const AiTutorException(AiFailureCode.localPersistence);
    }
  }

  Future<void> _cleanupObsoleteBlobIfNonCurrent({
    required String ownerToken,
    required String? obsoleteBlobVersion,
  }) async {
    if (obsoleteBlobVersion == null) return;
    final current = await _readPointer(ownerToken);
    if (current?.version == obsoleteBlobVersion) {
      throw StateError('Refusing to delete the active credential version.');
    }
    if (obsoleteBlobVersion == 'legacy') {
      await _deleteLegacyScopedValues(ownerToken);
      return;
    }
    await _delete(_versionedProfileKey(ownerToken, obsoleteBlobVersion));
    await _deleteLegacyGranularValues(ownerToken);
  }

  Future<void> _eraseDeletionSecrets({
    required String ownerToken,
    required String? obsoleteBlobVersion,
  }) async {
    if (obsoleteBlobVersion != null && obsoleteBlobVersion != 'legacy') {
      await _delete(_versionedProfileKey(ownerToken, obsoleteBlobVersion));
    }
    await _deleteLegacyScopedValues(ownerToken);
  }

  Future<void> _deleteLegacyScopedValues(String ownerToken) async {
    for (final baseKey in _scopedKeys) {
      await _delete('$baseKey:$ownerToken');
    }
  }

  Future<void> _deleteLegacyGranularValues(String ownerToken) async {
    for (final baseKey in _scopedKeys.where((key) => key != _profile)) {
      await _delete('$baseKey:$ownerToken');
    }
  }

  Future<bool> _owned(Future<bool> Function() check) async {
    try {
      return await check();
    } on Object {
      return false;
    }
  }

  DateTime _requiredUtc(DateTime value) {
    if (!value.isUtc) {
      throw const AiTutorException(AiFailureCode.localPersistence);
    }
    return value;
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key);
    } on Object {
      throw const AiTutorException(AiFailureCode.secureStorage);
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key, value);
    } on Object {
      throw const AiTutorException(AiFailureCode.secureStorage);
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key);
    } on Object {
      throw const AiTutorException(AiFailureCode.secureStorage);
    }
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
