import '../../learning/application/lesson_mode_registry.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../learning/domain/session_configuration.dart';

/// The required semantic order for every lesson-mode presentation.
enum AccessibilitySemanticRole {
  contextAndProgress,
  prompt,
  responseAndInput,
  feedback,
  navigation,
}

/// A non-color indication must accompany meaning-bearing visual state.
enum NonColorCue { textAndIcon, unavailable }

/// The concrete presentation used when platform high contrast is active.
enum HighContrastBehavior { platformTheme, unavailable }

/// The equivalent presentation when platform motion reduction is active.
enum ReducedMotionBehavior { staticEquivalent, unavailable }

/// The focus behavior required for keyboard and switch access.
enum KeyboardSwitchNavigation { orderedFocusableControls, unavailable }

/// An explicit non-primary way to enter or select a response.
enum InputAlternative {
  keyboardReachableControls,
  keyboardSelectableControls,
  typedTextFallback,
  typedTranscriptFallback,
  unavailable,
}

/// The declared alternative for a mode that uses audio or speech media.
enum LessonMediaAlternative {
  noMediaDependency,
  visibleTextWithReplay,
  typedTranscriptFallback,
  alternativeActivity,
  unavailable,
}

/// Fail-closed validation error for accessibility release-gate metadata.
final class AccessibilityPolicyValidationException implements Exception {
  const AccessibilityPolicyValidationException(this.message);

  final String message;

  @override
  String toString() => 'AccessibilityPolicyValidationException: $message';
}

/// Immutable presentation metadata for one canonical lesson mode.
final class LessonModeAccessibilityDeclaration {
  LessonModeAccessibilityDeclaration({
    required this.mode,
    required this.supportsTextScale200,
    required Iterable<AccessibilitySemanticRole> semanticOrder,
    required Iterable<AccessibilitySemanticRole> modeOwnedSemanticRoles,
    required this.nonColorCue,
    required this.highContrastBehavior,
    required this.reducedMotionBehavior,
    required this.keyboardSwitchNavigation,
    required this.supportsUntimedAlternative,
    required this.inputAlternative,
    required this.mediaAlternative,
  }) : semanticOrder = List<AccessibilitySemanticRole>.unmodifiable(
         semanticOrder,
       ),
       modeOwnedSemanticRoles = Set<AccessibilitySemanticRole>.unmodifiable(
         modeOwnedSemanticRoles,
       );

  final LessonMode mode;
  final bool supportsTextScale200;
  final List<AccessibilitySemanticRole> semanticOrder;
  final Set<AccessibilitySemanticRole> modeOwnedSemanticRoles;
  final NonColorCue nonColorCue;
  final HighContrastBehavior highContrastBehavior;
  final ReducedMotionBehavior reducedMotionBehavior;
  final KeyboardSwitchNavigation keyboardSwitchNavigation;
  final bool supportsUntimedAlternative;
  final InputAlternative inputAlternative;
  final LessonMediaAlternative mediaAlternative;
}

/// Pure release-gate metadata for accessible lesson-mode presentation.
///
/// This policy intentionally has no route, session, evidence, score, or
/// persistence authority. It validates the canonical adapter declarations but
/// never changes registry delivery state.
final class AccessibilityPolicy {
  AccessibilityPolicy(Iterable<LessonModeAccessibilityDeclaration> values)
    : declarations = _validatedDeclarations(values);

  factory AccessibilityPolicy.canonical() =>
      AccessibilityPolicy(<LessonModeAccessibilityDeclaration>[
        _canonicalDeclaration(LessonMode.associativeReading),
        _canonicalDeclaration(LessonMode.meaningQuiz),
        _canonicalDeclaration(LessonMode.typedRecall),
        _canonicalDeclaration(LessonMode.definitionQuiz),
        _canonicalDeclaration(LessonMode.cloze),
        _canonicalDeclaration(LessonMode.matching),
        _canonicalDeclaration(LessonMode.flashcard),
        _canonicalDeclaration(LessonMode.handwritingScratchpad),
        _canonicalDeclaration(LessonMode.dictation),
        _canonicalDeclaration(LessonMode.speaking),
        _canonicalDeclaration(LessonMode.shadowing),
        _canonicalDeclaration(LessonMode.cefrReading),
        _canonicalDeclaration(LessonMode.sentenceScramble),
        _canonicalDeclaration(LessonMode.wordScramble),
      ]);

  final Map<LessonMode, LessonModeAccessibilityDeclaration> declarations;

