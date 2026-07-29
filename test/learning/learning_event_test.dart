import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/learning_event.dart';

LearningEvent _referenceEvent({
  DateTime? occurredAtUtc,
  int schemaVersion = 1,
  int score = 100,
  int attemptNumber = 1,
  int? responseTimeMs = 1200,
  String eventId = 'quiz-session-1:0',
  String pseudonymousUserId = 'firebase-uid-1',
  String contentId = 'word:apple',
  String? categoryId = 'fruit',
  String? cefrLevel = 'A1',
  String appVersion = '1.0.0+1',
  String buildId = '214b2b6',
}) {
  return LearningEvent(
    eventId: eventId,
    schemaVersion: schemaVersion,
    pseudonymousUserId: pseudonymousUserId,
    occurredAtUtc: occurredAtUtc ?? DateTime.utc(2026, 7, 26, 1),
    activity: LearningActivity.multipleChoiceQuiz,
    contentId: contentId,
    categoryId: categoryId,
    cefrLevel: cefrLevel,
    skill: LearningSkill.meaningRecall,
    correct: true,
    score: score,
    responseTimeMs: responseTimeMs,
    attemptNumber: attemptNumber,
    appVersion: appVersion,
    buildId: buildId,
  );
}

void main() {
  group('LearningEvent', () {
    test('constructor preserves every field from the Task 1 example', () {
      final event = _referenceEvent();

      expect(event.eventId, 'quiz-session-1:0');
      expect(event.schemaVersion, 1);
      expect(event.pseudonymousUserId, 'firebase-uid-1');
      expect(event.occurredAtUtc, DateTime.utc(2026, 7, 26, 1));
      expect(event.activity, LearningActivity.multipleChoiceQuiz);
      expect(event.contentId, 'word:apple');
      expect(event.categoryId, 'fruit');
      expect(event.cefrLevel, 'A1');
      expect(event.skill, LearningSkill.meaningRecall);
      expect(event.correct, isTrue);
      expect(event.score, 100);
      expect(event.responseTimeMs, 1200);
      expect(event.attemptNumber, 1);
      expect(event.appVersion, '1.0.0+1');
      expect(event.buildId, '214b2b6');
    });

    test(
      'toMap/fromMap round-trip preserves data with stable enum wire values',
      () {
        final event = _referenceEvent();
        final map = event.toMap();

        expect(map['activity'], 'multiple_choice_quiz');
        expect(map['skill'], 'meaning_recall');

        final restored = LearningEvent.fromMap(map);
        expect(restored.activity, LearningActivity.multipleChoiceQuiz);
        expect(restored.skill, LearningSkill.meaningRecall);
        expect(restored.eventId, event.eventId);
        expect(restored.score, event.score);
        expect(restored.occurredAtUtc, event.occurredAtUtc);
      },
    );

    test('associative reading dimensions use stable wire values', () {
      final event = LearningEvent(
        eventId: 'reading-event-1',
        schemaVersion: 1,
        pseudonymousUserId: 'owner-a',
        occurredAtUtc: DateTime.utc(2026, 7, 29),
        activity: LearningActivity.associativeReading,
        contentId: 'reading-content-1',
        categoryId: 'transferMastery',
        cefrLevel: 'A2',
        skill: LearningSkill.contextRecall,
        correct: true,
        score: 100,
        responseTimeMs: 900,
        attemptNumber: 1,
        appVersion: '1.0.0+1',
        buildId: 'build-1',
      );

      expect(event.toMap()['activity'], 'associative_reading');
      expect(event.toMap()['skill'], 'context_recall');
      expect(
        LearningEvent.fromMap(event.toMap()).activity,
        LearningActivity.associativeReading,
      );
    });

    test('normalizes a non-UTC DateTime to UTC', () {
      final local = DateTime(2026, 7, 26, 1);
      expect(local.isUtc, isFalse);

      final event = _referenceEvent(occurredAtUtc: local);

      expect(event.occurredAtUtc.isUtc, isTrue);
      expect(event.occurredAtUtc, local.toUtc());
    });

    test('toString is exactly LearningEvent and exposes no field value', () {
      expect(_referenceEvent().toString(), 'LearningEvent');
    });

    test('constructor throws ArgumentError when schemaVersion is not 1', () {
      expect(() => _referenceEvent(schemaVersion: 0), throwsArgumentError);
      expect(() => _referenceEvent(schemaVersion: 2), throwsArgumentError);
    });

    test(
      'constructor throws for score outside 0 to 100 and accepts boundaries',
      () {
        expect(() => _referenceEvent(score: -1), throwsArgumentError);
        expect(() => _referenceEvent(score: 101), throwsArgumentError);
        expect(_referenceEvent(score: 0).score, 0);
        expect(_referenceEvent(score: 100).score, 100);
      },
    );

    test('constructor throws when attemptNumber is below 1', () {
      expect(() => _referenceEvent(attemptNumber: 0), throwsArgumentError);
      expect(() => _referenceEvent(attemptNumber: -1), throwsArgumentError);
    });

    test('response time cannot be negative', () {
      expect(() => _referenceEvent(responseTimeMs: -1), throwsArgumentError);
    });

    test('required identifiers reject blank or values over 200 characters', () {
      final builders = <String, LearningEvent Function(String)>{
        'eventId': (value) => _referenceEvent(eventId: value),
        'pseudonymousUserId': (value) =>
            _referenceEvent(pseudonymousUserId: value),
        'contentId': (value) => _referenceEvent(contentId: value),
        'appVersion': (value) => _referenceEvent(appVersion: value),
        'buildId': (value) => _referenceEvent(buildId: value),
      };
      final cases = <String, String>{
        'empty': '',
        'whitespace-only': ' \t ',
        'too-long': 'x' * 201,
      };

      for (final entry in builders.entries) {
        for (final invalidCase in cases.entries) {
          expect(
            () => entry.value(invalidCase.value),
            throwsArgumentError,
            reason: '${entry.key} rejects ${invalidCase.key}',
          );
        }
      }

      expect(_referenceEvent(eventId: 'x' * 200).eventId.length, 200);
    });

    test('fromMap rejects unknown activity or skill wire values', () {
      final base = _referenceEvent().toMap();
      final unknownActivity = Map<String, dynamic>.from(base)
        ..['activity'] = 'unknown_activity';
      final unknownSkill = Map<String, dynamic>.from(base)
        ..['skill'] = 'unknown_skill';

      expect(() => LearningEvent.fromMap(unknownActivity), throwsArgumentError);
      expect(() => LearningEvent.fromMap(unknownSkill), throwsArgumentError);
    });

    test(
      'optional dimensions and response time accept and round-trip null',
      () {
        final event = _referenceEvent(
          categoryId: null,
          cefrLevel: null,
          responseTimeMs: null,
        );

        expect(event.categoryId, isNull);
        expect(event.cefrLevel, isNull);
        expect(event.responseTimeMs, isNull);

        final restored = LearningEvent.fromMap(event.toMap());
        expect(restored.categoryId, isNull);
        expect(restored.cefrLevel, isNull);
        expect(restored.responseTimeMs, isNull);
      },
    );

    test('toMap contains only declared keys and no forbidden payload', () {
      final map = _referenceEvent().toMap();
      const expectedKeys = <String>{
        'eventId',
        'schemaVersion',
        'pseudonymousUserId',
        'occurredAtUtc',
        'activity',
        'contentId',
        'categoryId',
        'cefrLevel',
        'skill',
        'correct',
        'score',
        'responseTimeMs',
        'attemptNumber',
        'appVersion',
        'buildId',
      };

      expect(map.keys, unorderedEquals(expectedKeys));
      expect(map.length, 15);

      final combined = <String>[
        ...map.keys,
        for (final value in map.values) '$value',
        map.toString(),
        jsonEncode(map),
      ].join('\n').toLowerCase();
      const forbidden = <String>[
        'email',
        'token',
        'password',
        'prompt',
        'answertext',
        'audio',
        'image',
        'bearer',
      ];

      for (final term in forbidden) {
        expect(
          combined,
          isNot(contains(term)),
          reason: 'payload must not expose "$term"',
        );
      }
      expect(combined, isNot(contains('sentinel-never-supplied-7c4f8d9e2a')));
    });
  });
}
