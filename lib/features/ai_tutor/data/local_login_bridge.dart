import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../domain/ai_tutor_contracts.dart';
import '../domain/managed_tutor_transport.dart';
import '../application/menu_action_registry.dart';

final class DeviceLoginChallenge {
  const DeviceLoginChallenge(this.userCode);
  final String userCode;
  Uri get verificationUrl => Uri.parse('https://auth.openai.com/codex/device');
}

/// Developer-only loopback login client. Never proxies arbitrary provider RPC.
/// The short-lived bridge capability is unrelated to provider credentials.
final class LocalLoginBridge implements ManagedTutorTransport {
  // Named public parameter keeps the capability out of the public object API.
  LocalLoginBridge({required String token, http.Client? client, this.reloadPairing})
    // ignore: prefer_initializing_formals
    : _token = token,
      _client = client ?? http.Client();
  String _token;
  final Future<String?> Function()? reloadPairing;
  final http.Client _client;
  bool _disposed = false;
  bool inferenceEnabled = false;
  ManagedTutorBinding? _connectedBinding;
  Map<String, dynamic>? selectedWord;
  MenuActionRegistry? menuActions;
  List<Map<String, dynamic>> toolResults = const [];
  final _network = StreamController<bool>.broadcast(sync: true);
  Stream<bool> get network => _network.stream;
  Future<Map<String, dynamic>> _post(
    String path, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (_disposed) throw const AiTutorException(AiFailureCode.cancelled);
    try {
      final response = await _client
          .post(
            Uri.parse('http://127.0.0.1:8765$path'),
            headers: {
              'authorization': 'Bearer $_token',
              'content-type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: path == '/reply' ? 105 : 35));
      if (_disposed) throw const AiTutorException(AiFailureCode.cancelled);
      _network.add(true);
      if (response.statusCode != 200 || response.body.length > 64000) {
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
    if (_disposed) throw const AiTutorException(AiFailureCode.cancelled);
    final reload = reloadPairing;
    if (reload != null) {
      _connectedBinding = null;
      inferenceEnabled = false;
      toolResults = const [];
      menuActions?.invalidateSession(preserveContext: true);
      _token = '';
      final String? fresh;
      try {
        fresh = await reload();
      } on Object {
        throw const AiTutorException(AiFailureCode.providerUnavailable);
      }
      if (_disposed) throw const AiTutorException(AiFailureCode.cancelled);
      if (fresh == null || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(fresh)) {
        throw const AiTutorException(AiFailureCode.providerUnavailable);
      }
      _token = fresh;
    }
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
    if (data['authenticated'] is! bool || data['inferenceEnabled'] is! bool) {
      throw const AiTutorException(AiFailureCode.malformedResponse);
    }
    inferenceEnabled = data['inferenceEnabled'] == true;
    return data['authenticated'] as bool;
  }

  Future<void> disconnect() async {
    _connectedBinding = null;
    menuActions?.invalidateSession(preserveContext: true);
    inferenceEnabled = false;
    toolResults = const [];
    await _post('/disconnect');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connectedBinding = null;
    menuActions?.invalidateSession(preserveContext: true);
    menuActions = null;
    selectedWord = null;
    toolResults = const [];
    _token = '';
    _client.close();
    unawaited(_network.close());
  }

  @override
  Future<void> connect({
    required ManagedTutorBinding binding,
    required AiCancellation cancellation,
  }) async {
    _connectedBinding = null;
    menuActions?.invalidateSession(preserveContext: true);
    if (cancellation.isCancelled) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    if (!await status() || !inferenceEnabled) {
      throw const AiTutorException(AiFailureCode.providerUnavailable);
    }
    if (cancellation.isCancelled) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    toolResults = const [];
    final result = await _post('/connect', {
      'binding': _bindingJson(binding),
      'word': selectedWord,
    });
    if (cancellation.isCancelled) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    if (result['ready'] != true) {
      throw const AiTutorException(AiFailureCode.providerUnavailable);
    }
    _connectedBinding = binding;
  }

  @override
  Future<AiGatewayReply> reply({
    required ManagedTutorBinding binding,
    required String learnerMessage,
    required AiCancellation cancellation,
  }) async {
    if (cancellation.isCancelled) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    final connected = _connectedBinding;
    if (!inferenceEnabled ||
        connected == null ||
        connected.ownerId != binding.ownerId ||
        connected.accountId != binding.accountId ||
        connected.generation != binding.generation) {
      throw const AiTutorException(AiFailureCode.providerUnavailable);
    }
    toolResults = const [];
    var finished = false;
    final requestId = const Uuid().v4();
    Future<void> serviceMenus() async {
      // Poll only during an explicit learner turn, never in the background.
      while (!finished && !cancellation.isCancelled && !_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (finished || cancellation.isCancelled || _disposed) return;
        try {
          final envelope = await _post('/menu/next', {
            'binding': _bindingJson(binding),
            'requestId': requestId,
          });
          if (finished ||
              cancellation.isCancelled ||
              _disposed ||
              !identical(_connectedBinding, connected)) {
            return;
          }
          final request = envelope['request'];
          if (request == null) continue;
          if (request is! Map<String, dynamic> ||
              request['requestId'] is! String ||
              !RegExp(
                r'^[A-Za-z0-9_-]{1,80}$',
              ).hasMatch(request['requestId'] as String) ||
              request['arguments'] is! Map<String, dynamic>) {
            return;
          }
          final arguments = request['arguments'] as Map<String, dynamic>;
          final registry = menuActions;
          Map<String, Object?> result = {'status': 'unavailable'};
          if (registry != null &&
              request['name'] == 'list_menu_actions' &&
              arguments.isEmpty) {
            result = {'status': 'available', ...registry.snapshot()};
          } else if (registry != null &&
              request['name'] == 'execute_menu_action' &&
              arguments.keys.every(
                (key) => const ['id', 'revision', 'values'].contains(key),
              ) &&
              (arguments['values'] == null ||
                  arguments['values'] is Map &&
                      (arguments['values'] as Map).entries.every(
                        (e) => e.key is String && e.value is String,
                      )) &&
              arguments['id'] is String &&
              arguments['revision'] is int) {
            result = await registry.execute(
              id: arguments['id'] as String,
              owner: binding.ownerId,
              revision: arguments['revision'] as int,
              requestId: request['requestId'] as String,
              values: Map<String, String>.from(
                arguments['values'] as Map? ?? const {},
              ),
            );
          }
          if (finished || cancellation.isCancelled || _disposed) return;
          await _post('/menu/result', {
            'binding': _bindingJson(binding),
            'requestId': requestId,
            'response': {'requestId': request['requestId'], 'result': result},
          });
        } on Object {
          // The provider reply/cancel path remains authoritative. A closed turn
          // rejects a late poll; never retry a possibly applied app command.
          return;
        }
      }
    }

    if (menuActions != null) unawaited(serviceMenus());
    unawaited(
      cancellation.whenCancelled.then((_) async {
        if (!finished && !_disposed) {
          menuActions?.invalidateSession(preserveContext: true);
          try {
            await _post('/cancel');
          } on Object {
            /* Local cancellation still completes. */
          }
        }
      }),
    );
    try {
      final result = await _post('/reply', {
        'binding': _bindingJson(binding),
        'message': learnerMessage,
        'requestId': requestId,
      });
      if (cancellation.isCancelled) {
        throw const AiTutorException(AiFailureCode.cancelled);
      }
      final text = result['text'];
      final receipts = result['tools'];
      if (text is! String ||
          text.trim().isEmpty ||
          text.length > 16000 ||
          receipts is! List ||
          receipts.length > 8 ||
          receipts.any(
            (r) =>
                r is! Map<String, dynamic> ||
                !{
                  'read_selected_word',
                  'create_practice_draft',
                  'list_menu_actions',
                  'execute_menu_action',
                }.contains(r['name']) ||
                !{'completed', 'failed'}.contains(r['status']) ||
                r['data'] is! Map<String, dynamic>,
          )) {
        throw const AiTutorException(AiFailureCode.malformedResponse);
      }
      toolResults = List.unmodifiable(receipts.cast<Map<String, dynamic>>());
      return AiGatewayReply(text: text);
    } finally {
      finished = true;
    }
  }

  static Map<String, dynamic> _bindingJson(ManagedTutorBinding binding) => {
    'ownerId': binding.ownerId,
    'accountId': binding.accountId,
    'generation': binding.generation,
  };
}
