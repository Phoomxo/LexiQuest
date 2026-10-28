import 'dart:async';
import 'package:flutter/foundation.dart';
import '../domain/ai_tutor_contracts.dart';
import '../domain/managed_tutor_transport.dart';
import 'owner_operation_coordinator.dart';

enum ManagedTutorState {
  disconnected,
  pending,
  ready,
  replying,
  cancelled,
  expired,
  offline,
  quotaExhausted,
  providerUnavailable,
}

/// In-memory managed-session foundation. Not registered in production.
/// The host must call ownerChanged synchronously on auth/account transitions,
/// and owns the injected transport's lifetime and any actual provider revoke.
final class ManagedTutorController extends ChangeNotifier {
  ManagedTutorController({
    required this.transport,
    required this.ownerCoordinator,
    this.operationTimeout = const Duration(seconds: 30),
  }) {
    if (operationTimeout <= Duration.zero) {
      throw ArgumentError('Operation timeout must be positive');
    }
  }
  final ManagedTutorTransport transport;
  final OwnerOperationCoordinator ownerCoordinator;
  final Duration operationTimeout;
  ManagedTutorState _state = ManagedTutorState.disconnected;
  ManagedTutorState get state => _state;
  String? _replyText;
  String? get replyText => _replyText;
  final List<({bool isUser, String text})> _messages = [];
  List<({bool isUser, String text})> get messages =>
      List.unmodifiable(_messages);
  ManagedTutorBinding? _binding;
  AiCancellation? _cancellation;
  int _generation = 0;
  int _operation = 0;
  bool _disposed = false;

  Future<void> connect({
    required String ownerId,
    required String accountId,
  }) async {
    if (_disposed) return;
    _invalidate();
    if (ownerId.trim().isEmpty || accountId.trim().isEmpty) {
      _publish(ManagedTutorState.providerUnavailable);
      return;
    }
    final binding = ManagedTutorBinding(
      ownerId: ownerId.trim(),
      accountId: accountId.trim(),
      generation: _generation,
    );
    _binding = binding;
    await _perform(binding, ManagedTutorState.pending, (cancel) async {
      await transport.connect(binding: binding, cancellation: cancel);
      return null;
    });
  }

  Future<void> send(String message) async {
    final binding = _binding;
    final text = message.trim();
    if (_disposed ||
        _state != ManagedTutorState.ready ||
        binding == null ||
        text.isEmpty ||
        text.length > 4000) {
      return;
    }
    _messages.add((isUser: true, text: text));
    await _perform(binding, ManagedTutorState.replying, (cancel) async {
      final reply = await transport.reply(
        binding: binding,
        learnerMessage: text,
        cancellation: cancel,
      );
      if (reply.text.trim().isEmpty || reply.text.length > 16000) {
        throw const AiTutorException(AiFailureCode.malformedResponse);
      }
      return reply.text.trim();
    });
  }

  Future<void> _perform(
    ManagedTutorBinding binding,
    ManagedTutorState pending,
    Future<String?> Function(AiCancellation) action,
  ) async {
    final operation = ++_operation;
    final cancel = AiCancellation();
    _cancellation = cancel;
    var timedOut = false;
    final timer = Timer(operationTimeout, () {
      timedOut = true;
      cancel.cancel();
    });
    _publish(pending);
    bool current() =>
        !_disposed && operation == _operation && identical(_binding, binding);
    try {
      // Race inside the owner gate so an uncooperative transport cannot retain
      // the lease indefinitely; late values/errors are consumed and discarded.
      final value = await _cancelable(
        ownerCoordinator.run(cancel, (ownerId) async {
          if (!current() || ownerId != binding.ownerId || cancel.isCancelled) {
            throw const AiTutorException(AiFailureCode.cancelled);
          }
          final result = await _cancelable(
            Future<String?>.sync(() => action(cancel)),
            cancel,
          );
          final activeOwner = await _cancelable(
            ownerCoordinator.activeOwnerId(),
            cancel,
          );
          if (!current() || activeOwner.trim() != binding.ownerId) {
            throw const AiTutorException(AiFailureCode.cancelled);
          }
          return result;
        }),
        cancel,
      );
      if (!current()) return;
      // Recheck after coordinator cleanup, which is itself asynchronous.
      final activeOwner = await _cancelable(
        ownerCoordinator.activeOwnerId(),
        cancel,
      );
      if (!current()) return;
      if (cancel.isCancelled || activeOwner.trim() != binding.ownerId) {
        throw const AiTutorException(AiFailureCode.cancelled);
      }
      _publish(ManagedTutorState.ready, reply: value);
    } on Object catch (error) {
      if (!current()) return;
      cancel.cancel();
      _binding = null;
      final code = error is AiTutorException
          ? error.code
          : AiFailureCode.providerUnavailable;
      _publish(
        timedOut
            ? ManagedTutorState.expired
            : switch (code) {
                AiFailureCode.cancelled => ManagedTutorState.cancelled,
                AiFailureCode.timeout => ManagedTutorState.expired,
                AiFailureCode.offline => ManagedTutorState.offline,
                AiFailureCode.quota ||
                AiFailureCode.rateLimited => ManagedTutorState.quotaExhausted,
                _ => ManagedTutorState.providerUnavailable,
              },
      );
    } finally {
      timer.cancel();
      if (identical(_cancellation, cancel)) _cancellation = null;
    }
  }

  static Future<T> _cancelable<T>(Future<T> work, AiCancellation cancel) =>
      Future.any<T>([
        work,
        cancel.whenCancelled.then<T>(
          (_) => throw const AiTutorException(AiFailureCode.cancelled),
        ),
      ]);

  void cancel() => _stop(ManagedTutorState.cancelled);
  void setOffline() => _stop(ManagedTutorState.offline);

  /// Local-only disconnect; it makes no claim of remote provider revocation.
  void disconnect() => _stop(ManagedTutorState.disconnected);
  void ownerChanged() => disconnect();

  void _invalidate() {
    _operation++;
    _generation++;
    _cancellation?.cancel();
    _cancellation = null;
    _binding = null;
    _replyText = null;
    _messages.clear();
  }

  void _stop(ManagedTutorState state) {
    if (_disposed) return;
    _invalidate();
    _publish(state);
  }

  void _publish(ManagedTutorState state, {String? reply}) {
    _state = state;
    _replyText = reply;
    if (reply != null) _messages.add((isUser: false, text: reply));
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _invalidate();
    _state = ManagedTutorState.disconnected;
    super.dispose();
  }
}
