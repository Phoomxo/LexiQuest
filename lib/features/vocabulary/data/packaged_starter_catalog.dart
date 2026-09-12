import 'package:drift/drift.dart';
import '../../../data/local/app_database.dart' as db;
import '../../learning_packs/data/drift_content_manifest_repository.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../learning_packs/domain/content_quality_policy.dart';
import '../domain/vocabulary_word.dart' show RichLexicalMetadata;
import '../domain/packaged_starter_identity.dart';

/// Original text internally reviewed on 2026-09-08. No certified CEFR claim.
abstract final class PackagedStarterCatalog {
  static const ownerId = PackagedStarterIdentity.ownerId;
  static const categoryId = PackagedStarterIdentity.categoryId;
  static const categoryName = 'คำศัพท์เริ่มต้นรอบตัว';
  static const source = 'asset://lexiquest/starter-content/r1';
  static final timestamp = DateTime.utc(2026, 9, 8);
  static const words = <StarterWord>[
    StarterWord(
      'book',
      'หนังสือ',
      'a92b4c2e6a8db6c1b760b82ee7bc8341afcd26b974bba78a06c0385696731bee',
      234,
    ),
    StarterWord(
      'pencil',
      'ดินสอ',
      '5c2c96810f0b52bcafcafb31cc418382dfc9ae5a2be4326878f25285625dfbca',
      263,
    ),
    StarterWord(
      'chair',
      'เก้าอี้',
      '33d514b228ae7033e1d1242a77054178aecf1e67587b1514bb05901f47591fdd',
      229,
    ),
    StarterWord(
      'door',
      'ประตู',
      'c5118f9b9d159b18c0694d63d7667481c2189832a5b39307a1f83b5ef00aac04',
      264,
    ),
    StarterWord(
      'window',
      'หน้าต่าง',
      '1fa2337cdb2f423fb85068d9ec2cf468dc82448c44a2b36ea22a104e2d2fbc4c',
      272,
    ),
    StarterWord(
      'bottle',
      'ขวด',
      '61dd55ca6b4a3574e304be3738befba59b9a5c1ba17993ef411db189b713c562',
      259,
    ),
    StarterWord(
      'cup',
      'ถ้วย',
      '4af13e68ae9dc7364560bb9cd15e40c5e0fb1a43d16b8f46ea8f8376adf1cc38',
      260,
    ),
    StarterWord(
      'spoon',
      'ช้อน',
      '8cadc285886d20ad391423309e455b82bbb6f008253480c0274894a5491c8795',
      261,
    ),
    StarterWord(
      'plate',
      'จาน',
      '4deed1ddfb40df024d5d014b8323ea08f824f5b7a0653113c7c01316ac6c05ce',
      236,
    ),
    StarterWord(
      'bag',
      'กระเป๋า',
      '9b27908a43e5f047ab8cf00ee9684d902255aa67e11f4c703032ba321856cf7b',
      249,
    ),
    StarterWord(
      'clock',
      'นาฬิกา',
      'a662360d388bb4466a97b3f915d4fb77cd9b6cec0624b2e87b9a62176be7d3b9',
      270,
    ),
    StarterWord(
      'key',
      'กุญแจ',
      '834b6e191333dc96238269dd4884dd09546eab26aee93f0ca1df19ff776e6cdf',
      235,
    ),
  ];

  static bool isReservedId(String id) =>
      PackagedStarterIdentity.isReservedId(id);

  /// Verifies every shipped file before one atomic, immutable installation.
  /// Replays never update a row, including user rows with colliding IDs.
  static Future<void> provision(
    db.AppDatabase database,
    DriftContentManifestRepository manifests,
    ContentArtifactBytesLoader loadBytes,
  ) async {
    final artifacts = <VerifiedContentManifest>[];
    for (final word in words) {
      final bytes = await loadBytes(word.identity);
      if (bytes == null) {
        throw const ContentQualityFailure(
          ContentQualityFailureCode.missingReference,
        );
      }
      final verified = const ContentQualityPolicy().requireVerified(
        manifest: word.manifest,
        bytes: bytes,
      );
      RichLexicalMetadata.fromVerifiedArtifact(
        bytes: verified.bytes,
        wordId: word.id,
        contentRevision: 1,
        verifiedArtifactChecksumSha256: word.artifactHash,
      );
      artifacts.add(verified);
    }
    await database.transaction(() async {
      final owner = await (database.select(
        database.localOwners,
      )..where((row) => row.id.equals(ownerId))).getSingleOrNull();
      if (owner == null) {
        await database
            .into(database.localOwners)
            .insert(
              db.LocalOwnersCompanion.insert(
                id: ownerId,
                accountState: const Value('localGuest'),
                createdAtUtcMs: timestamp.millisecondsSinceEpoch,
                isActive: const Value(false),
              ),
            );
      } else if (owner.isActive ||
          owner.firebaseUid != null ||
          owner.accountState != 'localGuest' ||
          owner.createdAtUtcMs != timestamp.millisecondsSinceEpoch ||
          owner.upgradedAtUtcMs != null) {
        throw const ContentQualityFailure(
          ContentQualityFailureCode.immutableRevisionConflict,
        );
      }
      final category =
          await (database.select(database.vocabularyCategories)..where(
                (row) =>
                    row.id.equals(categoryId) |
                    (row.ownerId.equals(ownerId) &
                        row.normalizedName.equals(categoryName)),
              ))
              .get();
      if (category.isEmpty) {
        await database
            .into(database.vocabularyCategories)
            .insert(
              db.VocabularyCategoriesCompanion.insert(
                id: categoryId,
                ownerId: ownerId,
                name: categoryName,
                normalizedName: categoryName,
                createdAtUtcMs: timestamp.millisecondsSinceEpoch,
                updatedAtUtcMs: timestamp.millisecondsSinceEpoch,
              ),
            );
      } else if (category.length != 1 || !matchesCategory(category.single)) {
        throw const ContentQualityFailure(
          ContentQualityFailureCode.immutableRevisionConflict,
        );
      }
      for (var index = 0; index < words.length; index++) {
        final word = words[index];
        final found =
            await (database.select(database.vocabularyWords)..where(
                  (row) =>
                      row.id.equals(word.id) |
                      (row.ownerId.equals(ownerId) &
                          row.categoryId.equals(categoryId) &
                          row.normalizedSpelling.equals(word.key) &
                          row.normalizedMeaning.equals(word.meaning)),
                ))
                .get();
        if (found.isEmpty) {
          await database.into(database.vocabularyWords).insert(word.insert);
        } else if (found.length != 1 || !word.matches(found.single)) {
          throw const ContentQualityFailure(
            ContentQualityFailureCode.immutableRevisionConflict,
          );
        }
        await manifests.provisionPackagedArtifact(artifacts[index]);
      }
    });
  }

