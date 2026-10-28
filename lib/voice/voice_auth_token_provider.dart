import 'package:firebase_auth/firebase_auth.dart';

import 'voice_models.dart';

/// Boundary for acquiring a Firebase ID token for OmniVoice requests.
abstract interface class VoiceAuthTokenProvider {
  Future<String> getIdToken({bool forceRefresh = false});
}

/// Decouples token-provider tests from the Firebase plugin.
abstract interface class FirebaseTokenReader {
  Future<String?> readIdToken({required bool forceRefresh});
}

/// Production token reader backed by an injected-or-default [FirebaseAuth].
final class FirebaseAuthTokenReader implements FirebaseTokenReader {
  FirebaseAuthTokenReader({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  @override
  Future<String?> readIdToken({required bool forceRefresh}) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return null;
    }
    return user.getIdToken(forceRefresh);
  }
}

const _authenticationFailure = VoiceFailure(
  category: VoiceFailureCategory.authentication,
  message: 'Voice authentication is unavailable.',
);

/// Converts missing tokens and reader failures to one privacy-safe failure.
final class FirebaseVoiceAuthTokenProvider implements VoiceAuthTokenProvider {
  FirebaseVoiceAuthTokenProvider(this._reader);

  final FirebaseTokenReader _reader;

  @override
  Future<String> getIdToken({bool forceRefresh = false}) async {
    final String? token;
    try {
      token = await _reader.readIdToken(forceRefresh: forceRefresh);
    } on Object {
      throw _authenticationFailure;
    }

    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      throw _authenticationFailure;
    }
    return trimmed;
  }
}
