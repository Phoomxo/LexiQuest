import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

void main() {
  group('accepted meaning quiz plan', () {
    test(
      'round-trips exact words, option order, real activity and checksum',
      () {
        final plan = _plan();
        final restored = AcceptedQuizPlan.parse(
          id: plan.id,
          json: plan.stableSerialization,
        );
        expect(restored.id, plan.id);
        expect(restored.stableSerialization, plan.stableSerialization);
        expect(restored.mode, 'meaning-quiz');
        expect(restored.activityType, 'quiz');
        expect(restored.questions.first.word.spelling, 'Polish');
        expect(restored.questions.first.options, ['ขัดเงา', 'ภาษาโปแลนด์']);
        expect(
          restored.questions.first.word.contentRevision,
          'local-vocabulary-v1:7',
        );
        final body =
            jsonDecode(plan.stableSerialization) as Map<String, dynamic>;
        expect(body.containsKey('ownerId'), isFalse);
        expect(body.containsKey('sessionId'), isFalse);
        expect(
          (body['questions'] as List).first['contentChecksumSha256'],
          quizWordChecksum(plan.questions.first.word),
        );
      },
    );

    test('one-option deck remains valid', () {
      final plan = AcceptedQuizPlan.create(
        configuration: QuizConfiguration.category(limit: 1),
        questions: [
          _question(options: ['ภาษาโปแลนด์']),
        ],
      );
      expect(plan.questions.single.options, ['ภาษาโปแลนด์']);
    });

    test('same content and configuration have the same plan identity', () {
      expect(_plan().id, _plan().id);
    });

    test('empty deck and requests above the current limit are rejected', () {
      expect(
        () => AcceptedQuizPlan.create(
          configuration: QuizConfiguration.category(),
          questions: [],
        ),
        throwsFormatException,
      );
      expect(
        () => QuizConfiguration.category(limit: 101),
        throwsFormatException,
      );
      expect(() => QuizConfiguration.category(limit: 0), throwsFormatException);
    });

    test('changed option order changes the full plan identity', () {
      final changed = AcceptedQuizPlan.create(
        configuration: QuizConfiguration.category(limit: 2),
        questions: [
          _question(options: ['ภาษาโปแลนด์', 'ขัดเงา']),
        ],
      );
      expect(changed.id, isNot(_plan().id));
    });

    test('source and weakness keep distinct canonical activity types', () {
      final source = AcceptedQuizPlan.create(
        configuration: QuizConfiguration.sourcePractice(
          wordIds: ['word:polish'],
        ),
        questions: [_question()],
      );
      final weakness = AcceptedQuizPlan.create(
        configuration: QuizConfiguration.weaknessPractice(
          wordIds: ['word:polish'],
        ),
        questions: [_question()],
      );
      expect(source.activityType, 'sourcePractice');
      expect(weakness.activityType, 'weaknessPractice');
      expect(source.id, isNot(weakness.id));
    });

    test('request serialization is independent of accepted item count', () {
      final configuration = QuizConfiguration.category(limit: 2);
      final first = AcceptedQuizPlan.create(
        configuration: configuration,
        questions: [_question()],
      );
      final second = AcceptedQuizPlan.create(
        configuration: configuration,
        questions: [
          _question(),
          _question(
            id: 'word:second',
            spelling: 'second',
            meaning: 'ที่สอง',
            options: ['ที่สอง'],
          ),
        ],
      );
      expect(
        first.configuration.stableSerialization,
        second.configuration.stableSerialization,
      );
      expect(first.id, isNot(second.id));
    });

    test(
      'target selection is deduplicated and sorted without affecting the deck',
      () {
        final configuration = QuizConfiguration.sourcePractice(
          wordIds: ['word:z', 'word:a', 'word:z'],
        );
        expect(configuration.wordIds, ['word:a', 'word:z']);
        expect(
          configuration.stableSerialization,
          QuizConfiguration.sourcePractice(
            wordIds: ['word:a', 'word:z'],
          ).stableSerialization,
        );
      },
    );

    test(
      'request budget rejects oversize input without truncating its tail',
      () {
        expect(
          () => QuizConfiguration.sourcePractice(
            wordIds: List.generate(
              5000,
              (i) => 'word:${i.toString().padLeft(245, '0')}',
            ),
          ),
          throwsFormatException,
        );
        final first = QuizConfiguration.sourcePractice(
          wordIds: ['word:polish', 'word:tail-a'],
        );
        final second = QuizConfiguration.sourcePractice(
          wordIds: ['word:polish', 'word:tail-b'],
        );
        expect(first.stableSerialization, isNot(second.stableSerialization));
        expect(first.wordIds, ['word:polish', 'word:tail-a']);
      },
    );

    test(
      'plan byte budget admits full decks at current escaped-text limits',
      () {
        final plan = AcceptedQuizPlan.create(
          configuration: QuizConfiguration.category(limit: 100),
          questions: List.generate(100, (i) {
            final meaning = 'm${'\u0001' * 499}';
            return QuizQuestion(
              word: QuizWord(
                id: 'word:$i',
                categoryId: 'category:languages',
                spelling: 's${'\u0001' * 119}',
                meaning: meaning,
                partOfSpeech: 'n${'\u0001' * 59}',
                contentRevision: 'local-vocabulary-v1:7',
              ),
              options: [
                meaning,
                for (var option = 1; option < 4; option++)
                  '$option${'\u0001' * 499}',
              ],
            );
          }),
        );
        expect(
          utf8.encode(plan.stableSerialization).length,
          lessThan(AcceptedQuizPlan.maxSerializedBytes),
        );
        expect(
          AcceptedQuizPlan.parse(
            id: plan.id,
            json: plan.stableSerialization,
          ).id,
          plan.id,
        );
      },
    );

    test('accepted question and options cannot be mutated through aliases', () {
      final options = ['ขัดเงา', 'ภาษาโปแลนด์'];
      final input = [_question(options: options)];
      final plan = AcceptedQuizPlan.create(
        configuration: QuizConfiguration.category(),
        questions: input,
      );
      final original = plan.stableSerialization;
      options.clear();
      input.clear();
      expect(plan.stableSerialization, original);
      expect(() => plan.questions.clear(), throwsUnsupportedError);
      expect(
        () => plan.questions.first.options.clear(),
        throwsUnsupportedError,
      );
    });

    test('text preserves case, Thai and Unicode exactly', () {
      final plan = AcceptedQuizPlan.create(
        configuration: QuizConfiguration.category(),
        questions: [
          _question(
            spelling: 'École ก😀',
            meaning: 'e\u0301',
            options: ['é', 'e\u0301'],
          ),
        ],
      );
      final restored = AcceptedQuizPlan.parse(
        id: plan.id,
        json: plan.stableSerialization,
      );
      expect(restored.questions.single.word.spelling, 'École ก😀');
      expect(restored.questions.single.options, ['é', 'e\u0301']);
    });

    test('missing source content revision cannot be accepted', () {
      expect(
        () => AcceptedQuizPlan.create(
          configuration: QuizConfiguration.category(),
          questions: [
            QuizQuestion(
              word: const QuizWord(
                id: 'w',
                categoryId: 'c',
                spelling: 'a',
                meaning: 'b',
                partOfSpeech: 'noun',
              ),
              options: const ['b'],
            ),
          ],
        ),
        throwsFormatException,
      );
    });

    test('duplicate word IDs and absent correct answers are rejected', () {
      expect(
        () => AcceptedQuizPlan.create(
          configuration: QuizConfiguration.category(),
          questions: [_question(), _question()],
        ),
        throwsFormatException,
      );
      expect(
        () => AcceptedQuizPlan.create(
          configuration: QuizConfiguration.category(),
          questions: [
            _question(options: ['wrong']),
          ],
        ),
        throwsFormatException,
      );
    });

    test('target plan cannot contain an unrequested word', () {
      expect(
        () => AcceptedQuizPlan.create(
          configuration: QuizConfiguration.sourcePractice(
            wordIds: ['word:other'],
          ),
          questions: [_question()],
        ),
        throwsFormatException,
      );
    });

    for (final count in [0, 5]) {
      test('rejects $count options', () {
        expect(
          () => AcceptedQuizPlan.create(
            configuration: QuizConfiguration.category(),
            questions: [
              _question(
                options: List.generate(
                  count,
                  (i) => i == 0 ? 'ภาษาโปแลนด์' : 'wrong$i',
                ),
              ),
            ],
          ),
          throwsFormatException,
        );
      });
    }

    test('tampered plan ID cannot be read', () {
      final plan = _plan();
      expect(
        () => AcceptedQuizPlan.parse(
          id: 'quiz-plan:${'0' * 64}',
          json: plan.stableSerialization,
        ),
        throwsFormatException,
      );
    });

    test(
      'unknown keys and noncanonical serialization are rejected even with matching hash',
      () {
        final body =
            jsonDecode(_plan().stableSerialization) as Map<String, dynamic>;
        body['ownerId'] = 'synthetic-owner';
        final json = jsonEncode(body);
        expect(
          () => AcceptedQuizPlan.parse(id: _id(json), json: json),
          throwsFormatException,
        );
        final pretty = const JsonEncoder.withIndent(
          ' ',
        ).convert(jsonDecode(_plan().stableSerialization));
        expect(
          () => AcceptedQuizPlan.parse(id: _id(pretty), json: pretty),
          throwsFormatException,
        );
      },
    );

    test('rehashed correct ordinal contradiction rejects', () {
      final body =
          jsonDecode(_plan().stableSerialization) as Map<String, dynamic>;
      ((body['questions'] as List).first
              as Map<String, dynamic>)['correctOptionOrdinal'] =
          0;
      final json = jsonEncode(body);
      expect(
        () => AcceptedQuizPlan.parse(id: _id(json), json: json),
        throwsFormatException,
      );
    });

    test(
      'unsupported policy is readable but cannot authorize fresh capture',
      () {
        final body =
            jsonDecode(_plan().stableSerialization) as Map<String, dynamic>;
        body['evidencePolicyVersion'] = 'unsupported-policy-v999';
        final json = jsonEncode(body);
        final plan = AcceptedQuizPlan.parse(id: _id(json), json: json);
        expect(plan.supportsCurrentPolicy, isFalse);
        expect(
          () => QuizAnswerReceipt.capture(
            plan: plan,
            ownerId: 'owner:one',
            attemptId: 'attempt:one',
            questionOrdinal: 0,
            selectedOptionOrdinal: 1,
            revealed: false,
            assistance: QuizAssistance(),
            occurredAtUtcMs: 50,
            responseTimeMs: null,
          ),
          throwsStateError,
        );
      },
    );
  });

  group('typed quiz checkpoints', () {
    test('rehashed changed word snapshot still needs its exact checksum', () {
      final body =
          jsonDecode(_plan().stableSerialization) as Map<String, dynamic>;
      ((body['questions'] as List).first as Map<String, dynamic>)['spelling'] =
          'polish';
      final json = jsonEncode(body);
      expect(
        () => AcceptedQuizPlan.parse(id: _id(json), json: json),
        throwsFormatException,
      );
    });

    test('pending ordinary answer cannot carry a research pin', () {
      final plan = _plan();
      final checkpoint = PendingQuizAnswer(
        planId: plan.id,
        questionOrdinal: 0,
        assistance: QuizAssistance(),
        answer: _answer(plan),
      );
      final body =
          jsonDecode(checkpoint.stableSerialization) as Map<String, dynamic>;
      final context =
          ((body['answer'] as Map<String, dynamic>)['evidenceContext']
              as Map<String, dynamic>);
      context['protocolId'] = 'synthetic-research-protocol';
      expect(
        () => QuizCheckpoint.parse(jsonEncode(body), plan: plan),
        throwsFormatException,
      );
    });

    test('initial state round-trips as an unanswered exact plan', () {
      final plan = _plan();
      final checkpoint = QuizCheckpoint.initial(plan);
      final restored = QuizCheckpoint.parse(
        checkpoint.stableSerialization,
        plan: plan,
      );
      expect(restored, isA<AwaitingQuizAnswer>());
      expect(restored.questionOrdinal, 0);
      expect(restored.planId, plan.id);
    });

    test('hiding a hint retains its first receipt across reopen', () {
      final plan = _plan();
      final assistance = QuizAssistance().showHint(10).hideHint().showHint(20);
      expect(assistance.hintFirstShownAtUtcMs, 10);
      final checkpoint = AwaitingQuizAnswer(
        planId: plan.id,
        questionOrdinal: 0,
        assistance: assistance.hideHint(),
      );
      final restored = QuizCheckpoint.parse(
        checkpoint.stableSerialization,
        plan: plan,
      );
      expect(restored.assistance.hintVisible, isFalse);
      expect(restored.assistance.hintFirstShownAtUtcMs, 10);
    });

    test(
      'pending answer preserves exact identity, option, time and full frozen evidence',
      () {
        final plan = _plan();
        final assistance = QuizAssistance().showHint(10);
        final answer = _answer(plan, assistance: assistance);
        final checkpoint = PendingQuizAnswer(
          planId: plan.id,
          questionOrdinal: 0,
          assistance: assistance,
          answer: answer,
        );
        final restored =
            QuizCheckpoint.parse(checkpoint.stableSerialization, plan: plan)
                as PendingQuizAnswer;
        final command = restored.answer.toCommand(sessionId: 'session:one');
        expect(command.id, 'attempt:one');
        expect(command.ownerId, 'owner:one');
        expect(command.occurredAtUtc.millisecondsSinceEpoch, 50);
        expect(command.isCorrect, isTrue);
        expect(restored.answer.selectedOptionOrdinal, 1);
        expect(command.responseTimeMs, isNull);
        expect(
          command.evidenceContext.toJson(),
          answer.evidenceContext.toJson(),
        );
        expect(command.evidenceContext.hintLevel, 1);
        expect(
          command.evidenceContext.evidenceClass,
          EvidenceClass.guidedPractice,
        );
      },
    );

    test('revealed answer has a durable receipt and cannot become correct', () {
      final plan = _plan();
      final assistance = QuizAssistance().withReveal(50);
      final answer = _answer(
        plan,
        assistance: assistance,
        revealed: true,
        selected: null,
      );
      expect(answer.isCorrect, isFalse);
      expect(answer.evidenceContext.hintLevel, 2);
      final checkpoint = PendingQuizAnswer(
        planId: plan.id,
        questionOrdinal: 0,
        assistance: assistance,
        answer: answer,
      );
      expect(
        QuizCheckpoint.parse(checkpoint.stableSerialization, plan: plan),
        isA<PendingQuizAnswer>(),
      );
    });

    test(
      'unassisted response remains recognition and ordinal determines correctness',
      () {
        final answer = _answer(_plan(), selected: 0);
        expect(answer.isCorrect, isFalse);
        expect(answer.evidenceContext.evidenceClass, EvidenceClass.recognition);
        expect(answer.evidenceContext.hintLevel, 0);
      },
    );

    test('reveal without durable assistance receipt is rejected', () {
      expect(
        () => _answer(_plan(), revealed: true, selected: null),
        throwsFormatException,
      );
    });

    test(
      'answer under an altered option ordinal cannot use original correctness',
      () {
        final plan = _plan();
        final checkpoint = PendingQuizAnswer(
          planId: plan.id,
          questionOrdinal: 0,
          assistance: QuizAssistance(),
          answer: _answer(plan),
        );
        final body =
            jsonDecode(checkpoint.stableSerialization) as Map<String, dynamic>;
        (body['answer'] as Map<String, dynamic>)['selectedOptionOrdinal'] = 0;
        expect(
          () => QuizCheckpoint.parse(jsonEncode(body), plan: plan),
          throwsFormatException,
        );
      },
    );

    test('pending evidence cannot clear previous hint use', () {
      final plan = _plan();
      final checkpoint = PendingQuizAnswer(
        planId: plan.id,
        questionOrdinal: 0,
        assistance: QuizAssistance().showHint(10),
        answer: _answer(plan, assistance: QuizAssistance().showHint(10)),
      );
      final body =
          jsonDecode(checkpoint.stableSerialization) as Map<String, dynamic>;
      final context =
          ((body['answer'] as Map<String, dynamic>)['evidenceContext']
              as Map<String, dynamic>);
      context['hintLevel'] = 0;
      context['evidenceClass'] = 'recognition';
      expect(
        () => QuizCheckpoint.parse(jsonEncode(body), plan: plan),
        throwsFormatException,
      );
    });

    test(
      'checkpoint rejects wrong plan, unknown phase, missing keys and out-of-range cursor',
      () {
        final plan = _plan();
        final original =
            jsonDecode(QuizCheckpoint.initial(plan).stableSerialization)
                as Map<String, dynamic>;
        for (final change in <void Function(Map<String, dynamic>)>[
          (body) => body['planId'] = 'quiz-plan:${'0' * 64}',
          (body) => body['phase'] = 'pretendCompleted',
          (body) => body.remove('answer'),
          (body) => body['questionOrdinal'] = 9,
        ]) {
          final body = Map<String, dynamic>.of(original);
          change(body);
          expect(
            () => QuizCheckpoint.parse(jsonEncode(body), plan: plan),
            throwsFormatException,
          );
        }
      },
    );

    test('terminal checkpoints retain original close identity and time', () {
      final plan = _plan();
      final close = QuizCloseReceipt(
        capturedOwnerId: 'owner:one',
        endedAtUtcMs: 90,
      );
      for (final checkpoint in <QuizCheckpoint>[
        ClosingQuizSession(
          planId: plan.id,
          questionOrdinal: 0,
          assistance: QuizAssistance(),
          close: close,
        ),
        CompletedQuizSession(
          planId: plan.id,
          questionOrdinal: 0,
          assistance: QuizAssistance(),
          close: close,
        ),
        AbandonedQuizSession(
          planId: plan.id,
          questionOrdinal: 0,
          assistance: QuizAssistance(),
          close: close,
        ),
      ]) {
        final restored = QuizCheckpoint.parse(
          checkpoint.stableSerialization,
          plan: plan,
        );
        expect(restored.phase, checkpoint.phase);
        expect(restored.stableSerialization, checkpoint.stableSerialization);
      }
    });

    test(
      'unexpected answer in awaiting state and invalid assistance are rejected',
      () {
        final plan = _plan();
        final body =
            jsonDecode(QuizCheckpoint.initial(plan).stableSerialization)
                as Map<String, dynamic>;
        body['answer'] = _answer(plan).toJson();
        expect(
          () => QuizCheckpoint.parse(jsonEncode(body), plan: plan),
          throwsFormatException,
        );
        expect(() => QuizAssistance(hintVisible: true), throwsFormatException);
        expect(
          () =>
              QuizCloseReceipt(capturedOwnerId: 'owner:one', endedAtUtcMs: -1),
          throwsFormatException,
        );
      },
    );
  });
}

