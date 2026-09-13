"""G0.6 reversible classification; never deletes or moves source artifacts."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[6]
OUT = Path(__file__).parent
BASE = '6ab2e371fc4f7563da1ad8dc04a158d854b5dc20'

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

paths = git('ls-tree', '-r', '--name-only', BASE).decode().splitlines()
blobs = {line.split('\t', 1)[1]: line.split()[2] for line in git('ls-tree', '-r', BASE).decode().splitlines()}
texts = {}
for p in paths:
    f = ROOT / p
    if f.suffix in {'.md', '.json', '.yaml', '.yml', '.dart', '.py', '.ps1', '.gitignore'} and f.stat().st_size < 2_000_000:
        texts[p] = f.read_text(encoding='utf-8-sig', errors='replace').replace('\\', '/')

active = {'AGENTS.md', 'docs/development/full-system-active-index.md',
          'docs/development/full-system-package-workflow.md', 'docs/development/full-system-task-index.json',
          'docs/development/full-system-bundle-map.md', 'docs/development/2026-09-13-rule-supersession-register.md',
          'docs/superpowers/plans/2026-09-13-lexiquest-full-system-master-plan.md'}
contracts = {'docs/development/2026-09-13-full-system-work-ledger.json',
             'docs/development/2026-09-13-master-plan-coverage-audit.md',
             'docs/superpowers/specs/2026-09-13-minigame-coverage-contract.md',
             'docs/superpowers/specs/2026-09-12-r15-engineering-spec.md',
             'docs/superpowers/plans/2026-09-12-r15-acceptance-contract.md',
             'docs/superpowers/specs/2026-09-12-r15-source-register.md'}
records = []
for p in paths:
    if not (p.startswith('docs/') or p == 'AGENTS.md'):
        continue
    if p in active or p.startswith(('docs/superpowers/bundle-briefs/', 'docs/superpowers/task-briefs/full-system/')):
        category, reason = 'active', 'Current bundles-4 authority or requirement selected through active index.'
    elif p in contracts:
        category, reason = 'supporting-contract', 'Acceptance/source input subordinate to current Master and rule register; historical source observations are not fresh runtime claims.'
    elif 'r15-package-workflow' in p or 'r15-autonomous-development-roadmap' in p:
        category, reason = 'superseded', 'Execution authority replaced by bundles-4; retain historical identity and references.'
    else:
        category, reason = 'historical', 'Preserve design, observation, provenance or prior evidence; not an independent execution queue. Consult current contract before reusing claims.'
    records.append({'path': p, 'gitBlob': blobs[p], 'sha256': hashlib.sha256((ROOT / p).read_bytes()).hexdigest(),
                    'category': category, 'disposition': 'retain-in-place', 'reason': reason,
                    'replacementAuthority': 'docs/development/full-system-active-index.md',
                    'restore': {'commit': BASE, 'path': p, 'gitBlob': blobs[p]}})

failures = []
for p in paths:
    if '/failures/' not in p or not p.endswith('.png'):
        continue
    name = Path(p).name
    stem = re.sub(r'_(isolatedDiff|maskedDiff|masterImage|testImage)\.png$', '', name)
    refs = [q for q, txt in texts.items() if q != p and (p in txt or name in txt)]
    consumers = [q for q, txt in texts.items() if q.endswith('_test.dart') and stem in txt]
    golden = [q for q in paths if '/goldens/' in q and Path(q).name == stem + '.png']
    failures.append({'path': p, 'sha256': hashlib.sha256((ROOT / p).read_bytes()).hexdigest(), 'gitBlob': blobs[p],
                     'inboundLiteralReferences': refs, 'testStemConsumers': consumers, 'goldenCounterparts': golden,
                     'referenceScan': 'All tracked text files in declared extensions under 2MB; full path and basename, plus test stem. Dynamic references cannot be excluded.',
                     'category': 'cleanup-candidate', 'defectStatus': 'unresolved-provenance-no-closure-proof',
                     'disposition': 'retain-in-place', 'deletionEligible': False,
                     'reason': 'Failure evidence may explain unresolved historical golden mismatch; absent literal refs do not prove unused. Preserve until owner review ties artifact to closed defect.',
                     'archive': {'kind': 'existing-git-object', 'commit': BASE, 'gitBlob': blobs[p], 'moved': False},
                     'restore': {'commit': BASE, 'path': p, 'expectedSha256': hashlib.sha256((ROOT / p).read_bytes()).hexdigest()}})
save('G0.6-document-registry.json', {'schemaVersion': 1, 'sourceSha': BASE, 'records': records,
     'supersession': {'PLAN-04': 'Pre-R15 claims of missing conversation context or speech identity remain observations at their recorded source. Accepted G0.3 dispositions and G0.5 pins govern current ownership; G6.1/G6.4 verify actual behavior, not duplicate implementation.'}})
save('G0.6-cleanup-dry-run.json', {'schemaVersion': 1, 'sourceSha': BASE, 'mode': 'dry-run-retain',
     'scanFiles': len(texts), 'candidateCount': len(failures), 'plannedDeletes': [], 'plannedMoves': [],
     'protected': ['learning data', 'history', 'receipts', 'consent', 'migrations', 'goldens', 'provenance'],
     'restoreProtocol': 'Inspect target changes first. Recover pinned blob into a separate review directory, check expected SHA256, then restore only approved target. Never reset/clean or overwrite user files.',
     'records': failures})
print(json.dumps({'documents': len(records), 'failureCandidates': len(failures), 'deleted': 0, 'moved': 0}))
