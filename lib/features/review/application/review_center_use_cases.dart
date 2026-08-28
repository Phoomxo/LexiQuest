import '../../learning/application/learning_use_cases.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../domain/review_queue_item.dart';

typedef ReviewCenterUtcNow = DateTime Function();

abstract interface class ReviewSessionLauncher {
  Object get authorityIdentity;

  Future<PinnedReviewSessionLaunch> start({
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> items,
  });

  Future<void> abandon({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  });
}

final class LearningUseCasesReviewSessionLauncher
    implements ReviewSessionLauncher {
  const LearningUseCasesReviewSessionLauncher(this.learning);

  final LearningUseCases learning;

  @override
  Object get authorityIdentity => learning;

  @override
  Future<PinnedReviewSessionLaunch> start({
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> items,
  }) => learning.startPinnedReviewSession(ownerId: ownerId, items: items);

  @override
  Future<void> abandon({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) async {
    await learning.abandonSession(
      ownerId: ownerId,
      sessionId: sessionId,
      abandonedAtUtc: abandonedAtUtc,
    );
  }
}

final class ReviewLessonLaunchRequest {
  factory ReviewLessonLaunchRequest({
    required String ownerId,
    required QuizSession session,
    required Iterable<ReviewedLexicalContentSnapshot> items,
    required ReviewQueueItem item,
    required String timezoneId,
  }) {
    final configuration = _ReviewLessonLaunchConfiguration(
      ownerId: ownerId,
      items: items,
      timezoneId: timezoneId,
    );
    _requireSessionMatches(session, configuration.items);
    return ReviewLessonLaunchRequest._validated(
      configuration: configuration,
      session: session,
      item: item,
    );
  }

  ReviewLessonLaunchRequest._validated({
    required _ReviewLessonLaunchConfiguration configuration,
    required this.session,
    required this.item,
  }) : ownerId = configuration.ownerId,
       items = configuration.items,
       timezoneId = configuration.timezoneId;

  static void _requireSessionMatches(
    QuizSession session,
    List<ReviewedLexicalContentSnapshot> items,
  ) {
    _requireCanonicalText(session.id, 'session.id');
    final startedAtUtc = session.startedAtUtc;
    if (startedAtUtc == null ||
        !startedAtUtc.isUtc ||
        startedAtUtc.millisecondsSinceEpoch < 0 ||
        session.questions.length != items.length) {
      throw ArgumentError('launch must contain one canonical active session');
    }
    for (var index = 0; index < items.length; index += 1) {
      final snapshot = items[index];
      final identity = snapshot.identity;
      final word = session.questions[index].word;
      if (identity.type != ContentType.lexicalMetadata ||
          identity.id != word.id ||
          identity.revision != word.contentRevision ||
          snapshot.categoryId != word.categoryId ||
          snapshot.spelling != word.spelling ||
          snapshot.normalizedSpelling != word.normalizedSpelling ||
          snapshot.meaning != word.meaning ||
          snapshot.normalizedMeaning != word.normalizedMeaning ||
          snapshot.partOfSpeech != word.partOfSpeech ||
          snapshot.cefrLevel != word.cefrLevel ||
          snapshot.coreChecksumSha256 != word.contentChecksumSha256) {
        throw ArgumentError('launch content does not match its pinned session');
      }
    }
  }

  final String ownerId;
  final QuizSession session;
  final ReviewQueueItem item;
  final List<ReviewedLexicalContentSnapshot> items;
  final String timezoneId;
}

/// Read-model orchestration plus a narrow adapter into canonical learning
/// session creation. This class never writes attempts, rewards, or evidence.
final class ReviewCenterUseCases {
  const ReviewCenterUseCases({
    required this.reader,
    required this.ownerIdentities,
    required this.sessionLauncher,
    required this.nowUtc,
    required this.timezoneId,
  });

  final ReviewCenterReader reader;
  final ReviewOwnerIdentityReader ownerIdentities;
  final ReviewSessionLauncher sessionLauncher;
  final ReviewCenterUtcNow nowUtc;
  final String timezoneId;

  Object get sessionAuthorityIdentity => sessionLauncher.authorityIdentity;

  Future<List<ReviewQueueItem>> load({
    Set<ReviewQueueReason> includeReasons = ReviewQueueFilter.allReasons,
    int? limit,
  }) async {
    final ownerId = await ownerIdentities.requireSingleActiveOwnerId();
    return reader.compose(
      ReviewQueueFilter(
        ownerId: ownerId,
        evaluatedAtUtc: _now(),
        timezoneId: timezoneId,
        includeReasons: includeReasons,
        limit: limit,
      ),
    );
  }

  Future<ReviewLessonLaunchRequest> launch(ReviewQueueItem item) async {
    _requireCanonicalText(timezoneId, 'timezoneId');
    final ownerId = await ownerIdentities.requireSingleActiveOwnerId();
    final configuration = _ReviewLessonLaunchConfiguration(
      ownerId: ownerId,
      items: <ReviewedLexicalContentSnapshot>[item.snapshot],
      timezoneId: timezoneId,
    );
    final launch = await sessionLauncher.start(
      ownerId: configuration.ownerId,
      items: configuration.items,
    );
    final validatedConfiguration = _ReviewLessonLaunchConfiguration(
      ownerId: ownerId,
      items: launch.content,
      timezoneId: timezoneId,
    );
    final session = launch.session;
    ReviewLessonLaunchRequest._requireSessionMatches(
      session,
      validatedConfiguration.items,
    );
    // The canonical learning repository constructs and validates this exact
    // session before its final atomic insert. No fallible validation belongs
    // between persistence and shell attachment.
    return ReviewLessonLaunchRequest._validated(
      configuration: validatedConfiguration,
      session: session,
      item: ReviewQueueItem(
        snapshot: validatedConfiguration.items.single,
        provenance: item.provenance,
      ),
    );
  }

  Future<void> abandonLaunch(ReviewLessonLaunchRequest request) =>
      sessionLauncher.abandon(
        ownerId: request.ownerId,
        sessionId: request.session.id,
        abandonedAtUtc: _now(),
      );

  DateTime _now() {
    final value = nowUtc();
    if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(
        value,
        'nowUtc',
        'must return a nonnegative UTC time',
      );
    }
    return value;
  }
}

final class _ReviewLessonLaunchConfiguration {
  _ReviewLessonLaunchConfiguration({
    required this.ownerId,
    required Iterable<ReviewedLexicalContentSnapshot> items,
    required this.timezoneId,
  }) : items = List<ReviewedLexicalContentSnapshot>.unmodifiable(items) {
    _requireCanonicalText(ownerId, 'ownerId');
    _requireCanonicalText(timezoneId, 'timezoneId');
    if (this.items.isEmpty || this.items.length > 100) {
      throw ArgumentError.value(items, 'items', 'must contain 1–100 items');
    }
    final identities = <String>{};
    for (final item in this.items) {
      final identity = item.identity;
      _requireCanonicalText(identity.id, 'items.id');
      if (identity.type != ContentType.lexicalMetadata ||
          identity.revision <= 0 ||
          !identities.add(identity.id)) {
        throw ArgumentError.value(
          item,
          'items',
          'must contain unique positive lexical identities',
        );
      }
    }
  }

  final String ownerId;
  final List<ReviewedLexicalContentSnapshot> items;
  final String timezoneId;
}

void _requireCanonicalText(String value, String name) {
  if (value.isEmpty || value != value.trim() || value.runes.length > 256) {
    throw ArgumentError.value(value, name, 'must be canonical nonblank text');
  }
}
