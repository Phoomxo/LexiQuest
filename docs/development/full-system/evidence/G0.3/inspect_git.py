"""Reproduce the pinned G0.3 commit/path census; never modifies application code."""
import hashlib
import json
import subprocess
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
OUT = Path(__file__).resolve().parent
MAIN = '7b8ac6cc029c0df43f9d4e7d161da3502e6f557b'
R15 = 'f4eebb895836349fbf8e9960312a78bad524d462'
BASE = 'e1b3fcb17fbdbdab158780142383f3ee15d8da0a'

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

def text(*args):
    return git(*args).decode('utf-8').strip()

def tree(sha):
    result = {}
    for line in git('ls-tree', '-rlz', sha).split(b'\0'):
        if not line:
            continue
        meta, path = line.split(b'\t', 1)
        mode, kind, blob, size = meta.split()
        if kind == b'blob':
            result[path.decode()] = {'blob': blob.decode(), 'bytes': int(size)}
    return result

# Explicit decisions for every main non-merge commit. These are semantic
# dispositions, not a claim that the cumulative R15 implementation is tested.
# The authority report defines D01-D12 and the exact required follow-up.
MAIN_DECISIONS = '''
f2aa7565 applicable P1.7 D01 Defer remote SDK access until invocation; retain this invariant in R15 factory composition.
361389a0 applicable P7.7 D08 Preserve offline/no-AI build support when reconciling protected release workflow.
2fb5c0ba conflict P7.3 D04 Preserve reversible catalog transaction design; do not migrate remote products into local reward catalog automatically.
c8908dcf equivalent P7.7 D06 Android Firebase options match; R15 additionally retains old client entry as historical compatibility.
b9039b58 applicable P7.7 D08 Create artifact/SBOM output directory before generation.
f4516d36 applicable P7.7 D08 Require signed AAB verification and fail missing artifacts.
cddb2321 applicable P7.7 D08 Carry device/production/dependency gate intent into current release tools; do not restore obsolete workflow wholesale.
15e3f232 applicable P7.7 D07 Root npm uuid override is absent in R15 and resolved uuid is 9.0.1; evaluate compatible remediation.
6d546650 applicable P7.7 D07 Keep functions uuid remediation as candidate if functions selected; its absence is not proof of root remediation.
0aaf1f0d superseded P0.6 D12 Formatting-only runtime test layout carries no behavior to port.
c1b7e4c2 conflict P7.1 D04 Main progress/session callable sync and R15 leased outbox have different authority and payloads.
8159eb7b conflict P7.3 D04 Main backend writer has idempotent transactions but trusts submitted correctAnswers; not equivalent to canonical evidence validation.
7abc4204 conflict P1.5 D03 Atomic scheduler projections must use canonical R15 transaction and evidence identity; no second repository.
20856d9b conflict P1.5 D03 Review main deterministic scheduler formula against R15 evidence policy; retain owner and versioned scheduling authority.
384c723c superseded P0.6 D12 Constructor lint cleanup is historical; current adapters own behavior.
06063884 conflict P1.7 D01 Keep optional enrichment and availability intent in current composition; no old learning dependency graph.
58886273 applicable P6.4 D05 Preserve deterministic reading/voice fallback behavior in current adapters.
35b9d91e conflict P2.8 D05 Map six-stage reading flow to canonical R15 session/recovery; do not reinstate legacy session writer.
01af8df0 conflict P2.8 D05 Retain durable ordered coordinator intent through R15 associative adapter and canonical completion.
dc6e508c applicable P3.1 D05 Preserve curated offline reading source and versioned content choice.
75a9f881 conflict P1.5 D03 Compare vocabulary mixing policy under current content/evidence pins before adoption.
b24f15df superseded P0.6 D12 Migration test line-ending normalization has no semantic port.
d730e261 conflict P1.4 D02 Preserve offline owner-bound associative memory using AppDatabase; never open a parallel learning store.
5f704eb8 conflict P1.7 D01 Preserve failure/availability gating under R15 AppDependencies; old flags do not become second authority.
cbf52d8c applicable P1.7 D02 Port safe-open integrity/future-schema/error-disposal requirements to AppDatabase; legacy factory is empty in R15.
cc3b21ad conflict P1.4 D02 Preserve atomic commit/outbox/idempotency invariants through canonical R15 repository; schema1 is not schema26.
b38a5971 superseded P1.4 D02 Separate learning.sqlite schema1 is replaced by AppDatabase schema26; legacy import requires explicit compatibility design.
f0bfc1ea conflict P1.4 D03 Preserve validated owner/id/time/commit semantics without reintroducing a second evidence contract.
54ee7b27 applicable P7.7 D07 Review narrow historical fixture exception against current configuration; no blanket exception or scan activation.
ac2ea37b conflict P7.5 D09 Storage configuration required only for an edition that enables storage; optional local startup must remain possible.
efd6d3b8 applicable P5.1 D10 Preserve simulated scanner exclusion; R15 physical scanner and its uncertainty UI remain current.
830f5ee4 conflict P7.3 D09 R15 omits other-bucket closure and legacy broad-policy removal; audit forward migration before any storage activation.
6f073f2a conflict P4.5 D04 Remote client-economy write prohibition survives; local separated ledger replaces disabled legacy shop behavior.
eeb29a81 superseded P0.4 D08 Bounded runner evolved into accepted F2; preserve no-wide-rerun rules and inspect current closure.
b73f206b applicable P0.4 D08 Retain isolated backend dev-environment provisioning in command registry without running backend here.
57e12ca9 applicable P7.3 D04 Fail-closed missing auth-provider check is missing from R15 isRegisteredUser and must be reconciled.
844563f2 applicable P7.3 D04 Retain anonymous/private/shared-write restrictions for legacy paths without deleting valid versioned field_users rules.
9c7e606a superseded P0.6 D12 Historical Release A planning; active sequential-3 plan controls execution.
0008cfb6 applicable P7.4 D11 Preserve empty-export rejection; research execution remains excluded.
4906e2dd superseded P0.6 D12 Historical Release A gates are references, not current package commands.
cfbe3ae5 superseded P0.6 D12 Historical Release A plan replaced by active master; retain provenance.
1e0e2d6c applicable P7.3 D04 Legacy client-authoritative economy write lockdown must not be discarded because R15 uses a new ledger.
7d681498 applicable P7.4 D11 Keep no-fabricated-outcomes and evidence-derived achievements/export semantics.
2276dcb4 applicable P7.4 D11 Preserve result/research integrity and owner-specific failure behavior; inspect mapped consumers before any selective port.
04e2f8f2 conflict P4.5 D04 Preserve remote reward prohibition while retaining legitimate local evidence-derived rewards and separated XP/coins.
20e40da5 applicable P7.4 D11 Keep undefined-latency result rejection; no research report execution in production package.
7bec4825 applicable P7.4 D11 Keep observation provenance and non-fabricated charts; old research routes are not activated.
f66d0316 conflict P7.6 D07 Voice GPU dependency set differs materially; main runtime-compat remediation requires compatibility review before any GPU deployment.
'''
DECISIONS = {}
for line in MAIN_DECISIONS.strip().splitlines():
    prefix, disposition, owner, decision, reason = line.split(' ', 4)
    DECISIONS[prefix] = (disposition, owner, decision, reason)

