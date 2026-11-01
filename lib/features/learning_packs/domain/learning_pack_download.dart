import 'learning_pack.dart';
import 'learning_pack_repository.dart';

final class LearningPackDownloadDescriptor {
  LearningPackDownloadDescriptor({
    required this.catalogId,
    required this.manifest,
    required this.uri,
    required this.packageSha256,
    required this.packageByteCount,
  }) {
    PackSourceDescriptor.configuredCatalog(catalogId);
    final host = uri.host.toLowerCase();
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.port != 443 ||
        uri.toString().length > 2048 ||
        !RegExp(r'^(?:[a-z0-9][a-z0-9-]*\.)+[a-z][a-z0-9-]*$').hasMatch(host) ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(packageSha256) ||
        packageByteCount < 1 ||
        packageByteCount > maxLearningPackBytes) {
      throw const PackStorageException(PackStorageFailureCode.invalid);
    }
  }
  final String catalogId;
  final LearningPackManifest manifest;
  final Uri uri;
  final String packageSha256;
  final int packageByteCount;
}
