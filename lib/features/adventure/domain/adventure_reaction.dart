/// Committed learning states that may select reviewed companion copy.
enum AdventureReactionTrigger {
  missionReady,
  independentCorrect,
  guidedCorrect,
  incorrect,
  skipped,
  resumed,
  completed,
  rewardPending,
  recovered,
}

enum AdventureReactionMotion { none, gentlePulse, celebrate }

enum AdventureReactionLanguage { th, en }

/// Describes the bounded claim made by a reviewed script.
enum AdventureReactionClaimClassification {
  noMasteryClaim,
  factualCorrectness,
  missionCompletion,
}

enum AdventureReactionContentViolation { unapprovedScript }

final class AdventureLocalizedReactionText {
  const AdventureLocalizedReactionText({required this.th, required this.en});

  final String th;
  final String en;

  String forLanguage(String languageCode) => languageCode == 'th' ? th : en;
}

/// One immutable script from the compile-time reviewed Adventure catalog.
///
/// Construction is private so runtime callers can select scripts but cannot
/// inject unreviewed companion copy.
final class AdventureReaction {
  const AdventureReaction._({
    required this.reactionId,
    required this.catalogVersion,
    required this.trigger,
    required this.variant,
    required this.copy,
    required this.accessibilityText,
    required this.visualPoseId,
    required this.motion,
    required this.audioAssetId,
    required this.claimClassification,
  });

  final String reactionId;
  final String catalogVersion;
  final AdventureReactionTrigger trigger;
  final int variant;
  final AdventureLocalizedReactionText copy;
  final AdventureLocalizedReactionText accessibilityText;
  final String visualPoseId;
  final AdventureReactionMotion motion;
  final String? audioAssetId;
  final AdventureReactionClaimClassification claimClassification;
}

/// Closed, locally packaged Adventure reaction catalog.
final class AdventureReactionCatalog {
  const AdventureReactionCatalog._(this.version, this.reactions);

