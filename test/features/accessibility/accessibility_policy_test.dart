import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/accessibility/domain/accessibility_policy.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';

void main() {
  group('AccessibilityPolicy', () {
    test(
      'canonical declarations cover each current lesson mode exactly once',
      () {
        final policy = AccessibilityPolicy.canonical();

        expect(policy.declarations, hasLength(LessonMode.values.length));
        expect(policy.declarations.keys.toSet(), LessonMode.values.toSet());
        expect(
          () => policy.declarations[LessonMode.meaningQuiz] = _declaration(
            LessonMode.meaningQuiz,
          ),
          throwsUnsupportedError,
        );
      },
    );

    test('requires the canonical semantic order and explicit alternatives', () {
      final policy = AccessibilityPolicy(_canonicalDeclarations());

      for (final declaration in policy.declarations.values) {
        expect(declaration.supportsTextScale200, isTrue);
        expect(declaration.semanticOrder, const <AccessibilitySemanticRole>[
          AccessibilitySemanticRole.contextAndProgress,
          AccessibilitySemanticRole.prompt,
          AccessibilitySemanticRole.responseAndInput,
          AccessibilitySemanticRole.feedback,
          AccessibilitySemanticRole.navigation,
        ]);
        expect(declaration.nonColorCue, NonColorCue.textAndIcon);
        expect(
          declaration.reducedMotionBehavior,
          ReducedMotionBehavior.staticEquivalent,
        );
        expect(
          declaration.keyboardSwitchNavigation,
          KeyboardSwitchNavigation.orderedFocusableControls,
        );
        expect(declaration.inputAlternative, isNotNull);
        expect(declaration.mediaAlternative, isNotNull);
      }

      const mediaDependentModes = <LessonMode>{
        LessonMode.flashcard,
        LessonMode.dictation,
        LessonMode.speaking,
        LessonMode.shadowing,
        LessonMode.cefrReading,
        LessonMode.sentenceScramble,
      };
      for (final mode in LessonMode.values) {
        final declaration = policy.declarations[mode]!;
        expect(
          declaration.mediaAlternative ==
              LessonMediaAlternative.noMediaDependency,
          isNot(mediaDependentModes.contains(mode)),
          reason: '$mode must declare its media alternative explicitly',
        );
      }
    });

    test(
      'f38 mode surfaces: unavailable voice modes designate a non-recording alternative activity',
      () {
        final policy = AccessibilityPolicy.canonical();

        for (final mode in const <LessonMode>{
          LessonMode.dictation,
          LessonMode.speaking,
          LessonMode.shadowing,
        }) {
          final declaration = policy.declarations[mode]!;
          expect(
            declaration.mediaAlternative,
            LessonMediaAlternative.alternativeActivity,
            reason:
                '$mode must leave the unavailable media activity instead of '
                'fabricating a transcript or exposing answer text',
          );
          expect(
            declaration.inputAlternative,
            InputAlternative.keyboardReachableControls,
            reason:
                '$mode must retain keyboard/switch controls without treating '
                'typed text as pronunciation or dictation evidence',
          );
        }
      },
    );

    test(
      'f38 review: every canonical mode declares a typed high contrast presentation',
      () {
        final policy = AccessibilityPolicy.canonical();

        for (final mode in LessonMode.values) {
          expect(
            policy.declarations[mode]!.highContrastBehavior,
            HighContrastBehavior.platformTheme,
            reason:
                '$mode must opt into a concrete platform high-contrast theme '
                'instead of merely observing a flag',
          );
        }
      },
    );

    test('rejects missing, duplicate, and contradictory declarations', () {
      final declarations = _canonicalDeclarations();

      expect(
        () => AccessibilityPolicy(
          declarations.where(
            (declaration) => declaration.mode != LessonMode.wordScramble,
          ),
        ),
        throwsA(isA<AccessibilityPolicyValidationException>()),
      );
      expect(
        () => AccessibilityPolicy(<LessonModeAccessibilityDeclaration>[
          ...declarations,
          _declaration(LessonMode.meaningQuiz),
        ]),
        throwsA(isA<AccessibilityPolicyValidationException>()),
      );
      expect(
        () => AccessibilityPolicy(<LessonModeAccessibilityDeclaration>[
          ...declarations.where(
            (declaration) => declaration.mode != LessonMode.cloze,
          ),
          _declaration(
            LessonMode.cloze,
            semanticOrder: const <AccessibilitySemanticRole>[
              AccessibilitySemanticRole.prompt,
              AccessibilitySemanticRole.contextAndProgress,
              AccessibilitySemanticRole.responseAndInput,
              AccessibilitySemanticRole.feedback,
              AccessibilitySemanticRole.navigation,
            ],
          ),
        ]),
        throwsA(isA<AccessibilityPolicyValidationException>()),
      );
    });

    test(
      'fails closed when untimed metadata conflicts with canonical adapter capabilities',
      () {
        final registry = buildLessonModeRegistry();
        final before = <LessonMode, LessonModeDeliveryState>{
          for (final registration in registry.registrations)
            registration.mode: registration.deliveryState,
        };
        final policy = AccessibilityPolicy(
          _canonicalDeclarations(
            untimedOverride: <LessonMode, bool>{LessonMode.matching: false},
          ),
        );

        expect(
          () => policy.validateAgainst(registry),
          throwsA(isA<AccessibilityPolicyValidationException>()),
        );
        expect(
          <LessonMode, LessonModeDeliveryState>{
            for (final registration in registry.registrations)
              registration.mode: registration.deliveryState,
          },
          before,
          reason:
              'accessibility validation is a release gate, not a delivery, '
              'session, or evidence authority',
        );
      },
    );
  });
}

