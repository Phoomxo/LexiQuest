import 'association_record.dart';
import 'memory_state.dart';
import 'reading_session.dart';
import 'recall_attempt.dart';

class LocalLearningRepository {
  final Map<String, AssociationRecord> _associations = {};
  final Map<String, MemoryState> _memoryStates = {};
  final List<RecallAttempt> _attempts = [];
  final Map<String, ReadingSession> _sessions = {};

  Future<void> saveAssociation(AssociationRecord record) async {
    _associations[record.associationId] = record;
  }

  Future<AssociationRecord?> getAssociation(String associationId) async {
    return _associations[associationId];
  }

  Future<List<AssociationRecord>> getAssociationsForWord(
    String ownerId,
    String wordKey,
  ) async {
    return _associations.values
        .where((a) => a.ownerId == ownerId && a.wordKey == wordKey)
        .toList();
  }

  Future<void> deleteAssociation(String associationId) async {
    _associations.remove(associationId);
  }

  Future<void> saveMemoryState(MemoryState state) async {
    _memoryStates['${state.ownerId}:${state.wordKey}'] = state;
  }

  Future<MemoryState?> getMemoryState(String ownerId, String wordKey) async {
    return _memoryStates['$ownerId:$wordKey'];
  }

  Future<List<MemoryState>> getAllMemoryStates(String ownerId) async {
    return _memoryStates.values.where((s) => s.ownerId == ownerId).toList();
  }

  Future<void> recordAttempt(RecallAttempt attempt) async {
    _attempts.add(attempt);
  }

  Future<List<RecallAttempt>> getAttemptsForWord(String wordKey) async {
    return _attempts.where((a) => a.wordKey == wordKey).toList();
  }

  Future<void> saveSession(ReadingSession session) async {
    _sessions[session.sessionId] = session;
  }

  Future<ReadingSession?> getSession(String sessionId) async {
    return _sessions[sessionId];
  }
}
