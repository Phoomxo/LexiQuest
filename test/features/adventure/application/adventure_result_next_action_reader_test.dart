import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_result_next_action_reader.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_result.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';

void main() {
  group('ReviewCenterAdventureResultNextActionReader', () {
    test('maps an empty canonical queue to none', () async {
      final reader = _ReviewReader(const <ReviewQueueItem>[]);
      final subject = _subject(reader: reader);

      expect(await subject.read(ownerId: _ownerId), AdventureNextAction.none);
    });

    test('maps due-SRS work anywhere in queue provenance to SRS', () async {
      final reader = _ReviewReader(<ReviewQueueItem>[
        _item(
          id: 'word:incorrect',
          provenance: <ReviewReasonProvenance>[
            ReviewReasonProvenance.incorrect(
              sourceId: 'attempt:incorrect',
              occurredAtUtc: _nowUtc,
            ),
          ],
        ),
        _item(
          id: 'word:mixed',
          provenance: <ReviewReasonProvenance>[
            ReviewReasonProvenance.saved(
              sourceId: 'saved:mixed',
              occurredAtUtc: _nowUtc,
            ),
            ReviewReasonProvenance.due(
              sourceId: 'srs:mixed',
              dueAtUtc: _nowUtc,
            ),
          ],
        ),
      ]);

      expect(
        await _subject(reader: reader).read(ownerId: _ownerId),
        AdventureNextAction.spacedRepetition,
      );
    });

    test('maps nonempty non-SRS canonical work to Review Center', () async {
      final reader = _ReviewReader(<ReviewQueueItem>[
        _item(
          id: 'word:saved',
          provenance: <ReviewReasonProvenance>[
            ReviewReasonProvenance.saved(
              sourceId: 'saved:one',
              occurredAtUtc: _nowUtc,
            ),
          ],
        ),
      ]);

      expect(
        await _subject(reader: reader).read(ownerId: _ownerId),
        AdventureNextAction.reviewCenter,
      );
    });

    test('composes the exact bounded deterministic canonical filter', () async {
      var nowCalls = 0;
      final reader = _ReviewReader(const <ReviewQueueItem>[]);
      final owners = _OwnerIdentities.value(_ownerId);
      final subject = ReviewCenterAdventureResultNextActionReader(
        reader: reader,
        ownerIdentities: owners,
        nowUtc: () {
          nowCalls += 1;
          return _nowUtc;
        },
        timezoneId: _timezoneId,
      );

      await subject.read(ownerId: _ownerId);

      expect(nowCalls, 1);
      expect(owners.calls, 1);
      expect(reader.calls, 1);
      expect(reader.filter!.ownerId, _ownerId);
      expect(reader.filter!.evaluatedAtUtc, _nowUtc);
      expect(reader.filter!.timezoneId, _timezoneId);
      expect(reader.filter!.includeReasons, ReviewQueueFilter.allReasons);
      expect(reader.filter!.limit, 100);
    });

    test(
      'owner drift fails closed before reading another owner queue',
      () async {
        final reader = _ReviewReader(<ReviewQueueItem>[
          _item(
            id: 'word:foreign',
            provenance: <ReviewReasonProvenance>[
              ReviewReasonProvenance.due(
                sourceId: 'srs:foreign',
                dueAtUtc: _nowUtc,
              ),
            ],
          ),
        ]);
        final subject = _subject(
          reader: reader,
          owners: _OwnerIdentities.value('owner:other'),
        );

        expect(await subject.read(ownerId: _ownerId), AdventureNextAction.none);
        expect(reader.calls, 0);
      },
    );

    test('owner and canonical source exceptions fail closed to none', () async {
      final unreadReader = _ReviewReader(<ReviewQueueItem>[
        _item(
          id: 'word:unread',
          provenance: <ReviewReasonProvenance>[
            ReviewReasonProvenance.saved(
              sourceId: 'saved:unread',
              occurredAtUtc: _nowUtc,
            ),
          ],
        ),
      ]);
      final ownerFailure = _subject(
        reader: unreadReader,
        owners: _OwnerIdentities.error(StateError('owner unavailable')),
      );
      final sourceFailure = _subject(
        reader: _ReviewReader.error(StateError('review unavailable')),
      );

      expect(
        await ownerFailure.read(ownerId: _ownerId),
        AdventureNextAction.none,
      );
      expect(unreadReader.calls, 0);
      expect(
        await sourceFailure.read(ownerId: _ownerId),
        AdventureNextAction.none,
      );
    });

    test('invalid requested owner throws before clock or source handling', () {
      var nowCalls = 0;
      final reader = _ReviewReader(const <ReviewQueueItem>[]);
      final owners = _OwnerIdentities.value(_ownerId);
      final subject = ReviewCenterAdventureResultNextActionReader(
        reader: reader,
        ownerIdentities: owners,
        nowUtc: () {
          nowCalls += 1;
          return _nowUtc;
        },
        timezoneId: _timezoneId,
      );

      for (final ownerId in <String>['', ' owner:one', 'owner:one\n']) {
        expect(
          () => subject.read(ownerId: ownerId),
          throwsArgumentError,
          reason: ownerId,
        );
      }
      expect(nowCalls, 0);
      expect(owners.calls, 0);
      expect(reader.calls, 0);
    });

    test('invalid constructor values throw and inclusive bounds are valid', () {
      for (final limit in <int>[0, 101]) {
        expect(
          () => ReviewCenterAdventureResultNextActionReader(
            reader: _ReviewReader(const <ReviewQueueItem>[]),
            ownerIdentities: _OwnerIdentities.value(_ownerId),
            nowUtc: () => _nowUtc,
            timezoneId: _timezoneId,
            limit: limit,
          ),
          throwsArgumentError,
        );
      }
      for (final timezoneId in <String>['', ' Asia/Bangkok', 'UTC\n']) {
        expect(
          () => ReviewCenterAdventureResultNextActionReader(
            reader: _ReviewReader(const <ReviewQueueItem>[]),
            ownerIdentities: _OwnerIdentities.value(_ownerId),
            nowUtc: () => _nowUtc,
            timezoneId: timezoneId,
          ),
          throwsArgumentError,
          reason: timezoneId,
        );
      }
      for (final limit in <int>[1, 100]) {
        expect(
          () => ReviewCenterAdventureResultNextActionReader(
            reader: _ReviewReader(const <ReviewQueueItem>[]),
            ownerIdentities: _OwnerIdentities.value(_ownerId),
            nowUtc: () => _nowUtc,
            timezoneId: _timezoneId,
            limit: limit,
          ),
          returnsNormally,
        );
      }
    });

    test('invalid clock value throws before owner or source handling', () {
      final reader = _ReviewReader(const <ReviewQueueItem>[]);
      final owners = _OwnerIdentities.value(_ownerId);
      final subject = ReviewCenterAdventureResultNextActionReader(
        reader: reader,
        ownerIdentities: owners,
        nowUtc: () => DateTime(2026, 9, 5),
        timezoneId: _timezoneId,
      );

      expect(() => subject.read(ownerId: _ownerId), throwsArgumentError);
      expect(owners.calls, 0);
      expect(reader.calls, 0);
    });

    test('identity getters expose the exact composed authorities', () {
      final reader = _ReviewReader(const <ReviewQueueItem>[]);
      final owners = _OwnerIdentities.value(_ownerId);
      final subject = _subject(reader: reader, owners: owners);

      expect(subject.readerIdentity, same(reader));
      expect(subject.ownerIdentity, same(owners));
    });
  });
}

