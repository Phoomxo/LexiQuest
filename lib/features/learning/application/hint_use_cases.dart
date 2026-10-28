import '../domain/hint_policy.dart';

final class HintUseCases {
  HintUseCases({required this.policy, HintState? initialState})
    : _state = initialState ?? policy.initialState;

  final HintPolicy policy;
  HintState _state;

  HintState get state => _state;

  HintRevealResult revealNext() {
    final result = policy.revealNext(_state);
    _state = result.state;
    return result;
  }

  HintUsageSnapshot snapshot() => policy.snapshot(_state);

  void resetAfterCommittedEvidence() {
    _state = policy.initialState;
  }
}
