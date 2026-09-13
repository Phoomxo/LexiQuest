"""Author source-pinned inspection records and downstream acceptance fixtures."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[6]
OUT = Path(__file__).parent
records = []

def add(n, title, version, sources, writers, readers, inputs, denominator, missing, formula, owners, tests, cases, defects=()):
    pins = []
    for path, symbol in sources:
        p = ROOT / path
        lines = p.read_text(encoding='utf-8-sig').splitlines()
        line = next(i + 1 for i, text in enumerate(lines) if symbol in text)
        pins.append({'path': path, 'symbol': symbol, 'line': line,
                     'sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
                     'gitBlob': subprocess.check_output(['git', 'rev-parse', 'HEAD:' + path], cwd=ROOT).decode().strip()})
    for path in writers + readers + tests:
        assert (ROOT / path).is_file(), path
    records.append({'formulaId': f'FORM-{n:02}', 'title': title, 'policyVersion': version,
                    'authorities': pins, 'writers': writers, 'readers': readers, 'inputs': inputs,
                    'denominator': denominator, 'missingBehavior': missing, 'sourceFormula': formula,
                    'ownerPackages': owners, 'plannedTestTargets': tests,
                    'fixtures': [{'caseId': f'FORM-{n:02}-{i+1:02}', 'input': case[0], 'expected': case[1], 'basis': case[2],
                                  'runtimeStatus': 'NOT RUN in B01'} for i, case in enumerate(cases)],
                    'defects': list(defects), 'inspectionStatus': 'registered-with-downstream-defect' if defects else 'registered',
                    'compatibility': 'No production formula change. Persisted policy/receipt/content meanings remain pinned; a behavior change requires versioned compatibility/adapter and owner-package regression.'})

add(1, 'First answers versus repair and practice aggregate', 'Pair checkpoint/plan-pinned; EvidenceEligibilityPolicySet policy-set-v1',
    [('lib/features/learning/pair_matching/domain/pair_matching_history_projection.dart', '_answerCounts('),
     ('lib/features/progress/data/drift_progress_queries.dart', '_isPracticeAttempt('),
     ('lib/features/learning/domain/evidence_eligibility_policy.dart', 'policy-set-v1')],
    ['lib/features/learning/data/drift_learning_repository.dart'],
    ['lib/features/progress/data/drift_progress_queries.dart', 'lib/features/progress/data/drift_learning_calendar_reader.dart'],
    ['owner/session/item identity', 'ordered canonical attempts', 'correctness', 'evidence context/eligibility', 'checkpoint plan/content revision'],
    'Target: first eligible answer per item/session; repairs separate. Current aggregate counts all non-assessment/non-recreational attempts.',
    'Empty aggregate accuracy=null; no first eligible evidence must remain noEvidence. Exposure/self-report are not independent first-answer skill.',
    'Pair first seen promptWordId enters first count; subsequent answers enter repair count. Progress currently c/allPracticeN (B01-FORM-01).',
    ['G1.2', 'G1.3', 'G3.5'], ['test/features/learning/learning_use_cases_test.dart', 'test/features/progress/progress_projector_test.dart', 'test/features/progress/learning_calendar_reader_test.dart'],
    [({'firstCorrect': 5, 'firstN': 6, 'repairCorrect': 1, 'repairN': 1}, {'firstAccuracyFraction': '5/6', 'repairAccuracyFraction': '1/1', 'currentAggregateFraction': '6/7'}, 'Master target versus source-inspected aggregate defect; do not promote aggregate to first-answer accuracy'),
     ({'firstN': 0}, {'accuracy': None, 'availability': 'noEvidence'}, 'No denominator, not zero skill'),
     ({'acknowledgeSameAttemptTwice': True}, {'newAnswers': 1}, 'Durable command identity, not count of callback deliveries'),
     ({'onlyExposureOrSelfReport': True}, {'eligibleFirstN': 0}, 'Master first-eligible denominator; downstream projection gap')], ['B01-FORM-01'])

add(2, 'Pair descriptive stars', 'PairStarPolicy v1 (plan.starPolicyVersion)',
    [('lib/features/learning/pair_matching/domain/pair_star_policy.dart', 'static PairStarResult project')],
    ['lib/features/learning/data/drift_learning_repository.dart'], ['lib/features/learning/pair_matching/domain/pair_matching_history_projection.dart'],
    ['terminal acknowledgement', 'complete/pending', 'ordered first attempts', 'matched/independent/supported word IDs'],
    'matched words; integer comparison independent*4 >= matched*3', 'Incomplete or pending or unacknowledged -> stars=null; unsupported version throws',
    'Complete perfect first/no support ->3; otherwise independent*4>=matched*3 ->2; otherwise1. Projection never grants rewards.', ['G2.2'],
    ['test/features/learning/pair_matching/pair_star_policy_test.dart'],
    [({'complete': True, 'pending': True, 'ack': False}, {'stars': None}, 'Terminal guard'),
     ({'complete': True, 'ack': True, 'pending': False, 'perfect': True, 'independent': 4, 'matched': 4}, {'stars': 3}, 'Perfect first answers'),
     ({'complete': True, 'ack': True, 'pending': False, 'perfect': False, 'independent': 3, 'matched': 4}, {'stars': 2}, '12>=12 boundary'),
     ({'complete': True, 'ack': True, 'pending': False, 'perfect': False, 'independent': 2, 'matched': 4}, {'stars': 1}, '8<12'),
     ({'firstWrongThenRepair': True, 'independent': 4, 'matched': 4}, {'perfect': False, 'maximumStars': 2}, 'Repair cannot replace first answer')])

add(3, 'Binary SRS', 'BinarySm2SrsPolicy v2', [('lib/features/learning/domain/srs_policy.dart', 'static const int version = 2')],
    ['lib/features/learning/data/drift_learning_repository.dart'], ['lib/features/progress/data/drift_progress_queries.dart'],
    ['previous SrsSnapshot or null', 'isCorrect', 'UTC now'], 'None; deterministic interval/difficulty state transition',
    'No prior -> repetitions0/lapses0/difficulty0.3; non-UTC rejected',
    'Correct repetitions+1; intervals1,3,7,14 then double(clamp prior1..36500) cap36500; difficulty max(0.1,prior-0.03). Wrong repetitions0,interval1,lapses+1,difficulty min(1,prior+0.12); due=nowUTC+days.', ['G1.5'],
    ['test/features/learning/srs_policy_test.dart'],
    [({'correctSequenceCount': 5, 'previous': None}, {'intervalDays': [1, 3, 7, 14, 28], 'difficulty': 0.15}, 'Five increments and five decrements of0.03'),
     ({'previousRepetitions': 5, 'previousInterval': 28, 'previousLapses': 2, 'previousDifficulty': 0.9, 'correct': False}, {'repetitions': 0, 'intervalDays': 1, 'lapses': 3, 'difficulty': 1.0}, 'Wrong reset/cap'),
     ({'repetitions': 10, 'priorInterval': 50000, 'correct': True}, {'intervalDays': 36500}, 'Clamp before multiply'),
     ({'priorDifficulty': 0.11, 'correct': True}, {'difficulty': 0.1}, 'Floor'),
     ({'nowUtc': '2026-09-13T00:00:00Z', 'intervalDays': 28}, {'dueAtUtc': '2026-10-11T00:00:00Z'}, 'UTC date arithmetic'),
     ({'nowIsUtc': False}, {'error': 'ArgumentError'}, 'No implicit device timezone')])

add(4, 'Lifetime XP and receipt identity', 'AvatarProgressionPolicyV1 v1; eligibility receipt v1 permanently p1',
    [('lib/features/rewards/domain/avatar_progression_policy.dart', 'final class AvatarProgressionPolicyV1'),
     ('lib/features/rewards/data/drift_reward_repository.dart', 'class DriftRewardRepository')],
    ['lib/features/rewards/data/drift_reward_repository.dart'], ['lib/features/progress/data/drift_progress_queries.dart'],
    ['nonnegative canonical lifetimeXP', 'catalog version/required level', 'owner/idempotency key/event/purchase receipt'],
    '20 lifetime XP per level; coins are not denominator or XP input', 'Negative XP/invalid catalog throws; unreported event is not a grant',
    'level=XP~/20+1; into=XP%20; next=level*20; until=next-XP; item minimum=(requiredLevel-1)*20. Historical p1 eligibility stays bound to v1.', ['G1.2', 'G4.4', 'G4.5'],
    ['test/features/rewards/avatar_progression_policy_test.dart'],
    [({'lifetimeXp': [0, 19, 20, 39, 40]}, {'level': [1, 1, 2, 2, 3], 'xpIntoLevel': [0, 19, 0, 19, 0], 'nextLevelAt': [20, 20, 40, 40, 60]}, 'Integer boundaries'),
     ({'lifetimeXp': 40, 'coinsSpent': 20}, {'level': 3, 'lifetimeXp': 40}, 'Spending coins does not subtract lifetimeXP'),
     ({'requiredLevel': 3, 'xpBefore': 39, 'xpAfter': 40}, {'unlockedBefore': False, 'unlockedAfter': True}, 'Exact cosmetic threshold'),
     ({'sameGrantOrPurchaseKeyDeliveredTwice': True}, {'durableTransactions': 1}, 'Owner/idempotent writer acceptance; not verified by pure level arithmetic')])

add(5, 'Eligible local-day streak', 'StreakPolicy v2; TimezonePolicy v1',
    [('lib/features/motivation/domain/streak_policy.dart', 'static const int version = 2'), ('lib/features/motivation/domain/timezone_policy.dart', 'static const int version = 1')],
    ['lib/features/motivation/data/drift_streak_repository.dart'], ['lib/features/progress/data/drift_progress_queries.dart'],
    ['current/longest streak', 'freeze inventory', 'last UTC instant', 'current UTC instant', 'IANA timezone'],
    'Calendar day difference after converting both instants to selected timezone', 'No prior learning -> current1/longest1; invalid state/non-UTC/clock rollback rejected',
    'dayDiff0 no-op;1 increments and updates longest;2 with freeze consumes1 and holds current streak (does not increment); otherwise recovery current1, longest preserved. New freeze inventory cap3; historical surplus retained.', ['G4.4'],
    ['test/features/motivation/streak_use_cases_test.dart', 'test/features/motivation/timezone_policy_test.dart'],
    [({'current': 5, 'longest': 8, 'freeze': 1, 'dayDiff': 0}, {'current': 5, 'longest': 8, 'freeze': 1}, 'Same day'),
     ({'current': 5, 'longest': 8, 'freeze': 1, 'dayDiff': 1}, {'current': 6, 'longest': 8, 'freeze': 1}, 'Consecutive'),
     ({'current': 5, 'longest': 8, 'freeze': 1, 'dayDiff': 2}, {'current': 5, 'longest': 8, 'freeze': 0}, 'Freeze holds streak; no phantom sixth day'),
     ({'current': 5, 'longest': 8, 'freeze': 0, 'dayDiff': 2}, {'current': 1, 'longest': 8, 'freeze': 0}, 'Recovery'),
     ({'current': 5, 'longest': 8, 'freeze': 1, 'dayDiff': 3}, {'current': 1, 'longest': 8, 'freeze': 1}, 'Cannot bridge more than one missed day'),
     ({'nowBeforeLastInstant': True}, {'error': 'StateError', 'writes': 0}, 'Rollback rejection')])

add(6, 'Monotonic active effort', 'LearningTimeSegment persisted contract; controller has no independent formula version',
    [('lib/features/time_tracking/application/active_learning_time_controller.dart', 'totalDurationMs: (trustworthyEnd'),
     ('lib/features/time_tracking/data/drift_learning_time_repository.dart', 'class DriftLearningTimeRepository')],
    ['lib/features/time_tracking/data/drift_learning_time_repository.dart'], ['lib/features/progress/data/drift_learning_calendar_reader.dart'],
    ['session/owner', 'monotonic microseconds', 'UTC anchor', 'interaction/pause/background/idle', 'canonical offset and segment identity'],
    '1000 microseconds per persisted millisecond; sum unique contiguous active segments',
    'Inactive/paused/idle time not counted; negative/backward monotonic rejected; start reloads durable offset',
    'Clamp trustworthy active end to idle boundary (default5min), split into max5min segments, floor microseconds/1000. Repository guards same-segment retry and active-offset continuity.', ['G1.6', 'G4.3'],
    ['test/features/time_tracking/active_learning_time_controller_test.dart', 'test/features/time_tracking/learning_time_repository_test.dart'],
    [({'activeSeconds': [30, 30], 'pausedSeconds': 60}, {'activeMs': 60000}, '30000+30000; exclude pause'),
     ({'idleAfterSeconds': 300, 'wallSecondsWithoutInteraction': 420}, {'activeMs': 300000}, 'Idle clamp'),
     ({'duplicateSegmentMs': 30000, 'deliveries': 2}, {'activeMs': 30000}, 'Idempotent segment identity'),
     ({'durableOffsetMs': 30000, 'incomingStartOffsetMs': 20000}, {'result': 'reject', 'activeMs': 30000}, 'Overlap cannot inflate sum'),
     ({'monotonicDeltaMicros': -1}, {'result': 'reject'}, 'Clock rollback is not negative effort')])

add(7, 'Calendar, goals and countdown', 'TimezonePolicy v1; source-pinned calendar/goal readers',
    [('lib/features/progress/data/drift_learning_calendar_reader.dart', 'Future<LearningCalendarSnapshot> loadWeek'),
     ('lib/features/goals/application/learning_goal_use_cases.dart', 'LearningGoalCountdown countdown'),
     ('lib/features/motivation/domain/timezone_policy.dart', 'static DateTime getLearningDay')],
    ['lib/features/time_tracking/data/drift_learning_time_repository.dart', 'lib/features/goals/data/drift_learning_goal_repository.dart'],
    ['lib/features/progress/data/drift_personal_learning_profile_reader.dart'],
    ['owner', 'UTC event/reference', 'IANA timezone', 'goal deadline timezone', 'canonical effort segments and evidence'],
    'Accuracy c/n; effort milliseconds; countdown calendar date ordinals, not elapsed24h',
    'Empty week effort0 and accuracy=null; no goal remains absent, not countdown0; corrupt evidence rejected',
    'Local week starts Monday. Countdown signed day difference becomes past/today/future plus abs(days). Weekly accuracy currently shares aggregate practice-denominator gap FORM-01.', ['G3.5', 'G4.2'],
    ['test/features/progress/learning_calendar_reader_test.dart', 'test/features/goals/learning_goal_use_cases_test.dart'],
    [({'utc': ['2026-09-13T16:59:00Z', '2026-09-13T17:01:00Z'], 'timezone': 'Asia/Bangkok'}, {'dates': ['2026-09-13', '2026-09-14'], 'weekStarts': ['2026-09-07', '2026-09-14']}, 'Sunday23:59 to Monday00:01'),
     ({'deadlineDayDifference': [-1, 0, 1]}, {'states': ['past', 'today', 'future'], 'days': [1, 0, 1]}, 'Ordinal boundary'),
     ({'sameUtcInstant': '2026-09-13T17:01:00Z', 'timezones': ['UTC', 'Asia/Bangkok']}, {'dates': ['2026-09-13', '2026-09-14']}, 'Reproject timezone without rewriting evidence'),
     ({'weekAttempts': 0, 'segments': 0}, {'accuracy': None, 'effortMs': 0}, 'Missing evidence differs from measured wrong answer')], ['B01-FORM-01'])

add(8, 'Compatible assessment pair', 'Instrument/form/content/evidence/build versions from canonical run; no new policy',
    [('lib/features/assessment/application/assessment_comparison.dart', 'Future<AssessmentComparisonResult> compare')],
    ['lib/features/learning/data/drift_learning_repository.dart'], ['lib/features/assessment/application/assessment_comparison.dart'],
    ['owner/studyCycle/protocol/assignment/consent', 'instrument/form hashes/versions', 'content/policy/build/schema/catalog', 'unique canonical items', 'chronology'],
    'Each compatible complete form own item count; accuracy fraction0..1; UI percentage points=100*(post-pre)',
    'Missing/duplicate phase -> MissingPair; incompatible/empty/duplicate item -> IncompatibleMetadata; no delta',
    'correct/n per run; correctCountDelta=postC-preC; accuracyDelta=postFraction-preFraction; research gate remains intact.', ['G3.6'],
    ['test/features/assessment/assessment_comparison_test.dart'],
    [({'syntheticCompatibleFormItems': 6, 'preCorrect': 5, 'postCorrect': 6}, {'preFraction': '5/6', 'postFraction': '1/1', 'deltaFraction': '1/6', 'deltaPercentagePoints': '50/3', 'correctDelta': 1}, 'Arithmetic oracle; fixture requires matching synthetic instrument metadata, not arbitrary production6-item form'),
     ({'postRun': None}, {'result': 'MissingPair', 'delta': None}, 'No invented post score'),
     ({'duplicateItemId': True}, {'result': 'IncompatibleMetadata', 'delta': None}, 'Unique canonical item set'),
     ({'buildOrContentOrOwnerMismatch': True}, {'result': 'IncompatibleMetadata', 'delta': None}, 'Compatibility gate')])

add(9, 'Camera evaluation rates and uncertainty', 'camera_accuracy.py frozen config/dataset/predictions hashes; Wilson z=1.959963984540054',
    [('tools/camera_accuracy.py', 'def _metrics'), ('tools/camera_accuracy.py', 'def evaluate_frozen')],
    ['tools/camera_accuracy.py'], ['tools/camera_accuracy.py'],
    ['fresh natural full-frame paired unique IDs/groups/SHA', 'known/unknown truth', 'raw baseline label map', 'explicit baseline_accepted bool', 'candidate/confidence/threshold', 'frozen split config'],
    'Known n for accepted-and-correct, unknown n for false accept, per-class truth n for recall. Wilson n is same selected cohort.',
    'n0 rate=null/wilson95=null; unmapped raw label, bool/nonfinite threshold/confidence or missing accepted bool -> input error',
    'p=k/n; d=1+z²/n; center=(p+z²/(2n))/d; margin=z*sqrt(p*(1-p)/n+z²/(4n²))/d. Candidate gate known>=.85, unknown<=.05, every class>=.75; even pass retains baseline pending physical/resources.', ['G5.2', 'G5.4', 'G5.5'],
    ['tools/test_camera_accuracy.py'],
    [({'knownCorrectAccepted': 3, 'knownN': 4}, {'rate': 0.75, 'wilson95Approx': [0.300641842582402, 0.9544127391903]}, 'Wilson95 with pinned z'),
     ({'unknownAccepted': 1, 'unknownN': 20}, {'falseAcceptRate': 0.05}, 'Inclusive quality threshold; accepted baseline unknown counts even when mapped unknown'),
     ({'n': 0}, {'rate': None, 'wilson95': None}, 'No sample means unavailable'),
     ({'baselineRawLabel': 'unmapped'}, {'result': 'ValueError'}, 'No guessed mapping'),
     ({'threshold': 'NaN or bool'}, {'result': 'ValueError'}, 'Finite numeric validation'),
     ({'knownRate': 0.85, 'unknownRate': 0.05, 'minimumClassRate': 0.75}, {'numericQualityGate': True, 'rolloutAuthorized': False}, 'All thresholds inclusive; no tuning on fresh test')])

add(10, 'Recognized-text similarity and speech state', 'transcript-edit-distance-v1; durable speech evidence identity separate',
    [('lib/features/media_practice/application/speech_practice_use_cases.dart', 'TranscriptPronunciationAssessment assess'),
     ('lib/features/media_practice/domain/speech_evidence_use_cases.dart', 'similarityAlgorithm'),
     ('lib/screens/shadowing_challenge_screen.dart', 'final assessment = speech.assess')],
    ['lib/features/media_practice/domain/speech_evidence_use_cases.dart'], ['lib/screens/shadowing_challenge_screen.dart'],
    ['target/transcript', 'session/attempt/final epoch', 'engine/locale/UTC timestamp', 'failure/cancel state'],
    'max(normalized target rune count, normalized transcript rune count)',
    'assess currently returns0 and false if either canonical text empty; failure/cancel callbacks must not create skill score. Empty final callback needs downstream no-evidence remediation.',
    'Trim/lower/collapse whitespace; round(clamp(100*(1-Levenshtein/maxRuneLength),0,100)); exact normalized equality separately. This is text matching, not acoustic pronunciation.', ['G6.4', 'G6.5'],
    ['test/features/media_practice/speech_practice_use_cases_test.dart', 'test/screens/shadowing_challenge_screen_test.dart'],
    [({'target': ' Apple ', 'transcript': 'apple'}, {'similarityPercent': 100, 'exact': True}, 'Case/trim normalization'),
     ({'target': 'cat', 'transcript': 'cut'}, {'distance': 1, 'denominator': 3, 'similarityPercent': 67, 'exact': False}, 'Nearest integer'),
     ({'target': 'cat', 'transcript': ''}, {'sourceHelperPercent': 0, 'desiredSkillScore': None, 'desiredDisposition': 'noEvidence'}, 'B01-FORM-02 separates observed helper behavior from desired consumer gate'),
     ({'cancelThenLateFinal': True}, {'durableNewAnswers': 0}, 'Attempt retirement'),
     ({'deviceFailure': True}, {'skillPercent': None}, 'Unavailable device is not zero skill')], ['B01-FORM-02'])

add(11, 'Word and sentence construction', 'native-word-scramble:v1 / native-sentence-scramble:v1; recreational evidence',
    [('lib/features/learning/application/native_mode_adapters.dart', 'final class WordScrambleModeAdapter'),
     ('lib/features/learning/application/native_mode_adapters.dart', 'final class SentenceScrambleModeAdapter'),
     ('lib/screens/word_scramble_screen.dart', 'slotLetterIndexes'),
     ('lib/screens/sentence_scramble_screen.dart', 'void _selectWord')],
    ['lib/features/learning/data/drift_learning_repository.dart'], ['lib/screens/word_scramble_screen.dart', 'lib/screens/sentence_scramble_screen.dart'],
    ['validated target/response', 'occurrence-index tile/token selection', 'attempt/owner/session', 'evidence profile'],
    'None; exact correctness boolean, not partial-match percentage',
    'Empty response allowed and incorrect for nonempty target; empty target rejected. Missing route/content unavailable.',
    'Word case-sensitive exact string; Sentence trim/collapse spacing then case/punctuation-sensitive equality. Banks provide construction support and remain recreational, not independent recall.', ['G2.5'],
    ['test/features/learning/native_mode_adapters_test.dart', 'test/screens/word_scramble_screen_test.dart', 'test/screens/sentence_scramble_screen_test.dart'],
    [({'wordTarget': 'letter', 'response': 'letter'}, {'correct': True, 'evidenceClass': 'recreational'}, 'Repeated t/e retained by occurrence indexes'),
     ({'wordTarget': 'letter', 'response': 'Letter'}, {'correct': False}, 'Case sensitive'),
     ({'sentenceTarget': 'I can can.', 'response': ' I  can can. '}, {'correct': True}, 'Spacing normalization preserves duplicate token'),
     ({'sentenceTarget': 'I can can.', 'response': 'I can can'}, {'correct': False}, 'Punctuation not stripped'),
     ({'returnTileOccurrence': 2, 'sameLetterOtherOccurrence': 3}, {'returned': [2], 'otherRemainsPlaced': True}, 'Identity fixture for G2.5 widget verification')])

add(12, 'AI attempts, usage and central cost', 'AiUsage schema1; source-pinned CentralCostBaseline policy (no live price)',
    [('lib/features/ai_tutor/data/drift_ai_usage_repository.dart', 'Future<AiUsageFinalizeResult> finalizeForOwner'),
     ('lib/features/ai_tutor/domain/ai_tutor_contracts.dart', 'final class AiUsageSummary'),
     ('lib/runtime/central_cost_policy.dart', 'CentralCostAssessment assess')],
    ['lib/features/ai_tutor/application/ai_tutor_use_cases.dart', 'lib/features/ai_tutor/data/drift_ai_usage_repository.dart'],
    ['lib/features/ai_tutor/data/drift_ai_usage_repository.dart', 'lib/runtime/central_cost_policy.dart'],
    ['owner/event/provider/model/attempt outcome', 'reported token counts/cost microsUSD', 'latency', 'required central component monthlyTHB'],
    'Per terminal request; sums grouped by provider/model; central budget is sum of required central monthlyTHB only',
    'Unreported tokens/cost stay null; knownTokens is partial sum; required unknown central price -> unknown; no guessed conversion or current provider price',
    'pending→terminal once; identical finalize alreadyFinalized; contradictory terminal throws. TotalTokens/cost present only if all terminal rows reported; knownTokens separate. Central total<=100THB withinBudget, >100 outOfBudget.', ['G6.1', 'G6.3', 'G6.6'],
    ['test/features/ai_tutor/drift_ai_usage_repository_test.dart', 'test/runtime/central_cost_policy_test.dart'],
    [({'sameFinalizationDeliveredTwice': True}, {'terminalRequests': 1, 'secondResult': 'alreadyFinalized'}, 'Owner/event pending update guard'),
     ({'reportedTokens': [10, None], 'reportedCostMicrosUsd': [5, None]}, {'knownTokens': 10, 'totalTokens': None, 'reportedCount': 1, 'requestCount': 2, 'totalCostMicrosUsd': None}, 'Partial reporting is not zero'),
     ({'reportedTokens': [0], 'reportedCostMicrosUsd': [0]}, {'totalTokens': 0, 'totalCostMicrosUsd': 0}, 'Explicit reported zero preserved'),
     ({'requiredCentralMonthlyThb': [40, 60]}, {'total': 100, 'state': 'withinBudget'}, 'Inclusive budget bound'),
     ({'requiredCentralMonthlyThb': [40, 61]}, {'total': 101, 'state': 'outOfBudget'}, 'Over budget'),
     ({'requiredCentralMonthlyThb': [None]}, {'total': None, 'state': 'unknown'}, 'No free-tier assumption')])

result = {'schemaVersion': 1, 'bundleId': 'B01', 'packageId': 'G0.7',
          'sourceSha': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip(),
          'scope': 'Formula source inspection and downstream fixture specification; no production calculator or runtime PASS.',
          'records': records}
(OUT / 'G0.7-formula-registry.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'formulas': len(records), 'fixtures': sum(len(r['fixtures']) for r in records)}))
