import 'progress_repository.dart';

enum ProgressRemoteFailure {
  unauthenticated,
  invalidRequest,
  unavailable,
  localPersistence,
  unknown,
}

sealed class ProgressRemoteResult {
  const ProgressRemoteResult();
}

final class ProgressRemoteAccepted extends ProgressRemoteResult {
  const ProgressRemoteAccepted({required this.duplicate});

  final bool duplicate;
}

final class ProgressRemoteRejected extends ProgressRemoteResult {
  const ProgressRemoteRejected(this.failure);

  final ProgressRemoteFailure failure;
}

abstract interface class ProgressRemoteWriter {
  Future<ProgressRemoteResult> recordProgressSession(ProgressSession session);
}
