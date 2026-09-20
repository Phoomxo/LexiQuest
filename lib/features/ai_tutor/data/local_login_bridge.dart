import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/ai_tutor_contracts.dart';
import '../domain/managed_tutor_transport.dart';

final class DeviceLoginChallenge {
  const DeviceLoginChallenge(this.userCode);
  final String userCode;
  Uri get verificationUrl => Uri.parse('https://auth.openai.com/codex/device');
}

/// Developer-only loopback login client. Never proxies arbitrary provider RPC.
/// The short-lived bridge capability is unrelated to provider credentials.
final class LocalLoginBridge implements ManagedTutorTransport {
  // Named public parameter keeps the capability out of the public object API.
  LocalLoginBridge({required String token, http.Client? client})
    // ignore: prefer_initializing_formals
    : _token = token,
      _client = client ?? http.Client();
  String _token;
  final http.Client _client;
  bool _disposed = false;
  final _network = StreamController<bool>.broadcast(sync: true);
  Stream<bool> get network => _network.stream;
  Future<Map<String, dynamic>> _post(String path) async {
    if (_disposed) throw const AiTutorException(AiFailureCode.cancelled);
    try {
      final response = await _client
          .post(
            Uri.parse('http://127.0.0.1:8765$path'),
            headers: {
              'authorization': 'Bearer $_token',
              'content-type': 'application/json',
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 35));
      if (_disposed) throw const AiTutorException(AiFailureCode.cancelled);
      _network.add(true);
      if (response.statusCode != 200 || response.body.length > 4096) {
        throw const AiTutorException(AiFailureCode.providerUnavailable);
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on AiTutorException {
      rethrow;
    } on TimeoutException {
      throw const AiTutorException(AiFailureCode.timeout);
    } on http.ClientException {
      if (!_disposed) _network.add(false);
      throw const AiTutorException(AiFailureCode.offline);
    } on Object {
      throw const AiTutorException(AiFailureCode.malformedResponse);
    }
  }

  Future<DeviceLoginChallenge> login() async {
    final data = await _post('/login');
    final code = data['userCode'];
    if (data['verificationUrl'] != 'https://auth.openai.com/codex/device' ||
        code is! String ||
        !RegExp(r'^[A-Z0-9-]{4,32}$').hasMatch(code)) {
      throw const AiTutorException(AiFailureCode.malformedResponse);
    }
    return DeviceLoginChallenge(code);
  }

  Future<bool> status() async {
    final data = await _post('/status');
    if (data['authenticated'] is! bool || data['inferenceEnabled'] != false) {
      throw const AiTutorException(AiFailureCode.malformedResponse);
    }
    return data['authenticated'] as bool;
  }

  Future<void> disconnect() async {
    await _post('/disconnect');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _token = '';
    _client.close();
    unawaited(_network.close());
  }

  @override
  Future<void> connect({
    required ManagedTutorBinding binding,
    required AiCancellation cancellation,
  }) async => throw const AiTutorException(AiFailureCode.providerUnavailable);
  @override
  Future<AiGatewayReply> reply({
    required ManagedTutorBinding binding,
    required String learnerMessage,
    required AiCancellation cancellation,
  }) async => throw const AiTutorException(AiFailureCode.providerUnavailable);
}