  static const String v1Version = '1.0.0';
  static const AdventureReactionCatalog
  v1 = AdventureReactionCatalog._(v1Version, <AdventureReaction>[
    AdventureReaction._(
      reactionId: 'mission-ready-0',
      catalogVersion: v1Version,
      trigger: AdventureReactionTrigger.missionReady,
      variant: 0,
      copy: AdventureLocalizedReactionText(
        th: 'ภารกิจพร้อมแล้ว เริ่มเมื่อคุณพร้อมนะ',
        en: 'Your mission is ready. Start when you are ready.',
      ),
      accessibilityText: AdventureLocalizedReactionText(
        th: 'เพื่อนร่วมทางบอกว่าภารกิจพร้อมแล้ว เริ่มเมื่อคุณพร้อม',
        en: 'Companion says your mission is ready; start when you are ready.',
      ),
      visualPoseId: 'ready',
      motion: AdventureReactionMotion.gentlePulse,
      audioAssetId: null,
      claimClassification: AdventureReactionClaimClassification.noMasteryClaim,
    ),
    AdventureReaction._(
      reactionId: 'independent-correct-0',
      catalogVersion: v1Version,
      trigger: AdventureReactionTrigger.independentCorrect,
      variant: 0,
      copy: AdventureLocalizedReactionText(
        th: 'คำตอบนี้ถูกต้อง ไปต่อทีละก้าวนะ',
        en: 'That answer is correct. Keep going one step at a time.',
      ),
      accessibilityText: AdventureLocalizedReactionText(
        th: 'เพื่อนร่วมทางยืนยันว่าคำตอบนี้ถูกต้อง',
        en: 'Companion confirms that this answer is correct.',
      ),
      visualPoseId: 'affirm',
      motion: AdventureReactionMotion.celebrate,
      audioAssetId: null,
      claimClassification:
          AdventureReactionClaimClassification.factualCorrectness,
    ),
    AdventureReaction._(
      reactionId: 'guided-correct-0',
      catalogVersion: v1Version,
      trigger: AdventureReactionTrigger.guidedCorrect,
      variant: 0,
      copy: AdventureLocalizedReactionText(
        th: 'คำใบ้ช่วยให้ไปต่อได้ ลองสังเกตคำนี้อีกครั้งนะ',
        en: 'The hint helped you continue. Notice this word again.',
      ),
      accessibilityText: AdventureLocalizedReactionText(
        th: 'เพื่อนร่วมทางบอกว่าคำใบ้ช่วยได้ และชวนสังเกตคำนี้อีกครั้ง',
        en: 'Companion notes that the hint helped and suggests noticing the word again.',
      ),
      visualPoseId: 'guide',
      motion: AdventureReactionMotion.gentlePulse,
      audioAssetId: null,
      claimClassification: AdventureReactionClaimClassification.noMasteryClaim,
    ),
    AdventureReaction._(
      reactionId: 'incorrect-0',
      catalogVersion: v1Version,
      trigger: AdventureReactionTrigger.incorrect,
      variant: 0,
      copy: AdventureLocalizedReactionText(
        th: 'คำตอบนี้ยังไม่ตรง ลองใหม่เมื่อพร้อมนะ',
        en: 'That answer does not match yet. Try again when you are ready.',
      ),
      accessibilityText: AdventureLocalizedReactionText(
        th: 'เพื่อนร่วมทางบอกว่าคำตอบยังไม่ตรง และลองใหม่ได้เมื่อพร้อม',
        en: 'Companion says the answer does not match yet; try again when ready.',
      ),
      visualPoseId: 'encourage',
      motion: AdventureReactionMotion.gentlePulse,
      audioAssetId: null,
      claimClassification: AdventureReactionClaimClassification.noMasteryClaim,
    ),
    AdventureReaction._(
      reactionId: 'incorrect-1',
      catalogVersion: v1Version,
      trigger: AdventureReactionTrigger.incorrect,
      variant: 1,
      copy: AdventureLocalizedReactionText(
        th: 'ข้อนี้ยังไม่ใช่คำตอบที่ตรง มาดูอีกครั้งเมื่อพร้อมนะ',
        en: 'This one is not the matching answer yet. Take another look when ready.',
      ),
      accessibilityText: AdventureLocalizedReactionText(
        th: 'เพื่อนร่วมทางบอกว่าข้อนี้ยังไม่ตรง และกลับมาดูอีกครั้งได้',
        en: 'Companion says this one does not match yet and can be reviewed again.',
      ),
      visualPoseId: 'encourage',
      motion: AdventureReactionMotion.gentlePulse,
      audioAssetId: null,
      claimClassification: AdventureReactionClaimClassification.noMasteryClaim,
    ),
    AdventureReaction._(
      reactionId: 'skipped-0',
      catalogVersion: v1Version,
      trigger: AdventureReactionTrigger.skipped,
      variant: 0,
      copy: AdventureLocalizedReactionText(
        th: 'ข้ามข้อนี้ได้ เราจะเก็บไว้ให้กลับมาทบทวน',
        en: 'It is okay to skip this one. We will keep it for review.',
      ),
      accessibilityText: AdventureLocalizedReactionText(
        th: 'เพื่อนร่วมทางยืนยันว่าข้ามได้ และข้อนี้จะอยู่ในรายการทบทวน',
        en: 'Companion confirms that skipping is okay and this item will remain for review.',
      ),
      visualPoseId: 'support',
      motion: AdventureReactionMotion.none,
      audioAssetId: null,
      claimClassification: AdventureReactionClaimClassification.noMasteryClaim,
    ),
    AdventureReaction._(
      reactionId: 'resumed-0',
      catalogVersion: v1Version,
      trigger: AdventureReactionTrigger.resumed,
      variant: 0,
      copy: AdventureLocalizedReactionText(
        th: 'ยินดีต้อนรับกลับมา เริ่มต่อจากจุดที่พักไว้ได้เลย',
        en: 'Welcome back. Continue from where you paused.',
      ),
      accessibilityText: AdventureLocalizedReactionText(
        th: 'เพื่อนร่วมทางต้อนรับกลับมา และบอกว่าทำต่อจากจุดเดิมได้',
        en: 'Companion welcomes you back and says you can continue where you paused.',
      ),
      visualPoseId: 'welcome',
      motion: AdventureReactionMotion.gentlePulse,
      audioAssetId: null,
      claimClassification: AdventureReactionClaimClassification.noMasteryClaim,
    ),
    AdventureReaction._(
      reactionId: 'completed-0',
      catalogVersion: v1Version,
      trigger: AdventureReactionTrigger.completed,
      variant: 0,
      copy: AdventureLocalizedReactionText(
        th: 'ภารกิจรอบนี้เสร็จแล้ว คุณได้ลงมือเรียนรู้',
        en: 'This mission is complete. You showed up for your learning.',
      ),
      accessibilityText: AdventureLocalizedReactionText(
        th: 'เพื่อนร่วมทางยืนยันว่าภารกิจรอบนี้เสร็จแล้ว',
        en: 'Companion confirms that this mission is complete.',
      ),
      visualPoseId: 'complete',
      motion: AdventureReactionMotion.celebrate,
      audioAssetId: null,
      claimClassification:
          AdventureReactionClaimClassification.missionCompletion,
    ),
    AdventureReaction._(
      reactionId: 'reward-pending-0',
      catalogVersion: v1Version,
      trigger: AdventureReactionTrigger.rewardPending,
      variant: 0,
      copy: AdventureLocalizedReactionText(
        th: 'การเรียนบันทึกแล้ว รางวัลกำลังยืนยัน',
        en: 'Your learning is saved. The reward is being confirmed.',
      ),
      accessibilityText: AdventureLocalizedReactionText(
        th: 'เพื่อนร่วมทางบอกว่าการเรียนบันทึกแล้ว และรางวัลกำลังยืนยัน',
        en: 'Companion says learning is saved and the reward is being confirmed.',
      ),
      visualPoseId: 'waiting',
      motion: AdventureReactionMotion.none,
      audioAssetId: null,
      claimClassification: AdventureReactionClaimClassification.noMasteryClaim,
    ),
    AdventureReaction._(
      reactionId: 'recovered-0',
      catalogVersion: v1Version,
      trigger: AdventureReactionTrigger.recovered,
      variant: 0,
      copy: AdventureLocalizedReactionText(
        th: 'กลับมาใช้งานได้แล้ว ไปต่อเมื่อพร้อมนะ',
        en: 'The activity is available again. Continue when you are ready.',
      ),
      accessibilityText: AdventureLocalizedReactionText(
        th: 'เพื่อนร่วมทางบอกว่ากลับมาใช้งานได้แล้ว และไปต่อได้เมื่อพร้อม',
        en: 'Companion says the activity is available again; continue when ready.',
      ),
      visualPoseId: 'ready',
      motion: AdventureReactionMotion.none,
      audioAssetId: null,
      claimClassification: AdventureReactionClaimClassification.noMasteryClaim,
    ),
  ]);