  /// Validates that this presentation metadata remains aligned with the typed
  /// configuration capabilities of the current canonical lesson registry.
  ///
  /// The method only reads [registry]. A mismatch is a release-gate failure;
  /// it never hides a mode or mutates delivery/session/evidence state.
  void validateAgainst(LessonModeRegistry registry) {
    final registrations = registry.registrations.toList(growable: false);
    final registeredModes = registrations
        .map((registration) => registration.mode)
        .toSet();
    if (!_sameModes(registeredModes, LessonMode.values.toSet())) {
      throw const AccessibilityPolicyValidationException(
        'canonical lesson registry must contain every declared lesson mode',
      );
    }

    for (final registration in registrations) {
      final adapter = registration.adapter;
      if (adapter is! SessionConfigurableLessonModeAdapter) {
        throw AccessibilityPolicyValidationException(
          '${registration.mode} does not expose typed session capabilities',
        );
      }
      final declaration = declarations[registration.mode];
      if (declaration == null) {
        throw AccessibilityPolicyValidationException(
          '${registration.mode} has no accessibility declaration',
        );
      }
      if (declaration.supportsUntimedAlternative !=
          adapter.sessionConfigurationCapabilities.supportsUntimedAlternative) {
        throw AccessibilityPolicyValidationException(
          '${registration.mode} untimed accessibility metadata conflicts '
          'with its canonical adapter capability',
        );
      }
    }
  }

  static Map<LessonMode, LessonModeAccessibilityDeclaration>
  _validatedDeclarations(Iterable<LessonModeAccessibilityDeclaration> values) {
    final indexed = <LessonMode, LessonModeAccessibilityDeclaration>{};
    for (final declaration in values) {
      if (indexed.containsKey(declaration.mode)) {
        throw AccessibilityPolicyValidationException(
          'duplicate accessibility declaration for ${declaration.mode}',
        );
      }
      _validateDeclaration(declaration);
      indexed[declaration.mode] = declaration;
    }
    if (!_sameModes(indexed.keys.toSet(), LessonMode.values.toSet())) {
      throw const AccessibilityPolicyValidationException(
        'accessibility declarations must cover the exact canonical lesson '
        'mode set',
      );
    }
    return Map<LessonMode, LessonModeAccessibilityDeclaration>.unmodifiable(
      indexed,
    );
  }

  static void _validateDeclaration(
    LessonModeAccessibilityDeclaration declaration,
  ) {
    if (!declaration.supportsTextScale200) {
      throw AccessibilityPolicyValidationException(
        '${declaration.mode} must support 200% text scaling',
      );
    }
    if (!_sameSemanticOrder(declaration.semanticOrder)) {
      throw AccessibilityPolicyValidationException(
        '${declaration.mode} must use the canonical semantic order',
      );
    }
    if (!_sameSemanticRoles(
      declaration.modeOwnedSemanticRoles,
      _canonicalModeOwnedSemanticRoles,
    )) {
      throw AccessibilityPolicyValidationException(
        '${declaration.mode} must assign prompt, response/input, and '
        'navigation to its production mode surface only',
      );
    }
    if (declaration.nonColorCue != NonColorCue.textAndIcon ||
        declaration.highContrastBehavior !=
            HighContrastBehavior.platformTheme ||
        declaration.reducedMotionBehavior !=
            ReducedMotionBehavior.staticEquivalent ||
        declaration.keyboardSwitchNavigation !=
            KeyboardSwitchNavigation.orderedFocusableControls ||
        declaration.inputAlternative == InputAlternative.unavailable ||
        declaration.mediaAlternative == LessonMediaAlternative.unavailable) {
      throw AccessibilityPolicyValidationException(
        '${declaration.mode} is missing a required accessibility alternative '
        'or cue',
      );
    }
    if (declaration.inputAlternative !=
        _canonicalInputAlternative(declaration.mode)) {
      throw AccessibilityPolicyValidationException(
        '${declaration.mode} input alternative is not canonical',
      );
    }
    if (declaration.mediaAlternative !=
        _canonicalMediaAlternative(declaration.mode)) {
      throw AccessibilityPolicyValidationException(
        '${declaration.mode} media alternative is not canonical',
      );
    }
  }

  static bool _sameModes(Set<LessonMode> left, Set<LessonMode> right) =>
      left.length == right.length && left.containsAll(right);

  static const Set<AccessibilitySemanticRole> _canonicalModeOwnedSemanticRoles =
      <AccessibilitySemanticRole>{
        AccessibilitySemanticRole.prompt,
        AccessibilitySemanticRole.responseAndInput,
        AccessibilitySemanticRole.navigation,
      };

