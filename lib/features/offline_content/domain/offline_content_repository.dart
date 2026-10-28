import '../../learning_packs/domain/content_manifest.dart';
import 'offline_content_state.dart';

final class VerifiedDownloadedArtifact {
  VerifiedDownloadedArtifact({
    required this.manifest,
    required this.localPath,
    required this.byteLength,
    required this.totalInstalledBytes,
    required this.checksumSha256,
    required this.verifiedAtUtc,
  }) {
    if (localPath.isEmpty ||
        byteLength <= 0 ||
        totalInstalledBytes < byteLength ||
        checksumSha256 != manifest.checksumSha256 ||
        byteLength != manifest.byteLength ||
        !verifiedAtUtc.isUtc) {
      throw ArgumentError('invalid verified downloaded artifact');
    }
  }

  final ContentManifest manifest;
  final String localPath;
  final int byteLength;
  final int totalInstalledBytes;
  final String checksumSha256;
  final DateTime verifiedAtUtc;
}

abstract interface class OfflineContentRepository {
  Future<ContentManifest> requireManifest(ContentIdentity identity);

  Future<List<OfflineContentState>> catalog();

  Future<OfflineContentState> state(ContentIdentity identity);

  Future<void> markDownloading(
    ContentManifest manifest, {
    required int downloadedBytes,
    required DateTime updatedAtUtc,
  });

  Future<void> markFailure(
    ContentManifest manifest, {
    required OfflineContentStatus status,
    required OfflineContentFailureCode failureCode,
    required int downloadedBytes,
    required DateTime updatedAtUtc,
  });

  Future<void> persistVerified(VerifiedDownloadedArtifact artifact);

  Future<void> markNotDownloaded(
    ContentManifest manifest, {
    required DateTime updatedAtUtc,
  });
}

/// Read-only lease over the existing learning/assessment authorities. The
/// lease must serialize the final pin check with the durable removal state
/// transition; callers cannot supply or override the pin set.
abstract interface class OfflineContentRemovalAuthority {
  Future<bool> isRequired(ContentIdentity identity);

  Future<T> withRemovalLease<T>(
    ContentIdentity identity,
    Future<T> Function() operation,
  );
}

/// Explicit test/standalone authority for compositions with no session store.
/// Production bootstrap uses the Drift-backed authority.
final class UnpinnedOfflineContentRemovalAuthority
    implements OfflineContentRemovalAuthority {
  const UnpinnedOfflineContentRemovalAuthority();

  @override
  Future<bool> isRequired(ContentIdentity identity) async => false;

  @override
  Future<T> withRemovalLease<T>(
    ContentIdentity identity,
    Future<T> Function() operation,
  ) => operation();
}