  final String version;
  final List<AdventureReaction> reactions;

  static AdventureReactionCatalog? forVersion(String version) =>
      version == v1Version ? v1 : null;
}

/// Closed approval gate for the exact bilingual scripts reviewed for release.
///
/// Text that is merely absent from a denylist is not accepted. Every field
/// must exactly match an immutable entry in an approved catalog version.
abstract final class AdventureReactionContentReview {
  static Set<AdventureReactionContentViolation> findViolations(
    AdventureReaction reaction,
  ) => isApprovedReaction(reaction)
      ? const <AdventureReactionContentViolation>{}
      : const <AdventureReactionContentViolation>{
          AdventureReactionContentViolation.unapprovedScript,
        };

  static bool isApprovedReaction(AdventureReaction reaction) =>
      isApprovedScript(
        catalogVersion: reaction.catalogVersion,
        reactionId: reaction.reactionId,
        th: reaction.copy.th,
        en: reaction.copy.en,
        accessibilityTh: reaction.accessibilityText.th,
        accessibilityEn: reaction.accessibilityText.en,
      );

  static bool isApprovedScript({
    required String catalogVersion,
    required String reactionId,
    required String th,
    required String en,
    required String accessibilityTh,
    required String accessibilityEn,
  }) {
    final catalog = AdventureReactionCatalog.forVersion(catalogVersion);
    if (!identical(catalog, AdventureReactionCatalog.v1)) return false;
    for (final approved in catalog!.reactions) {
      if (approved.reactionId != reactionId) continue;
      return approved.copy.th == th &&
          approved.copy.en == en &&
          approved.accessibilityText.th == accessibilityTh &&
          approved.accessibilityText.en == accessibilityEn;
    }
    return false;
  }
}
