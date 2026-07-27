/// Thrown when the Supabase client configuration is missing or malformed.
///
/// Rejected values are never included in the error text.
final class SupabaseConfigurationException implements Exception {
  const SupabaseConfigurationException();

  @override
  String toString() => 'Invalid Supabase configuration.';
}

final RegExp _publishableKeyPattern = RegExp(
  r'^sb_publishable_[A-Za-z0-9_-]+$',
);

/// Returns [value] unchanged when it is a current Supabase publishable key.
String requireSupabasePublishableKey(String value) {
  if (!_publishableKeyPattern.hasMatch(value)) {
    throw const SupabaseConfigurationException();
  }
  return value;
}
