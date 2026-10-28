import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../../../voice/standard_voice_pack_download_manager.dart';
import '../../../voice/standard_voice_pack_manifest.dart';
import '../../../voice/voice_models.dart';
import '../application/offline_content_manager.dart';
import '../domain/offline_content_state.dart';

final class OfflineVoicePackManifestCatalog {
  OfflineVoicePackManifestCatalog(
    Map<ContentIdentity, StandardVoicePackManifest> manifests, {
    Map<Uri, Uint8List> packagedFiles = const <Uri, Uint8List>{},
  }) : _manifests =
           Map<ContentIdentity, StandardVoicePackManifest>.unmodifiable(
             manifests,
           ),
       _packagedFiles = Map<Uri, Uint8List>.unmodifiable(<Uri, Uint8List>{
         for (final entry in packagedFiles.entries)
           entry.key: Uint8List.fromList(entry.value),
       }) {
    final recordIds = <String>{};
    final packIds = <String>{};
    final filesByUri = <Uri, StandardVoicePackFile>{};
    for (final entry in _manifests.entries) {
      OfflineContentArtifactKey.requireCanonicalIdentity(entry.key);
      if (entry.key.type != ContentType.offlineArtifact ||
          !recordIds.add(entry.value.recordId) ||
          !packIds.add(entry.value.packId)) {
        throw ArgumentError('Voice content identities must map one-to-one.');
      }
      for (final file in entry.value.files) {
        if (filesByUri[file.uri] != null) {
          throw ArgumentError('Voice file URI must be globally unique.');
        }
        filesByUri[file.uri] = file;
      }
    }
    for (final entry in _packagedFiles.entries) {
      final file = filesByUri[entry.key];
      if (file == null ||
          file.byteSize != entry.value.length ||
          file.sha256 != sha256.convert(entry.value).toString()) {
        throw ArgumentError('Packaged voice bytes must match the manifest.');
      }
    }
  }

  final Map<ContentIdentity, StandardVoicePackManifest> _manifests;
  final Map<Uri, Uint8List> _packagedFiles;

  static const productionIdentity = ContentIdentity(
    type: ContentType.offlineArtifact,
    id: 'voice-installation-check',
    revision: 1,
  );

  static final Uint8List _productionReadinessWav =
      _buildProductionReadinessWav();

  static final StandardVoicePackManifest
  _productionManifest = StandardVoicePackManifest.fromJson(<String, Object>{
    'schemaVersion': 1,
    'packId': 'offline-readiness',
    'version': '1.0.0',
    'locale': 'en',
    'voiceId': 'installation_check',
    'engine': 'voxcpm2',
    'modelVersion': 'packaged-readiness-1',
    'license': 'Apache-2.0',
    'licenseUri': 'https://github.com/OpenBMB/VoxCPM/blob/main/LICENSE',
    'minimumAppVersion': '1.0.0+1',
    'baseUri':
        'https://appassets.lexiquest.invalid/voice/offline-readiness/1.0.0/',
    'generatedAtUtc': '2026-08-30T00:00:00.000Z',
    'totalBytes': _productionReadinessWav.length,
    'files': <Object>[
      <String, Object>{
        'contentId': 'installation-check',
        'normalizedTextSha256': sha256
            .convert(utf8.encode('__lexiquest_voice_installation_check__'))
            .toString(),
        'relativePath': 'diagnostics/installation-check.wav',
        'byteSize': _productionReadinessWav.length,
        'sha256': sha256.convert(_productionReadinessWav).toString(),
      },
    ],
  });

  static final production = OfflineVoicePackManifestCatalog(
    <ContentIdentity, StandardVoicePackManifest>{
      productionIdentity: _productionManifest,
    },
    packagedFiles: <Uri, Uint8List>{
      _productionManifest.files.single.uri: _productionReadinessWav,
    },
  );

  Set<ContentIdentity> get identities =>
      Set<ContentIdentity>.unmodifiable(_manifests.keys);

  Map<Uri, Uint8List> get packagedFiles =>
      Map<Uri, Uint8List>.unmodifiable(<Uri, Uint8List>{
        for (final entry in _packagedFiles.entries)
          entry.key: Uint8List.fromList(entry.value),
      });

  StandardVoicePackManifest? resolve(ContentIdentity identity) =>
      _manifests[identity];

  StandardVoicePackManifest requireManifest(ContentIdentity identity) =>
      resolve(identity) ??
      (throw ArgumentError.value(identity, 'identity', 'unknown voice pack'));

  Uint8List requireReceiptBytes(ContentIdentity identity) => Uint8List.fromList(
    utf8.encode(jsonEncode(requireManifest(identity).toJson())),
  );

  VerifiedContentManifest requireContentArtifact(ContentIdentity identity) {
    final bytes = requireReceiptBytes(identity);
    return VerifiedContentManifest(
      manifest: ContentManifest(
        storageId:
            'manifest:${identity.type.name}:${identity.id}:r${identity.revision}',
        identity: identity,
        checksumSha256: sha256.convert(bytes).toString(),
        byteLength: bytes.length,
        provenance: ContentProvenance.packaged,
        sourceUri:
            'package:vocab_learning_app/voice/${identity.id}/manifest.json',
        reviewState: ContentReviewState.approved,
        publicationState: ContentPublicationState.published,
        createdAtUtc: DateTime.utc(2026, 8, 30),
        reviewedAtUtc: DateTime.utc(2026, 8, 30),
        publishedAtUtc: DateTime.utc(2026, 8, 30),
      ),
      bytes: bytes,
    );
  }