  static bool _sameSemanticRoles(
    Set<AccessibilitySemanticRole> left,
    Set<AccessibilitySemanticRole> right,
  ) => left.length == right.length && left.containsAll(right);

  static bool _sameSemanticOrder(Iterable<AccessibilitySemanticRole> value) {
    const expected = <AccessibilitySemanticRole>[
      AccessibilitySemanticRole.contextAndProgress,
      AccessibilitySemanticRole.prompt,
      AccessibilitySemanticRole.responseAndInput,
      AccessibilitySemanticRole.feedback,
      AccessibilitySemanticRole.navigation,
    ];
    final actual = value.toList(growable: false);
    if (actual.length != expected.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  static LessonModeAccessibilityDeclaration _canonicalDeclaration(
    LessonMode mode,
  ) => switch (mode) {
    LessonMode.associativeReading => _buildCanonicalDeclaration(mode),
    LessonMode.meaningQuiz => _buildCanonicalDeclaration(mode),
    LessonMode.typedRecall => _buildCanonicalDeclaration(mode),
    LessonMode.definitionQuiz => _buildCanonicalDeclaration(mode),
    LessonMode.cloze => _buildCanonicalDeclaration(mode),
    LessonMode.matching => _buildCanonicalDeclaration(mode),
    LessonMode.flashcard => _buildCanonicalDeclaration(mode),
    LessonMode.handwritingScratchpad => _buildCanonicalDeclaration(mode),
    LessonMode.dictation => _buildCanonicalDeclaration(mode),
    LessonMode.speaking => _buildCanonicalDeclaration(mode),
    LessonMode.shadowing => _buildCanonicalDeclaration(mode),
    LessonMode.cefrReading => _buildCanonicalDeclaration(mode),
    LessonMode.sentenceScramble => _buildCanonicalDeclaration(mode),
    LessonMode.wordScramble => _buildCanonicalDeclaration(mode),
  };

  static LessonModeAccessibilityDeclaration _buildCanonicalDeclaration(
    LessonMode mode,
  ) => LessonModeAccessibilityDeclaration(
    mode: mode,
    supportsTextScale200: true,
    semanticOrder: const <AccessibilitySemanticRole>[
      AccessibilitySemanticRole.contextAndProgress,
      AccessibilitySemanticRole.prompt,
      AccessibilitySemanticRole.responseAndInput,
      AccessibilitySemanticRole.feedback,
      AccessibilitySemanticRole.navigation,
    ],
    modeOwnedSemanticRoles: _canonicalModeOwnedSemanticRoles,
    nonColorCue: NonColorCue.textAndIcon,
    highContrastBehavior: HighContrastBehavior.platformTheme,
    reducedMotionBehavior: ReducedMotionBehavior.staticEquivalent,
    keyboardSwitchNavigation: KeyboardSwitchNavigation.orderedFocusableControls,
    supportsUntimedAlternative: true,
    inputAlternative: _canonicalInputAlternative(mode),
    mediaAlternative: _canonicalMediaAlternative(mode),
  );

  static InputAlternative _canonicalInputAlternative(LessonMode mode) =>
      switch (mode) {
        LessonMode.handwritingScratchpad => InputAlternative.typedTextFallback,
        LessonMode.matching ||
        LessonMode.sentenceScramble ||
        LessonMode.wordScramble => InputAlternative.keyboardSelectableControls,
        LessonMode.dictation ||
        LessonMode.speaking ||
        LessonMode.shadowing => InputAlternative.keyboardReachableControls,
        LessonMode.associativeReading ||
        LessonMode.meaningQuiz ||
        LessonMode.typedRecall ||
        LessonMode.definitionQuiz ||
        LessonMode.cloze ||
        LessonMode.flashcard ||
        LessonMode.cefrReading => InputAlternative.keyboardReachableControls,
      };

  static LessonMediaAlternative _canonicalMediaAlternative(LessonMode mode) =>
      switch (mode) {
        LessonMode.dictation ||
        LessonMode.speaking ||
        LessonMode.shadowing => LessonMediaAlternative.alternativeActivity,
        LessonMode.flashcard ||
        LessonMode.cefrReading ||
        LessonMode.sentenceScramble =>
          LessonMediaAlternative.visibleTextWithReplay,
        LessonMode.associativeReading ||
        LessonMode.meaningQuiz ||
        LessonMode.typedRecall ||
        LessonMode.definitionQuiz ||
        LessonMode.cloze ||
        LessonMode.matching ||
        LessonMode.handwritingScratchpad ||
        LessonMode.wordScramble => LessonMediaAlternative.noMediaDependency,
      };
}
