import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../learning_packs/domain/content_manifest.dart';

enum OfflineContentStatus {
  notDownloaded,
  downloading,
  verified,
  interrupted,
  quarantined,
}

enum OfflineContentFailureCode {
  checksumMismatch,
  sizeMismatch,
  revisionMismatch,
  missingArtifact,
  unsupportedContent,
  contentInUse,
  interrupted,
  invalidState,
}

/// Canonical app-private artifact names. The digest input is a sequence of
/// length-prefixed UTF-8 fields, so distinct identity tuples cannot collapse
/// through delimiter ambiguity.
final class OfflineContentArtifactKey {
  OfflineContentArtifactKey._(this.digest);

  final String digest;

  String get publishedName => '$digest.content';
  String get partialName => '$digest.partial';

  static OfflineContentArtifactKey forManifest(ContentManifest manifest) {
    requireCanonicalIdentity(manifest.identity);
    _requireCanonicalPathField(manifest.storageId, 'manifest.storageId');
    final fields = <String>[
      manifest.storageId,
      manifest.identity.type.name,
      manifest.identity.id,
      manifest.identity.revision.toString(),
    ];
    final bytes = BytesBuilder(copy: false);
    for (final field in fields) {
      final encoded = utf8.encode(field);
      final length = ByteData(4)..setUint32(0, encoded.length, Endian.big);
      bytes
        ..add(length.buffer.asUint8List())
        ..add(encoded);
    }
    return OfflineContentArtifactKey._(
      sha256.convert(bytes.takeBytes()).toString(),
    );
  }

  static void requireCanonicalIdentity(ContentIdentity identity) {
    _requireCanonicalPathField(identity.id, 'identity.id');
    if (identity.revision <= 0) {
      throw ArgumentError.value(identity.revision, 'identity.revision');
    }
  }

  static bool isCanonicalPublishedName(String value) =>
      _artifactName.hasMatch(value);
}

final class OfflineContentFailure implements Exception {
  const OfflineContentFailure(this.code, [this.cause]);

  final OfflineContentFailureCode code;
  final Object? cause;

  @override
  String toString() => 'OfflineContentFailure(${code.name})';
}

final class OfflineContentState {
  OfflineContentState({
    required this.manifestId,
    required this.identity,
    required this.status,
    required this.localPath,
    required this.downloadedBytes,
    required this.verifiedChecksumSha256,
    required this.failureCode,
    required this.updatedAtUtc,
  }) {
    if (!_canonicalText(manifestId) ||
        !_canonicalText(identity.id) ||
        identity.revision <= 0 ||
        downloadedBytes < 0 ||
        !updatedAtUtc.isUtc ||
        updatedAtUtc.millisecondsSinceEpoch < 0) {
      throw ArgumentError('invalid offline content state');
    }
    final isVerified = status == OfflineContentStatus.verified;
    final path = localPath;
    final checksum = verifiedChecksumSha256;
    if (isVerified !=
            (path != null &&
                path.isNotEmpty &&
                downloadedBytes > 0 &&
                checksum != null) ||
        (path != null &&
            !OfflineContentArtifactKey.isCanonicalPublishedName(path)) ||
        (checksum != null && !_sha256.hasMatch(checksum)) ||
        (!isVerified && (path != null || checksum != null)) ||
        ((status == OfflineContentStatus.quarantined ||
                status == OfflineContentStatus.interrupted) !=
            (failureCode != null)) ||
        (status == OfflineContentStatus.notDownloaded &&
            (localPath != null ||
                downloadedBytes != 0 ||
                verifiedChecksumSha256 != null))) {
      throw ArgumentError('inconsistent offline content state');
    }
  }

  final String manifestId;
  final ContentIdentity identity;
  final OfflineContentStatus status;
  final String? localPath;
  final int downloadedBytes;
  final String? verifiedChecksumSha256;
  final OfflineContentFailureCode? failureCode;
  final DateTime updatedAtUtc;

  bool get canDownload =>
      status == OfflineContentStatus.notDownloaded ||
      status == OfflineContentStatus.interrupted ||
      status == OfflineContentStatus.quarantined;

  bool get hasVerifiedBytes => status == OfflineContentStatus.verified;
}

bool _canonicalText(String value) =>
    value.isNotEmpty &&
    value == value.trim() &&
    value.runes.length <= 256 &&
    !value.runes.any((rune) => rune < 0x20 || rune == 0x7f);

void _requireCanonicalPathField(String value, String name) {
  if (!_canonicalText(value) || value.contains('/') || value.contains('\\')) {
    throw ArgumentError.value(value, name, 'must be a canonical identifier');
  }
}

final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _artifactName = RegExp(r'^[0-9a-f]{64}\.content$');