  Uint8List requirePackagedFileBytes(Uri uri) {
    final bytes = _packagedFiles[uri];
    if (bytes == null) {
      throw ArgumentError.value(uri, 'uri', 'not a packaged voice file');
    }
    return Uint8List.fromList(bytes);
  }

  Uint8List? packagedFileBytes(Uri uri) {
    final bytes = _packagedFiles[uri];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }
}

final class CatalogStandardVoicePackSource
    implements StandardVoicePackByteSource {
  const CatalogStandardVoicePackSource({
    required this.catalog,
    required this.fallback,
  });

  final OfflineVoicePackManifestCatalog catalog;
  final StandardVoicePackByteSource fallback;

  @override
  Future<StandardVoicePackByteResponse> open(
    Uri uri, {
    required int start,
    StandardVoicePackCancellation? cancellation,
  }) async {
    final bytes = catalog.packagedFileBytes(uri);
    if (bytes == null) {
      return fallback.open(uri, start: start, cancellation: cancellation);
    }
    if (start < 0 || start > bytes.length) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.network,
        message: 'The packaged voice range is invalid.',
      );
    }
    if (cancellation?.isCancelled == true) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.cancelled,
        message: 'The voice pack download was cancelled.',
      );
    }
    return StandardVoicePackByteResponse(
      statusCode: start == 0 ? 200 : 206,
      contentRangeStart: start == 0 ? null : start,
      bytes: Stream<List<int>>.value(bytes.sublist(start)),
    );
  }
}

/// Adapter over the existing standard voice-pack installer. The f44 artifact
/// is the deterministic verified installation receipt; audio files remain
/// owned and validated by [StandardVoicePackDownloadManager].
final class VoicePackDownloadAdapter implements OfflineContentDownloadAdapter {
  VoicePackDownloadAdapter({required this.manager, required this.catalog});

  final StandardVoicePackDownloadManager manager;
  final OfflineVoicePackManifestCatalog catalog;

  @override
  bool supports(ContentManifest manifest) =>
      manifest.identity.type == ContentType.offlineArtifact &&
      catalog.resolve(manifest.identity) != null;

  @override
  Future<void> stage(ContentManifest manifest, File temporaryFile) async {
    final voiceManifest = catalog.resolve(manifest.identity);
    if (voiceManifest == null) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.revisionMismatch,
      );
    }
    final receipt = utf8.encode(jsonEncode(voiceManifest.toJson()));
    if (receipt.length != manifest.byteLength ||
        sha256.convert(receipt).toString() != manifest.checksumSha256) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.revisionMismatch,
      );
    }
    final installed = await manager.install(
      voiceManifest,
      receiptBytes: manifest.byteLength,
    );
    if (installed.manifest.recordId != voiceManifest.recordId) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.revisionMismatch,
      );
    }
    await requireInstalledValid(manifest);
    await temporaryFile.writeAsBytes(receipt, flush: true);
  }

  @override
  Future<void> requireInstalledValid(ContentManifest manifest) async {
    final voiceManifest = catalog.resolve(manifest.identity);
    if (voiceManifest == null) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.revisionMismatch,
      );
    }
    final receipt = utf8.encode(jsonEncode(voiceManifest.toJson()));
    if (receipt.length != manifest.byteLength ||
        sha256.convert(receipt).toString() != manifest.checksumSha256) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.revisionMismatch,
      );
    }
    final installed = await manager.findVerifiedInstalled(voiceManifest);
    if (installed == null) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.checksumMismatch,
      );
    }
  }

  @override
  Future<int> installedBytes(ContentManifest manifest) async {
    final voiceManifest = catalog.resolve(manifest.identity);
    if (voiceManifest == null) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.revisionMismatch,
      );
    }
    await requireInstalledValid(manifest);
    return manager.installedBytes(voiceManifest);
  }

  @override
  Future<int> removeInstalled(ContentManifest manifest) async {
    final voiceManifest = catalog.resolve(manifest.identity);
    if (voiceManifest == null) return 0;
    return manager.removeInstalled(voiceManifest);
  }
}

Uint8List _buildProductionReadinessWav() {
  const samples = <int>[0, 4096, 8192, 4096, 0, -4096, -8192, -4096];
  final repeatedSamples = List<int>.generate(
    800,
    (index) => samples[index % samples.length],
    growable: false,
  );
  final dataBytes = repeatedSamples.length * 2;
  final data = ByteData(44 + dataBytes);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 16000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, dataBytes, Endian.little);
  for (var index = 0; index < repeatedSamples.length; index += 1) {
    data.setInt16(44 + index * 2, repeatedSamples[index], Endian.little);
  }
  return data.buffer.asUint8List();
}