# Path ownership is intentionally independent of commit subjects: broad commits
# can have changes in multiple packages. P0.5 owns residual inventory triage.
RULES = [
    ('P0.6', r'(^docs/|^\.superpowers/|agents\.md$|\.gitattributes$|\.gitignore$)'),
    ('P7.7', r'(firebase_options|^firebase\.json$|^hosting/|device_certification)'),
    ('P0.4', r'(test_plan|test/phase_minus_1/)'),
    ('P1.7', r'(runtime_kill_switch|local_first_authority|provider_composition|fitness_test)'),
    ('P2.7', r'(production_feature_delivery|production_feature_invocation)'),
    ('P4.2', r'notification_platform'),
    ('P1.4', r'(current_database_contract|schema_v25_fixture|persistent_manual_qa_storage)'),
    ('P2.1', r'r15_visual_capture'),
    ('P1.5', r'(/events/|cosine_similarity|zpd_)'),
    ('P5.1', r'(media_practice|device_model|ml_image_labeling)'),
    ('P4.3', r'(timezone_policy|local_study_datetime)'),
    ('P3.4', r'/review/'),
    ('P3.1', r'(suggestion|vocab_service)'),
    ('P1.1', r'(auth_service|user_service)'),
    ('P6.4', r'(audio|phoneme|pitch_calibration|pronunciation)'),
    ('P7.1', r'background_service'),
    ('P2.8', r'(storybook|story_contextualizer)'),
    ('P7.3', r'(^firestore|^supabase/|^functions/|test/security/)'),
    ('P7.7', r'(^android/|^ios/|^macos/|^windows/|^linux/|^web/|^\.github/|pubspec|package(-lock)?\.json|osv|gitleaks)'),
    ('P0.4', r'(^tool/|^integration_test/)'),
    ('P7.6', r'^backend/'),
    ('P5.4', r'(^tools/|dataset|training|camera_accuracy|model_manifest|^assets/models/)'),
    ('P7.4', r'(research|export|deletion|erasure|delete_account)'),
    ('P1.1', r'(identity|owner|guest_session|account|entry_state|session/domain)'),
    ('P7.1', r'(sync|outbox)'),
    ('P1.4', r'(data/local|learning/storage|migration|recovery|restart|learning_repository)'),
    ('P1.7', r'(runtime/|app_config|bootstrap|main\.dart$)'),
    ('P2.2', r'(pair|matching)'),
    ('P2.4', r'cloze'),
    ('P2.5', r'(word_quest|wordquest|scramble)'),
    ('P2.6', r'(flashcard|scratchpad|handwriting)'),
    ('P2.8', r'(adventure|associative|reading|ghost)'),
    ('P6.5', r'(shadowing|dictation|speaking|speech_evidence)'),
    ('P6.4', r'(voice|speech|tts)'),
    ('P6.1', r'(ai_tutor|gemini|ai_|/ai/)'),
    ('P5.1', r'(camera|scanner|model_|litert|inference|benchmark)'),
    ('P4.5', r'(reward|achievement|companion|avatar|shop|wallpaper|economy)'),
    ('P4.4', r'(quest|streak)'),
    ('P4.2', r'(goal|countdown|reminder)'),
    ('P4.3', r'(focus_timer|time_tracking|learning_time)'),
    ('P4.6', r'(preference|setting|onboarding|theme|motion)'),
    ('P4.1', r'(today|navigation|home|choose_mode|drawer|glossary)'),
    ('P3.6', r'assessment'),
    ('P3.5', r'(progress|dashboard|calendar|analytics|score)'),
    ('P3.4', r'(history|review_center|saved_learning)'),
    ('P3.3', r'(hint|feedback|explanation|bookmark|quality_report)'),
    ('P3.7', r'(offline|download|content_manifest)'),
    ('P3.1', r'(pack|catalog|content|vocabulary|lexical|dictionary|word_service|category)'),
    ('P1.5', r'(evidence|eligib|srs|scheduler|recommendation|memory_state|learning_event|projection)'),
    ('P2.7', r'(session_config|lesson_mode|lesson_shell|feature_contract|capability)'),
    ('P2.3', r'(quiz|recall|answer_attempt)'),
    ('P2.1', r'(widget|screen|accessibility|font|design|token|surface)'),
    ('P1.2', r'(learning|session|attempt)'),
]

