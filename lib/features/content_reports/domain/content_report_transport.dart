import 'content_report.dart';

final class ContentReportIdentityBinding {
  ContentReportIdentityBinding({
    required this.ownerId,
    required this.firebaseUid,
    required this.generation,
  }) {
    if (ownerId.trim().isEmpty ||
        ownerId.runes.length > 256 ||
        firebaseUid.trim().isEmpty ||
        firebaseUid != firebaseUid.trim() ||
        firebaseUid.runes.length > 128 ||
        firebaseUid.contains('/') ||
        firebaseUid.runes.any((rune) => rune < 32) ||
        generation < 0) {
      throw ArgumentError('Invalid report identity binding');
    }
  }
  final String ownerId;
  final String firebaseUid;
  final int generation;
  @override
  bool operator ==(Object other) =>
      other is ContentReportIdentityBinding &&
      (ownerId, firebaseUid, generation) ==
          (other.ownerId, other.firebaseUid, other.generation);
  @override
  int get hashCode => Object.hash(ownerId, firebaseUid, generation);
}

abstract interface class ContentReportTransport {
  bool get enabled;
  ContentReportIdentityBinding? get currentBinding;
  Future<void> requireCurrent(ContentReportIdentityBinding binding);
  Future<ContentReportAcknowledgement> submit(
    ContentReportIdentityBinding binding,
    ContentReportPayload payload,
  );
  Future<ContentReportAcknowledgement?> readReceipt(
    ContentReportIdentityBinding binding,
    ContentReportPayload payload,
  );
}

final class DisabledContentReportTransport implements ContentReportTransport {
  const DisabledContentReportTransport();
  @override
  bool get enabled => false;
  @override
  ContentReportIdentityBinding? get currentBinding => null;
  Never _disabled() =>
      throw const ContentReportException(ContentReportFailureCode.disabled);
  @override
  Future<void> requireCurrent(ContentReportIdentityBinding binding) async =>
      _disabled();
  @override
  Future<ContentReportAcknowledgement> submit(
    ContentReportIdentityBinding binding,
    ContentReportPayload payload,
  ) async => _disabled();
  @override
  Future<ContentReportAcknowledgement?> readReceipt(
    ContentReportIdentityBinding binding,
    ContentReportPayload payload,
  ) async => _disabled();
}

final class ContentReportIdentityPorts {
  const ContentReportIdentityPorts({
    required this.currentBinding,
    required this.requireCurrent,
    required this.loadIdToken,
    required this.dispose,
  });
  final ContentReportIdentityBinding? Function() currentBinding;
  final Future<void> Function(ContentReportIdentityBinding) requireCurrent;
  final Future<String?> Function(ContentReportIdentityBinding) loadIdToken;
  final Future<void> Function() dispose;
}