ReviewCenterAdventureResultNextActionReader _subject({
  required _ReviewReader reader,
  _OwnerIdentities? owners,
}) => ReviewCenterAdventureResultNextActionReader(
  reader: reader,
  ownerIdentities: owners ?? _OwnerIdentities.value(_ownerId),
  nowUtc: () => _nowUtc,
  timezoneId: _timezoneId,
);

final class _ReviewReader implements ReviewCenterReader {
  _ReviewReader(this.items) : error = null;

  _ReviewReader.error(this.error) : items = const <ReviewQueueItem>[];

  final List<ReviewQueueItem> items;
  final Object? error;
  ReviewQueueFilter? filter;
  int calls = 0;

  @override
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter) async {
    calls += 1;
    this.filter = filter;
    if (error case final error?) throw error;
    return items;
  }
}

final class _OwnerIdentities implements ReviewOwnerIdentityReader {
  _OwnerIdentities.value(this.ownerId) : error = null;

  _OwnerIdentities.error(this.error) : ownerId = null;

  final String? ownerId;
  final Object? error;
  int calls = 0;

  @override
  Future<String> requireSingleActiveOwnerId() async {
    calls += 1;
    if (error case final error?) throw error;
    return ownerId!;
  }
}

ReviewQueueItem _item({
  required String id,
  required Iterable<ReviewReasonProvenance> provenance,
}) => ReviewQueueItem(
  snapshot: ReviewedLexicalContentSnapshot(
    identity: ContentIdentity(
      type: ContentType.lexicalMetadata,
      id: id,
      revision: 1,
    ),
    categoryId: 'category:one',
    spelling: id,
    normalizedSpelling: id,
    meaning: 'meaning-$id',
    normalizedMeaning: 'meaning-$id',
    partOfSpeech: 'noun',
    cefrLevel: null,
    source: 'manual',
    isGlobal: false,
    coreChecksumSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    provenance: ContentProvenance.userAuthored,
    reviewState: ContentReviewState.unreviewed,
    publicationState: ContentPublicationState.private,
    artifact: null,
  ),
  provenance: provenance,
);

const String _ownerId = 'owner:one';
const String _timezoneId = 'Asia/Bangkok';
final DateTime _nowUtc = DateTime.utc(2026, 9, 5, 9, 30);
