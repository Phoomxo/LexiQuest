enum PairRepairStatus { waiting, available, guidedRequired, completed }

final class PairRepairAnswer {
  const PairRepairAnswer(this.operationId, this.wordId, this.isCorrect);
  final String operationId, wordId;
  final bool isCorrect;
}

final class PairRepairTicket {
  const PairRepairTicket({
    required this.wordId,
    required this.sourceOperationId,
    required this.originalOrdinal,
    required this.dueOrdinal,
    required this.status,
    this.deferred = false,
  });
  final String wordId, sourceOperationId;
  final int originalOrdinal, dueOrdinal;
  final PairRepairStatus status;
  final bool deferred;
  PairRepairTicket withStatus(PairRepairStatus value) => PairRepairTicket(
    wordId: wordId,
    sourceOperationId: sourceOperationId,
    originalOrdinal: originalOrdinal,
    dueOrdinal: dueOrdinal,
    status: value,
    deferred: deferred || value == PairRepairStatus.guidedRequired,
  );
}

/// Rebuildable from the retained authenticated attempt ledger. No second
/// persisted queue or duplicate lexical identities are needed in checkpoints.
abstract final class PairRepairPolicy {
  static List<PairRepairTicket> project(
    List<String> wordIds,
    Iterable<PairRepairAnswer> answers,
  ) {
    final tickets = <String, PairRepairTicket>{};
    final matched = <String>{};
    var ordinal = 0;
    for (final a in answers) {
      final previous = tickets[a.wordId];
      if (a.isCorrect) {
        matched.add(a.wordId);
        if (previous != null) {
          tickets[a.wordId] = previous.withStatus(PairRepairStatus.completed);
        }
      } else if (previous == null) {
        tickets[a.wordId] = PairRepairTicket(
          wordId: a.wordId,
          sourceOperationId: a.operationId,
          originalOrdinal: ordinal,
          dueOrdinal: matched.length + wordIds.length ~/ 2,
          status: PairRepairStatus.waiting,
        );
      } else {
        tickets[a.wordId] = previous.withStatus(
          PairRepairStatus.guidedRequired,
        );
      }
      for (final t in tickets.values.toList()) {
        if (t.status == PairRepairStatus.waiting &&
            matched.length >= t.dueOrdinal) {
          tickets[t.wordId] = t.withStatus(PairRepairStatus.available);
        }
        if (t.status == PairRepairStatus.waiting &&
            matched.length +
                    wordIds
                        .where((id) => id != t.wordId && !matched.contains(id))
                        .length <
                t.dueOrdinal) {
          tickets[t.wordId] = t.withStatus(PairRepairStatus.guidedRequired);
        }
      }
      // When all remaining pairs wait on one another, expose one deterministic
      // guided tail. Its real confirmation can advance the other tickets.
      final playable = wordIds.where(
        (id) =>
            !matched.contains(id) &&
            tickets[id]?.status != PairRepairStatus.waiting,
      );
      if (playable.isEmpty) {
        final waiting =
            tickets.values
                .where((t) => t.status == PairRepairStatus.waiting)
                .toList()
              ..sort(compare);
        if (waiting.isNotEmpty) {
          tickets[waiting.first.wordId] = waiting.first.withStatus(
            PairRepairStatus.guidedRequired,
          );
        }
      }
      ordinal++;
    }
    return List.unmodifiable(tickets.values.toList()..sort(compare));
  }

  static int compare(PairRepairTicket a, PairRepairTicket b) {
    final due = a.dueOrdinal.compareTo(b.dueOrdinal);
    if (due != 0) return due;
    final original = a.originalOrdinal.compareTo(b.originalOrdinal);
    return original != 0 ? original : a.wordId.compareTo(b.wordId);
  }
}
