import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../domain/adventure_world_catalog.dart';

abstract final class PackagedAdventureWorldCatalog {
  static const String catalogId = 'lexiquest.adventure.world-v1';
  static const String catalogVersion = '1.0.0';
  static const ContentIdentity contentIdentity = ContentIdentity(
    type: ContentType.offlineArtifact,
    id: catalogId,
    revision: 1,
  );

  static final Uint8List bundleBytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'th': forLocale('th').toJson(),
        'en': forLocale('en').toJson(),
      }),
    ),
  );

  static final VerifiedContentManifest contentArtifact =
      VerifiedContentManifest(
        manifest: ContentManifest(
          storageId: 'manifest:$catalogId',
          identity: contentIdentity,
          checksumSha256: sha256.convert(bundleBytes).toString(),
          byteLength: bundleBytes.length,
          provenance: ContentProvenance.packaged,
          sourceUri: 'asset://adventure/world-v1/catalog-bundle.json',
          reviewState: ContentReviewState.approved,
          publicationState: ContentPublicationState.published,
          createdAtUtc: DateTime.utc(2026, 9, 1),
          reviewedAtUtc: DateTime.utc(2026, 9, 2),
          publishedAtUtc: DateTime.utc(2026, 9, 3),
        ),
        bytes: bundleBytes,
      );

  static final Map<String, List<int>>
  assetBytes = Map<String, List<int>>.unmodifiable(<String, List<int>>{
    'assets/adventure/world_v1/resume-review.svg': List<int>.unmodifiable(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg"><circle cx="8" cy="8" r="7"/></svg>',
      ),
    ),
    'assets/adventure/world_v1/today-mission.svg': List<int>.unmodifiable(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg"><path d="M1 15L8 1l7 14z"/></svg>',
      ),
    ),
    'assets/adventure/world_v1/next-preview.svg': List<int>.unmodifiable(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg"><rect x="1" y="1" width="14" height="14"/></svg>',
      ),
    ),
  });

  static AdventureWorldCatalog forLocale(String locale) {
    if (locale != 'th' && locale != 'en') {
      throw ArgumentError.value(locale, 'locale', 'must be th or en');
    }
    return AdventureWorldCatalog(
      schemaVersion: AdventureWorldCatalog.currentSchemaVersion,
      catalogId: catalogId,
      catalogVersion: catalogVersion,
      locale: locale,
      qaState: AdventureCatalogQaState.internalApproved,
      worlds: <AdventureWorldDefinition>[
        AdventureWorldDefinition(
          worldId: 'world-one',
          revision: 1,
          nodes: <AdventureNodeDefinition>[
            _node(
              id: 'resume-review',
              kind: AdventureNodeKind.resume,
              prerequisites: const <String>[],
              labels: const <String, String>{
                'th': 'ทบทวนการเดินทาง',
                'en': 'Resume or review',
              },
              accessibilityLabels: const <String, String>{
                'th':
                    'ทบทวนการเดินทาง พร้อมเมื่อมีบทเรียนค้างหรือคำที่ถึงกำหนด',
                'en': 'Resume or review, available for unfinished or due work',
              },
              assetId: 'node-resume-review',
            ),
            _node(
              id: 'today-mission',
              kind: AdventureNodeKind.mission,
              prerequisites: const <String>['resume-review'],
              labels: const <String, String>{
                'th': 'ภารกิจวันนี้',
                'en': 'Today mission',
              },
              accessibilityLabels: const <String, String>{
                'th': 'ภารกิจวันนี้ พร้อมเริ่มเมื่อบทเรียนวันนี้พร้อม',
                'en': 'Today mission, available when today work is ready',
              },
              assetId: 'node-today-mission',
            ),
            _node(
              id: 'next-preview',
              kind: AdventureNodeKind.rewardPreview,
              prerequisites: const <String>['today-mission'],
              labels: const <String, String>{
                'th': 'จุดหมายถัดไป',
                'en': 'Next destination',
              },
              accessibilityLabels: const <String, String>{
                'th': 'จุดหมายถัดไป ตัวอย่างสิ่งที่จะปลดล็อก',
                'en': 'Next destination, a preview of what unlocks next',
              },
              assetId: 'node-next-preview',
            ),
          ],
        ),
      ],
      reactions: <CompanionScriptDefinition>[
        CompanionScriptDefinition(
          reactionId: 'journey-ready',
          revision: 1,
          copyByLocale: const <String, String>{
            'th': 'ค่อย ๆ ไปทีละก้าวนะ',
            'en': 'One step at a time.',
          },
          accessibilityTextByLocale: const <String, String>{
            'th': 'เพื่อนร่วมทางให้กำลังใจให้ค่อย ๆ ไปทีละก้าว',
            'en': 'Your companion encourages one step at a time',
          },
          visualPoseAssetId: 'node-resume-review',
        ),
      ],
      assetManifest: AdventureAssetManifest(
        manifestId: 'world-v1-$locale',
        catalogVersion: catalogVersion,
        locale: locale,
        revision: 1,
        assets: const <AdventureAssetDefinition>[
          AdventureAssetDefinition(
            assetId: 'node-resume-review',
            path: 'assets/adventure/world_v1/resume-review.svg',
            mediaType: 'image/svg+xml',
            contentRevision: 1,
            byteSize: 75,
            checksumSha256:
                'a241cfd8af9c6ec98f47d1a67fed107943c6f0e6d0b5363c6f22f2ef3bed08bc',
          ),
          AdventureAssetDefinition(
            assetId: 'node-today-mission',
            path: 'assets/adventure/world_v1/today-mission.svg',
            mediaType: 'image/svg+xml',
            contentRevision: 1,
            byteSize: 73,
            checksumSha256:
                'a6d3b486e390e504c034694dfbdabe94e8ef85673c7141639f7fe5c4218e1442',
          ),
          AdventureAssetDefinition(
            assetId: 'node-next-preview',
            path: 'assets/adventure/world_v1/next-preview.svg',
            mediaType: 'image/svg+xml',
            contentRevision: 1,
            byteSize: 88,
            checksumSha256:
                '23af026c49bedf913fbe51b946aea1aff4a0538a82c315db0be4222dc6a3806e',
          ),
        ],
      ),
    );
  }

  static AdventureNodeDefinition _node({
    required String id,
    required AdventureNodeKind kind,
    required List<String> prerequisites,
    required Map<String, String> labels,
    required Map<String, String> accessibilityLabels,
    required String assetId,
  }) => AdventureNodeDefinition(
    nodeId: id,
    kind: kind,
    revision: 1,
    prerequisiteNodeIds: prerequisites,
    labelsByLocale: labels,
    accessibilityLabelsByLocale: accessibilityLabels,
    assetReferences: <AdventureAssetReference>[
      AdventureAssetReference(assetId: assetId, requiredRevision: 1),
    ],
  );
}