AcceptedQuizPlan _plan() => AcceptedQuizPlan.create(
  configuration: QuizConfiguration.category(limit: 2),
  questions: [_question()],
);

QuizQuestion _question({
  String id = 'word:polish',
  String spelling = 'Polish',
  String meaning = 'ภาษาโปแลนด์',
  List<String> options = const ['ขัดเงา', 'ภาษาโปแลนด์'],
}) => QuizQuestion(
  word: QuizWord(
    id: id,
    categoryId: 'category:languages',
    spelling: spelling,
    meaning: meaning,
    partOfSpeech: 'noun',
    contentRevision: 'local-vocabulary-v1:7',
  ),
  options: options,
);

QuizAnswerReceipt _answer(
  AcceptedQuizPlan plan, {
  QuizAssistance? assistance,
  bool revealed = false,
  int? selected = 1,
}) => QuizAnswerReceipt.capture(
  plan: plan,
  ownerId: 'owner:one',
  attemptId: 'attempt:one',
  questionOrdinal: 0,
  selectedOptionOrdinal: selected,
  revealed: revealed,
  assistance: assistance ?? QuizAssistance(),
  occurredAtUtcMs: 50,
  responseTimeMs: null,
);

String _id(String json) => 'quiz-plan:${sha256.convert(utf8.encode(json))}';