List<LessonModeAccessibilityDeclaration> _canonicalDeclarations({
  Map<LessonMode, bool> untimedOverride = const <LessonMode, bool>{},
}) => <LessonModeAccessibilityDeclaration>[
  for (final mode in LessonMode.values)
    _declaration(
      mode,
      supportsUntimedAlternative: untimedOverride[mode] ?? true,
    ),
];

LessonModeAccessibilityDeclaration _declaration(
  LessonMode mode, {
  List<AccessibilitySemanticRole> semanticOrder =
      const <AccessibilitySemanticRole>[
        AccessibilitySemanticRole.contextAndProgress,
        AccessibilitySemanticRole.prompt,
        AccessibilitySemanticRole.responseAndInput,
        AccessibilitySemanticRole.feedback,
        AccessibilitySemanticRole.navigation,
      ],
  bool supportsUntimedAlternative = true,
}) => LessonModeAccessibilityDeclaration(
  mode: mode,
  supportsTextScale200: true,
  semanticOrder: semanticOrder,
  modeOwnedSemanticRoles: const <AccessibilitySemanticRole>{
    AccessibilitySemanticRole.prompt,
    AccessibilitySemanticRole.responseAndInput,
    AccessibilitySemanticRole.navigation,
  },
  nonColorCue: NonColorCue.textAndIcon,
  highContrastBehavior: HighContrastBehavior.platformTheme,
  reducedMotionBehavior: ReducedMotionBehavior.staticEquivalent,
  keyboardSwitchNavigation: KeyboardSwitchNavigation.orderedFocusableControls,
  supportsUntimedAlternative: supportsUntimedAlternative,
  inputAlternative: switch (mode) {
    LessonMode.handwritingScratchpad => InputAlternative.typedTextFallback,
    LessonMode.matching ||
    LessonMode.sentenceScramble ||
    LessonMode.wordScramble => InputAlternative.keyboardSelectableControls,
    LessonMode.dictation ||
    LessonMode.speaking ||
    LessonMode.shadowing => InputAlternative.keyboardReachableControls,
    _ => InputAlternative.keyboardReachableControls,
  },
  mediaAlternative: switch (mode) {
    LessonMode.dictation ||
    LessonMode.speaking ||
    LessonMode.shadowing => LessonMediaAlternative.alternativeActivity,
    LessonMode.flashcard ||
    LessonMode.cefrReading ||
    LessonMode.sentenceScramble => LessonMediaAlternative.visibleTextWithReplay,
    _ => LessonMediaAlternative.noMediaDependency,
  },
);