def owner_for(path):
    import re
    for owner, pattern in RULES:
        if re.search(pattern, path.lower()):
            return owner
    return 'P0.5'

def build():
    trees = {p: tree(p) for p in (MAIN, R15, BASE)}
    records = []
    merges = []
    residual = set()
    for side, tip, other in [('main', MAIN, R15), ('R15', R15, MAIN)]:
        commits = text('rev-list', '--reverse', '--no-merges', f'{other}..{tip}').splitlines()
        merges += [{'side': side, 'sha': sha, 'reason': 'Merge node excluded; constituent non-merge changes inventoried.'}
                   for sha in text('rev-list', '--merges', f'{other}..{tip}').splitlines()]
        for sha in commits:
            subject = text('show', '-s', '--format=%s', sha)
            paths = git('diff-tree', '--no-commit-id', '--name-only', '-r', '--no-renames', '-z', sha).decode().strip('\0').split('\0')
            patch = git('show', '--format=', '--binary', '--no-ext-diff', '--no-renames', sha)
            if side == 'main':
                disposition, owner, decision, reason = DECISIONS[sha[:8]]
            else:
                disposition, owner, decision = 'applicable', None, 'D12'
                reason = 'Retain cumulative R15 baseline at pinned tip; later edits supersede earlier forms. This is source adoption, not runtime acceptance.'
            changes = []
            for path in paths:
                assigned = owner_for(path)
                if assigned == 'P0.5':
                    residual.add(path)
                source = trees[tip].get(path)
                accepted = trees[BASE].get(path)
                main_blob = trees[MAIN].get(path)
                r15_blob = trees[R15].get(path)
                change_disposition = disposition
                rationale = reason
                if side == 'main' and disposition == 'equivalent' and main_blob != r15_blob:
                    change_disposition = 'applicable'
                    rationale = 'Production Android identity intent retained in current selected client; surrounding native/config/test bytes differ and remain P7.7 verification inputs.'
                if side == 'R15':
                    if path.startswith('docs/') or path == 'AGENTS.md':
                        change_disposition = 'superseded'
                        rationale = 'Historical plan/evidence retained for provenance; active sequential-3 authority and G0.6 disposition govern use.'
                    elif not accepted or accepted['bytes'] <= 1:
                        change_disposition = 'superseded'
                        rationale = 'No active implementation at accepted path (absent/empty); retain historical delta and cumulative replacement, do not resurrect this file.'
                    elif main_blob and main_blob == r15_blob:
                        change_disposition = 'equivalent'
                        rationale = 'Exact endpoint Git blob equivalence; no port required.'
                    elif source != accepted:
                        change_disposition = 'superseded'
                        rationale = 'Accepted G0.1/G0.2 delta supersedes R15 tip bytes; accepted repairs/authority govern.'
                changes.append({'path': path, 'ownerPackage': assigned, 'disposition': change_disposition,
                                'reason': rationale, 'main': main_blob, 'r15': r15_blob, 'accepted': accepted})
            records.append({'sha': sha, 'side': side, 'subject': subject,
                            'patchSha256': hashlib.sha256(patch).hexdigest(),
                            'disposition': disposition, 'ownerPackage': owner or sorted({c['ownerPackage'] for c in changes}),
                            'decision': decision, 'reason': reason, 'changes': changes})
    assert len(DECISIONS) == 48
    assert Counter(r['side'] for r in records) == {'main': 48, 'R15': 382}
    payload = {'schemaVersion': 1, 'planRevision': '2026-09-13-sequential-3',
               'mainPin': MAIN, 'r15Pin': R15, 'acceptedInput': BASE,
               'mergeBase': text('merge-base', MAIN, R15),
               'scope': 'All unique non-merge commits and every changed path; disposition is cumulative source adoption, not per-commit test acceptance.',
               'records': records, 'excludedMergeNodes': merges}
    (OUT / 'semantic-ledger.json').write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    summary = {'nonMergeCommits': dict(Counter(r['side'] for r in records)),
               'mergeNodes': len(merges), 'changeRows': sum(len(r['changes']) for r in records),
               'uniquePaths': len({c['path'] for r in records for c in r['changes']}),
               'pathDispositions': dict(Counter(c['disposition'] for r in records for c in r['changes'])),
               'residualInventoryPaths': sorted(residual)}
    (OUT / 'census.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(summary, indent=2))

if __name__ == '__main__':
    build()
