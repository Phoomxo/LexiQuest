/// Closed schema-12 ownership contract for the mixed `runtime_flags` table.
///
/// Every subsystem that reads or writes one of these namespaces must consume
/// these constants so lifecycle export/deletion coverage cannot drift from
/// the operational key format.
abstract final class RuntimeFlagNamespaces {
  static const ownerOperationGate = 'ownerOperationGate';
  static const cloudSyncEnabled = 'cloudSyncEnabled';
  static const featureEmergencyOffPrefix = 'feature_emergency_off:';
  static const downloadCountPrefix = 'download_count:';
  static const downloadCounterSource = 'download_counter';
  static const aiCredentialPointerPrefix = 'aiCredentialPointer:';
  static const aiCredentialIntentPrefix = 'aiCredentialIntent:';

  /// Upper bound for a binary SQLite prefix range whose delimiter is `:`.
  static String prefixUpperBound(String prefix) {
    if (!prefix.endsWith(':')) {
      throw ArgumentError.value(prefix, 'prefix', 'must end with a colon');
    }
    return '${prefix.substring(0, prefix.length - 1)};';
  }
}
