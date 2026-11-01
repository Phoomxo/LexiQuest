import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/research_authority_snapshot.dart';
import '../domain/research_operation_authorizer.dart';
import '../domain/research_participation_permit.dart';
import '../domain/research_transport_contracts.dart';

part 'research_transport_codec.dart';

final class HttpResearchTransport
    implements
        ResearchAuthorityGateway,
        ResearchEnrollmentGateway,
        StudyUploadGateway {
  HttpResearchTransport({
    required this.client,
    required Uri baseUri,
    required this.currentBinding,
    required this.loadIdToken,
    this.timeout = const Duration(seconds: 20),
  }) : baseUri = _origin(baseUri) {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 2)) {
      throw ArgumentError('A bounded Research timeout is required');
    }
  }
  final http.Client client;
  final Uri baseUri;
  final ResearchAuthorityBinding? Function() currentBinding;
  final Future<String?> Function(ResearchAuthorityBinding binding) loadIdToken;
  final Duration timeout;
  static const maximumResponseBytes = 1024 * 1024;

  @override
  Future<ServerAttestedResearchAuthorityPacket?> fetchCurrent(
    ResearchAuthorityRefreshRequest request,
  ) async {
    final response = await _request(
      'POST',
      '/v1/research/authority/refresh',
      request.scope.binding,
      () => currentBinding() == request.scope.binding,
      body: {
        'schemaVersion': 1,
        'scope': _scopeJson(request.scope),
        'requestId': request.requestId,
        'clockSessionId': request.clockSessionId,
        'monotonicEpoch': request.monotonicEpoch,
      },
      monotonicElapsed: request.monotonicElapsed,
    );
    return _decode(() {
      final data = response.data;
      _keys(data, const {
        'schemaVersion',
        'scope',
        'requestId',
        'clockSessionId',
        'monotonicEpoch',
        'snapshotRevision',
        'anchorUtc',
        'validUntilUtc',
        'maximumAgeMs',
        'operationDocuments',
        'operationStates',
        'participationDocuments',
        'receipts',
      });
      _version(data);
      final scope = _scope(data['scope']);
      if (scope != request.scope ||
          _code(data['requestId']) != request.requestId ||
          _code(data['clockSessionId']) != request.clockSessionId ||
          _integer(data['monotonicEpoch'], minimum: 0) !=
              request.monotonicEpoch) {
        _invalid();
      }
      final states = <String, ResearchPermitState>{};
      final rawStates = _map(data['operationStates']);
      if (rawStates.length > 3) _invalid();
      for (final entry in rawStates.entries) {
        final value = _map(entry.value);
        _keys(value, const {'currentRevision', 'revoked'});
        states[_code(entry.key)] = ResearchPermitState(
          currentRevision: _integer(value['currentRevision']),
          revoked: _boolean(value['revoked']),
        );
      }
      final sentAt = response.sentAt;
      if (sentAt == null || sentAt < request.startedAtMonotonic) _invalid();
      final anchor = _utc(data['anchorUtc']);
      final until = _utc(data['validUntilUtc']);
      if (!until.isAfter(anchor)) _invalid();
      return ServerAttestedResearchAuthorityPacket(
        scope: scope,
        requestId: request.requestId,
        clockSessionId: request.clockSessionId,
        monotonicEpoch: request.monotonicEpoch,
        snapshotRevision: _integer(data['snapshotRevision']),
        anchorUtc: anchor,
        ageAtObservation: Duration.zero,
        observedAtMonotonic: sentAt,
        validUntilUtc: until,
        maximumAge: Duration(
          milliseconds: _integer(data['maximumAgeMs'], maximum: 3600000),
        ),
        operationDocuments: [
          for (final raw in _list(data['operationDocuments'], 3))
            _documentBytes(raw),
        ],
        operationStates: states,
        participationDocuments: [
          for (final raw in _list(data['participationDocuments'], 64))
            _text(raw, 16384),
        ],
        receipts: [
          for (final raw in _list(data['receipts'], 192)) _receipt(raw),
        ],
      );
    });
  }

  @override
  Future<ResearchEnrollmentContext> loadEnrollment(
    ResearchAuthorityBinding binding, {
    required bool Function() stillCurrent,
  }) async {
    final response = await _request(
      'GET',
      '/v1/research/enrollment-context',
      binding,
      stillCurrent,
    );
    return _decode(() {
      final data = response.data;
      _keys(data, const {
        'schemaVersion',
        'enrollmentId',
        'ownerId',
        'authSubjectId',
        'consentVersion',
        'protocolVersion',
        'scopes',
      });
      _version(data);
      if (_code(data['ownerId']) != binding.ownerId ||
          _code(data['authSubjectId']) != binding.authSubjectId) {
        _invalid();
      }
      final roles = <String, ResearchPermitRequirements>{};
      for (final raw in _list(data['scopes'], 2)) {
        final value = _map(raw);
        _keys(value, const {'role', 'requirements'});
        final role = _code(value['role']);
        if (!const {'motivation', 'assessment'}.contains(role) ||
            roles.containsKey(role)) {
          _invalid();
        }
        roles[role] = _requirements(value['requirements']);
      }
      if (roles.length != 2) _invalid();
      return ResearchEnrollmentContext(
        enrollmentId: _code(data['enrollmentId']),
        ownerId: binding.ownerId,
        authSubjectId: binding.authSubjectId,
        consentVersion: _integer(data['consentVersion']),
        protocolVersion: _code(data['protocolVersion']),
        motivationRequirements: roles['motivation']!,
        assessmentRequirements: roles['assessment']!,
      );
    });
  }

  @override
  Future<ResearchConsentAcknowledgement> decideConsent({
    required ResearchAuthorityBinding binding,
    required ResearchEnrollmentContext enrollment,
    required bool accepted,
    required String requestId,
    required bool Function() stillCurrent,
  }) async {
    if (enrollment.ownerId != binding.ownerId ||
        enrollment.authSubjectId != binding.authSubjectId) {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.ownerChanged,
      );
    }
    final response = await _request(
      'POST',
      '/v1/research/consent',
      binding,
      stillCurrent,
      body: {
        'schemaVersion': 1,
        'enrollmentId': enrollment.enrollmentId,
        'ownerId': binding.ownerId,
        'consentVersion': enrollment.consentVersion,
        'decision': accepted ? 'accepted' : 'withdrawn',
        'requestId': requestId,
      },
    );
    return _decode(() {
      final data = response.data;
      _keys(data, const {
        'schemaVersion',
        'enrollmentId',
        'ownerId',
        'consentVersion',
        'requestId',
        'state',
        'receiptId',
        'revision',
        'decidedAtUtc',
        'withdrawnAtUtc',
      });
      _version(data);
      if (_code(data['ownerId']) != binding.ownerId ||
          _code(data['enrollmentId']) != enrollment.enrollmentId ||
          _integer(data['consentVersion']) != enrollment.consentVersion ||
          _code(data['requestId']) != requestId) {
        _invalid();
      }
      final state = _code(data['state']);
      final decision = data['decidedAtUtc'] == null
          ? null
          : _utc(data['decidedAtUtc']);
      final withdrawal = data['withdrawnAtUtc'] == null
          ? null
          : _utc(data['withdrawnAtUtc']);
      if (!const {'accepted', 'withdrawn'}.contains(state) ||
          (state == 'accepted' && (decision == null || withdrawal != null)) ||
          (state == 'withdrawn' && withdrawal == null) ||
          (decision != null &&
              withdrawal != null &&
              withdrawal.isBefore(decision))) {
        _invalid();
      }
      return ResearchConsentAcknowledgement(
        enrollmentId: enrollment.enrollmentId,
        ownerId: binding.ownerId,
        version: enrollment.consentVersion,
        requestId: requestId,
        accepted: state == 'accepted',
        receiptId: _code(data['receiptId']),
        revision: _integer(data['revision']),
        decidedAtUtc: decision,
        withdrawnAtUtc: withdrawal,
      );
    });
  }

  @override
  Future<StudyUploadReceipt> upload(
    StudyUploadRequest request, {
    required bool Function() stillCurrent,
    required Future<void> Function() revalidateBeforeSubmit,
  }) async {
    final bytes = request.bytes;
    if (bytes.isEmpty ||
        bytes.length > maximumStudyUploadBytes ||
        request.motivationScope.binding != request.assessmentScope.binding) {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.denied,
      );
    }
    final response = await _request(
      'POST',
      '/v1/research/study-archives',
      request.motivationScope.binding,
      stillCurrent,
      body: {
        'schemaVersion': 1,
        'scope': _scopeJson(request.motivationScope),
        'assessmentScope': _scopeJson(request.assessmentScope),
        'cycleKey': _code(request.cycleKey),
        'payloadBase64': base64.encode(bytes),
        'payloadSha256': request.payloadSha256,
      },
      revalidateBeforeSubmit: revalidateBeforeSubmit,
    );
    return _decode(() {
      final data = response.data;
      _keys(data, const {
        'schemaVersion',
        'uploadId',
        'receiptId',
        'payloadSha256',
        'acceptedAtUtc',
      });
      _version(data);
      final uploadId = _hash(data['uploadId']);
      if (data['receiptId'] != 'research-upload:$uploadId' ||
          _hash(data['payloadSha256']) != request.payloadSha256) {
        _invalid();
      }
      return StudyUploadReceipt(
        uploadId: uploadId,
        receiptId: data['receiptId'] as String,
        payloadSha256: request.payloadSha256,
        acceptedAtUtc: _utc(data['acceptedAtUtc']),
      );
    });
  }

  Future<({Map<String, dynamic> data, Duration? sentAt})> _request(
    String method,
    String path,
    ResearchAuthorityBinding binding,
    bool Function() stillCurrent, {
    Map<String, Object?>? body,
    Duration Function()? monotonicElapsed,
    Future<void> Function()? revalidateBeforeSubmit,
  }) async {
    void requireCurrent() {
      if (!stillCurrent() || currentBinding() != binding) {
        throw const ResearchTransportException(
          ResearchTransportFailureCode.ownerChanged,
        );
      }
    }

    requireCurrent();
    final abort = Completer<void>();
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final token = await loadIdToken(binding).timeout(timeout);
      requireCurrent();
      if (token == null ||
          token.isEmpty ||
          token.length > 16384 ||
          token.contains(RegExp(r'[\s\x00-\x1f]'))) {
        throw const ResearchTransportException(
          ResearchTransportFailureCode.accountRequired,
        );
      }
      final request =
          http.AbortableRequest(
              method,
              baseUri.resolve(path),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers['authorization'] = 'Bearer $token'
            ..headers['accept'] = 'application/json'
            ..headers['cache-control'] = 'no-store';
      if (body != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode(body);
        if (request.bodyBytes.length > 768 * 1024) _invalid();
      }
      await revalidateBeforeSubmit?.call();
      requireCurrent();
      final sentAt = monotonicElapsed?.call();
      if (sentAt?.isNegative == true) _invalid();
      final response = await client.send(request).timeout(timeout);
      requireCurrent();
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(timeout)) {
        requireCurrent();
        if (bytes.length + chunk.length > maximumResponseBytes) _invalid();
        bytes.addAll(chunk);
      }
      requireCurrent();
      if (response.statusCode != 200) {
        throw ResearchTransportException(switch (response.statusCode) {
          401 => ResearchTransportFailureCode.accountRequired,
          403 => ResearchTransportFailureCode.denied,
          404 => ResearchTransportFailureCode.notEnrolled,
          409 => ResearchTransportFailureCode.conflict,
          _ => ResearchTransportFailureCode.unavailable,
        });
      }
      if (!(response.headers['content-type'] ?? '').toLowerCase().startsWith(
        'application/json',
      )) {
        _invalid();
      }
      return (data: _map(jsonDecode(utf8.decode(bytes))), sentAt: sentAt);
    } on ResearchTransportException {
      rethrow;
    } on Object {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.unavailable,
      );
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }
}
