enum CueType {
  personalStory,
  keyword,
  collocation,
  synonym,
  antonym,
  sensory,
  context,
}

enum AssociationSource { user, curated, aiSuggested }

enum AssociationPrivacy { private }

class AssociationRecord {
  final String associationId;
  final String ownerId;
  final String wordKey;
  final CueType cueType;
  final String cueText;
  final AssociationSource source;
  final AssociationPrivacy privacy;
  final double strength;
  final int successCount;
  final int failureCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int schemaVersion;

  AssociationRecord({
    required this.associationId,
    required this.ownerId,
    required this.wordKey,
    required this.cueType,
    required this.cueText,
    required this.source,
    this.privacy = AssociationPrivacy.private,
    this.strength = 1.0,
    this.successCount = 0,
    this.failureCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = 1,
  }) {
    if (cueText.trim().isEmpty || cueText.length > 500) {
      throw ArgumentError('cueText must be non-empty and <= 500 characters');
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'associationId': associationId,
      'ownerId': ownerId,
      'wordKey': wordKey,
      'cueType': cueType.name,
      'cueText': cueText,
      'source': source.name,
      'privacy': privacy.name,
      'strength': strength,
      'successCount': successCount,
      'failureCount': failureCount,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'schemaVersion': schemaVersion,
    };
  }

  factory AssociationRecord.fromJson(Map<String, dynamic> json) {
    return AssociationRecord(
      associationId: json['associationId'] as String,
      ownerId: json['ownerId'] as String,
      wordKey: json['wordKey'] as String,
      cueType: CueType.values.byName(json['cueType'] as String),
      cueText: json['cueText'] as String,
      source: AssociationSource.values.byName(json['source'] as String),
      privacy: AssociationPrivacy.values.byName(json['privacy'] as String),
      strength: (json['strength'] as num).toDouble(),
      successCount: json['successCount'] as int,
      failureCount: json['failureCount'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      schemaVersion: json['schemaVersion'] as int? ?? 1,
    );
  }
}
