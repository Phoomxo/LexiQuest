import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

final class StandardVoicePackFile {
  StandardVoicePackFile._({
    required this.contentId,
    required this.normalizedTextSha256,
    required this.relativePath,
    required this.byteSize,
    required this.sha256,
    required this.uri,
  });

  final String contentId;
  final String normalizedTextSha256;
  final String relativePath;
  final int byteSize;
  final String sha256;
  final Uri uri;

  bool matchesText(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return sha256Of(normalized) == normalizedTextSha256;
  }

  static String sha256Of(String value) =>
      crypto.sha256.convert(utf8.encode(value)).toString();
}

final class StandardVoicePackManifest {
  StandardVoicePackManifest._({
    required this.schemaVersion,
    required this.packId,
    required this.version,
    required this.locale,
    required this.voiceId,
    required this.engine,
    required this.modelVersion,
    required this.license,
    required this.licenseUri,
    required this.minimumAppVersion,
    required this.baseUri,
    required this.generatedAtUtc,
    required this.totalBytes,
    required List<StandardVoicePackFile> files,
  }) : files = List.unmodifiable(files);

  static const maxFiles = 2000;
  static const maxTotalBytes = 256 * 1024 * 1024;

  final int schemaVersion;
  final String packId;
  final String version;
  final String locale;
  final String voiceId;
  final String engine;
  final String modelVersion;
  final String license;
  final Uri licenseUri;
  final String minimumAppVersion;
  final Uri baseUri;
  final DateTime generatedAtUtc;
  final int totalBytes;
  final List<StandardVoicePackFile> files;

  String get recordId => '$packId@$version';

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'packId': packId,
    'version': version,
    'locale': locale,
    'voiceId': voiceId,
    'engine': engine,
    'modelVersion': modelVersion,
    'license': license,
    'licenseUri': licenseUri.toString(),
    'minimumAppVersion': minimumAppVersion,
    'baseUri': baseUri.toString(),
    'generatedAtUtc': generatedAtUtc.toIso8601String(),
    'totalBytes': totalBytes,
    'files': [
      for (final file in files)
        {
          'contentId': file.contentId,
          'normalizedTextSha256': file.normalizedTextSha256,
          'relativePath': file.relativePath,
          'byteSize': file.byteSize,
          'sha256': file.sha256,
        },
    ],
  };

  factory StandardVoicePackManifest.fromJson(Map<String, Object?> json) {
    ArgumentError invalid() => ArgumentError('Invalid voice pack manifest.');
    final schemaVersion = json['schemaVersion'];
    final packId = json['packId'];
    final version = json['version'];
    final locale = json['locale'];
    final voiceId = json['voiceId'];
    final engine = json['engine'];
    final modelVersion = json['modelVersion'];
    final license = json['license'];
    final licenseValue = json['licenseUri'];
    final minimumAppVersion = json['minimumAppVersion'];
    final baseValue = json['baseUri'];
    final generatedValue = json['generatedAtUtc'];
    final totalBytes = json['totalBytes'];
    final fileValues = json['files'];
    final safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
    final semantic = RegExp(r'^\d+\.\d+\.\d+(?:\+\d+)?$');
    if (schemaVersion != 1 ||
        packId is! String ||
        !safeId.hasMatch(packId) ||
        version is! String ||
        !semantic.hasMatch(version) ||
        locale is! String ||
        !const {'en', 'th'}.contains(locale) ||
        voiceId is! String ||
        !safeId.hasMatch(voiceId) ||
        engine != 'voxcpm2' ||
        modelVersion is! String ||
        modelVersion.trim().isEmpty ||
        license != 'Apache-2.0' ||
        licenseValue is! String ||
        minimumAppVersion is! String ||
        !semantic.hasMatch(minimumAppVersion) ||
        baseValue is! String ||
        generatedValue is! String ||
        totalBytes is! int ||
        totalBytes <= 0 ||
        totalBytes > maxTotalBytes ||
        fileValues is! List ||
        fileValues.isEmpty ||
        fileValues.length > maxFiles) {
      throw invalid();
    }
    final licenseUri = Uri.tryParse(licenseValue);
    final baseUri = Uri.tryParse(baseValue);
    final generatedAtUtc = DateTime.tryParse(generatedValue);
    if (!_isHttps(licenseUri) ||
        !_isHttps(baseUri) ||
        generatedAtUtc == null ||
        !generatedAtUtc.isUtc) {
      throw invalid();
    }

    final files = <StandardVoicePackFile>[];
    final contentIds = <String>{};
    final paths = <String>{};
    var calculatedBytes = 0;
    for (final value in fileValues) {
      if (value is! Map) throw invalid();
      final contentId = value['contentId'];
      final textHash = value['normalizedTextSha256'];
      final relativePath = value['relativePath'];
      final byteSize = value['byteSize'];
      final audioHash = value['sha256'];
      if (contentId is! String ||
          !safeId.hasMatch(contentId) ||
          textHash is! String ||
          !_isSha256(textHash) ||
          relativePath is! String ||
          !_isSafeRelativePath(relativePath) ||
          byteSize is! int ||
          byteSize <= 0 ||
          audioHash is! String ||
          !_isSha256(audioHash) ||
          !contentIds.add(contentId) ||
          !paths.add(relativePath.toLowerCase())) {
        throw invalid();
      }
      final uri = baseUri!.resolve(relativePath);
      if (uri.scheme != 'https' || uri.host != baseUri.host) throw invalid();
      calculatedBytes += byteSize;
      if (calculatedBytes > maxTotalBytes) throw invalid();
      files.add(
        StandardVoicePackFile._(
          contentId: contentId,
          normalizedTextSha256: textHash,
          relativePath: relativePath,
          byteSize: byteSize,
          sha256: audioHash,
          uri: uri,
        ),
      );
    }
    if (calculatedBytes != totalBytes) throw invalid();

    return StandardVoicePackManifest._(
      schemaVersion: schemaVersion as int,
      packId: packId,
      version: version,
      locale: locale,
      voiceId: voiceId,
      engine: engine as String,
      modelVersion: modelVersion,
      license: license as String,
      licenseUri: licenseUri!,
      minimumAppVersion: minimumAppVersion,
      baseUri: baseUri!,
      generatedAtUtc: generatedAtUtc,
      totalBytes: totalBytes,
      files: files,
    );
  }

  static bool _isHttps(Uri? uri) =>
      uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;

  static bool _isSha256(String value) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

  static bool _isSafeRelativePath(String value) {
    if (value.isEmpty ||
        value.contains('\\') ||
        value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(value)) {
      return false;
    }
    final segments = value.split('/');
    return segments.every(
      (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
    );
  }
}
