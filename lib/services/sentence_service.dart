import 'package:flutter/foundation.dart';

import '../ai/ai_models.dart';
import '../ai/ai_service_factory.dart';
import '../ai/content_provider.dart';
import '../models/sentence_model.dart';

/// Generates example sentences for a target word using the LexiQuest AI
/// content pipeline (LexiQuest-LM, or any OpenAI-compatible endpoint).
///
/// History: this previously called a hardcoded ngrok-hosted sentence API with
/// no auth, no error typing, and a developer's tunnel URL baked into source.
/// It now goes through [ManagedAiService] so:
///
/// - authentication uses the signed-in user's Firebase ID token,
/// - the base URL is supplied at build time via `LEXIQUEST_AI_API_URL`,
/// - failures are typed [AiFailure]s the UI can react to,
/// - the same content cache that serves every other AI feature also serves
///   the fill-in-the-blanks screen, so quota is shared (not double-spent).
class SentenceService {
  /// Default provider used by [fetchSentence]. Call [disposeDefault] once at
  /// app shutdown (e.g. from the top-level widget's `dispose`).
  static ManagedAiService? _default;
  static ManagedAiService get _instance => _default ??= AiServiceFactory.create();

  /// Generate one example sentence for [word] at A2 level (the level the
  /// fill-in-the-blanks screen expects; the screen is an A2 exercise).
  ///
  /// Returns `null` on any failure so existing call sites keep working
  /// unchanged. Failures are logged via [debugPrint] (the exception type
  /// only — never the request text, token, or response body).
  static Future<SentenceModel?> fetchSentence(
    String word, {
    CefrLevel cefr = CefrLevel.a2,
  }) async {
    try {
      final response = await _instance.generate(
        ContentRequest.create(text: word, kind: ContentKind.sentence, cefr: cefr),
      );
      return SentenceModel.fromJson(response.text);
    } on AiFailure catch (failure) {
      debugPrint('SentenceService: ${failure.category.name} - ${failure.message}');
      return null;
    } on Object catch (error) {
      debugPrint('SentenceService: ${error.runtimeType}');
      return null;
    }
  }

  /// Generate one example sentence via an injected provider.
  ///
  /// Screens that already own an [AiServiceFactory]-built provider (e.g. the
  /// AI tutor screen) should use this so they do not spin up a second HTTP
  /// client. Tests inject a fake [ContentProvider] here.
  static Future<SentenceModel?> fetchSentenceWith(
    ContentProvider provider,
    String word, {
    CefrLevel cefr = CefrLevel.a2,
  }) async {
    try {
      final response = await provider.generate(
        ContentRequest.create(text: word, kind: ContentKind.sentence, cefr: cefr),
      );
      return SentenceModel.fromJson(response.text);
    } on AiFailure catch (failure) {
      debugPrint('SentenceService: ${failure.category.name} - ${failure.message}');
      return null;
    } on Object catch (error) {
      debugPrint('SentenceService: ${error.runtimeType}');
      return null;
    }
  }

  /// Release the default provider's HTTP client. Safe to call multiple times.
  static Future<void> disposeDefault() async {
    final instance = _default;
    _default = null;
    await instance?.dispose();
  }
}