  static bool matchesCategory(db.VocabularyCategory row) =>
      row.id == categoryId &&
      row.ownerId == ownerId &&
      row.name == categoryName &&
      row.normalizedName == categoryName &&
      row.sortOrder == 0 &&
      row.localRevision == 1 &&
      row.cloudRevision == 0 &&
      row.lastAcknowledgedAtUtcMs == null &&
      row.serverUpdatedAtUtcMs == null &&
      !row.isDeleted &&
      row.createdAtUtcMs == timestamp.millisecondsSinceEpoch &&
      row.updatedAtUtcMs == timestamp.millisecondsSinceEpoch;
}

final class StarterWord {
  const StarterWord(
    this.key,
    this.meaning,
    this.artifactHash,
    this.artifactBytes,
  );
  final String key;
  final String meaning;
  final String artifactHash;
  final int artifactBytes;
  String get id => 'word:starter-$key';
  ContentIdentity get identity =>
      ContentIdentity(type: ContentType.lexicalMetadata, id: id, revision: 1);
  String get coreHash => ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: PackagedStarterCatalog.categoryId,
    spelling: key,
    normalizedSpelling: key,
    meaning: meaning,
    normalizedMeaning: meaning,
    partOfSpeech: 'noun',
    cefrLevel: null,
    source: PackagedStarterCatalog.source,
    isGlobal: true,
  );
  ContentManifest get manifest => ContentManifest(
    storageId: 'manifest:lexical:starter-$key:r1',
    identity: identity,
    checksumSha256: artifactHash,
    byteLength: artifactBytes,
    provenance: ContentProvenance.packaged,
    sourceUri: 'asset://content/lexical_metadata/starter-$key/r1.json',
    reviewState: ContentReviewState.approved,
    publicationState: ContentPublicationState.published,
    createdAtUtc: PackagedStarterCatalog.timestamp,
    reviewedAtUtc: PackagedStarterCatalog.timestamp,
    publishedAtUtc: PackagedStarterCatalog.timestamp,
  );
  db.VocabularyWordsCompanion get insert => db.VocabularyWordsCompanion.insert(
    id: id,
    ownerId: PackagedStarterCatalog.ownerId,
    categoryId: PackagedStarterCatalog.categoryId,
    spelling: key,
    normalizedSpelling: key,
    meaning: meaning,
    normalizedMeaning: meaning,
    partOfSpeech: 'noun',
    source: const Value(PackagedStarterCatalog.source),
    isGlobal: const Value(true),
    contentRevision: const Value(1),
    contentChecksumSha256: Value(coreHash),
    contentProvenance: const Value('packaged'),
    contentReviewState: const Value('approved'),
    contentPublicationState: const Value('published'),
    createdAtUtcMs: PackagedStarterCatalog.timestamp.millisecondsSinceEpoch,
    updatedAtUtcMs: PackagedStarterCatalog.timestamp.millisecondsSinceEpoch,
  );
  bool matches(db.VocabularyWord row) =>
      row.id == id &&
      row.ownerId == PackagedStarterCatalog.ownerId &&
      row.categoryId == PackagedStarterCatalog.categoryId &&
      row.spelling == key &&
      row.normalizedSpelling == key &&
      row.meaning == meaning &&
      row.normalizedMeaning == meaning &&
      row.partOfSpeech == 'noun' &&
      row.cefrLevel == null &&
      row.source == PackagedStarterCatalog.source &&
      row.isGlobal &&
      row.contentRevision == 1 &&
      row.contentChecksumSha256 == coreHash &&
      row.contentProvenance == 'packaged' &&
      row.contentReviewState == 'approved' &&
      row.contentPublicationState == 'published' &&
      !row.isDeleted &&
      row.localRevision == 1 &&
      row.cloudRevision == 0 &&
      row.lastAcknowledgedAtUtcMs == null &&
      row.serverUpdatedAtUtcMs == null &&
      row.createdAtUtcMs ==
          PackagedStarterCatalog.timestamp.millisecondsSinceEpoch &&
      row.updatedAtUtcMs ==
          PackagedStarterCatalog.timestamp.millisecondsSinceEpoch;
}
