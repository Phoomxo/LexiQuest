"""Bounded source-inspection acceptance, independent of Flutter/runtime gates."""
import hashlib
import json
import platform
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
OUT = Path(__file__).resolve().parent
START = time.perf_counter()
COMMANDS = []

def git(*args):
    start = time.perf_counter()
    result = subprocess.run(['git', *args], cwd=ROOT, capture_output=True, check=True)
    COMMANDS.append({'command': ['git', *args], 'exitCode': result.returncode,
                     'durationMs': round((time.perf_counter() - start) * 1000, 3)})
    return result.stdout.decode('utf-8').strip()

def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def check_tree(sha):
    entries = {}
    for line in git('ls-tree', '-rl', sha).splitlines():
        meta, path = line.split('\t', 1)
        mode, kind, blob, size = meta.split()
        if kind == 'blob':
            entries[path] = {'blob': blob, 'bytes': int(size)}
    return entries

ledger = load(OUT / 'semantic-ledger.json')
census = load(OUT / 'census.json')
base, main, r15 = (ledger[k] for k in ('acceptedInput', 'mainPin', 'r15Pin'))
assert git('rev-parse', '--git-common-dir').replace('\\', '/').lower() == 'c:/users/phet/documents/lexiquest/.git'
assert git('rev-parse', 'HEAD') == base
assert git('branch', '--show-current') == 'codex/g0-3-semantic-authority'
assert not census['residualInventoryPaths']
assert len(ledger['records']) == 430
assert len(ledger['excludedMergeNodes']) == 10
assert len({r['sha'] for r in ledger['records']}) == 430
trees = {sha: check_tree(sha) for sha in (main, r15, base)}
packages_path = ROOT / 'docs/development/2026-09-13-full-system-work-ledger.json'
packages = load(packages_path)
package_ids = {r['id'] for r in packages['packages']}
allowed = {'applicable', 'equivalent', 'conflict', 'superseded'}
for side, tip, other in [('main', main, r15), ('R15', r15, main)]:
    records = {r['sha']: r for r in ledger['records'] if r['side'] == side}
    # Independent single Git log query compares full per-commit changed-path sets.
    raw = git('log', '--no-merges', '--no-renames', '--format=COMMIT:%H', '--name-only', f'{other}..{tip}')
    observed = {}
    current = None
    for line in raw.splitlines():
        if line.startswith('COMMIT:'):
            current = line[7:]
            observed[current] = set()
        elif line:
            observed[current].add(line)
    assert set(observed) == set(records)
    for sha, paths in observed.items():
        row = records[sha]
        assert paths == {c['path'] for c in row['changes']}, sha
        assert re.fullmatch('[0-9a-f]{64}', row['patchSha256'])
        assert row['disposition'] in allowed and row['reason'] and row['decision']
        for change in row['changes']:
            assert change['ownerPackage'] in package_ids
            assert change['disposition'] in allowed and change['reason']
            for key, pin in [('main', main), ('r15', r15), ('accepted', base)]:
                assert change[key] == trees[pin].get(change['path'])
            if change['disposition'] == 'equivalent':
                assert change['main'] == change['r15']

assert census['changeRows'] == sum(len(r['changes']) for r in ledger['records']) == 4886
assert census['uniquePaths'] == len({c['path'] for r in ledger['records'] for c in r['changes']}) == 1603
authority = ROOT / 'docs/development/full-system/G0.3-authority.md'
checkpoint = ROOT / 'docs/development/full-system/checkpoints/G0.3.md'
for row in packages['packages']:
    if 'sourceReconciliation' in row:
        ref = row['sourceReconciliation']
        assert (ROOT / ref['authority']).is_file() and (ROOT / ref['ledger']).is_file()
        assert all(f'### {d} ' in authority.read_text(encoding='utf-8') for d in ref['decisions'])
for document in (authority, checkpoint):
    for target in re.findall(r'\]\(([^)]+)\)', document.read_text(encoding='utf-8')):
        if target.endswith('verification.json'):
            assert (document.parent / target).resolve() == OUT / 'verification.json'
        else:
            assert (document.parent / target).is_file(), target

# The only modifications to the inherited work ledger are current acceptance
# and source-reconciliation pointers. No historical coverage PASS is fabricated.
old_packages = json.loads(git('show', f'{base}:docs/development/2026-09-13-full-system-work-ledger.json'))
normalized = json.loads(json.dumps(packages))
for row in normalized['packages']:
    row.pop('sourceReconciliation', None)
    if row['id'] == 'P0.3':
        row.pop('checkpoint', None)
        row['status'] = 'waiting-predecessor'
assert normalized == old_packages
changed = git('diff', '--name-only', base).splitlines()
untracked = git('ls-files', '--others', '--exclude-standard').splitlines()
assert changed == ['docs/development/2026-09-13-full-system-work-ledger.json']
assert all(p.startswith('docs/development/full-system/') for p in untracked)
git('diff', '--check')

repair_paths = ['lib/screens/ai_tutor_screen.dart', 'test/screens/ai_tutor_screen_test.dart',
                'tool/cli/tests/r15-scope.tests.ps1', 'tool/cli/verify-scope.ps1',
                'tools/camera_accuracy.py', 'tools/test_camera_accuracy.py']
repair_pins = {p: trees[base][p] for p in repair_paths}
config_paths = ['pubspec.yaml', 'pubspec.lock', 'package.json', 'package-lock.json',
                'android/app/build.gradle.kts', 'backend/voice_api/pyproject.toml',
                'backend/voice_api/uv.lock', 'firestore.rules', 'firebase.json']
config_pins = {p: trees[base][p] for p in config_paths}
artifact_paths = [authority, checkpoint, packages_path, OUT / 'semantic-ledger.json',
                  OUT / 'census.json', OUT / 'inspect_git.py', Path(__file__).resolve()]
artifacts = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in artifact_paths}
payload = {'schemaVersion': 1, 'gate': 'G0.3-source-inspection', 'result': 'PASS',
           'timestampUtc': datetime.now(timezone.utc).isoformat(),
           'command': 'python -B docs/development/full-system/evidence/G0.3/verify_inspection.py',
           'exitCode': 0, 'durationMs': round((time.perf_counter() - START) * 1000, 3),
           'sourceFingerprint': {'acceptedInput': base, 'main': main, 'r15': r15,
                                 'acceptedTree': git('rev-parse', f'{base}^{{tree}}')},
           'environment': {'python': platform.python_version(), 'platform': platform.platform(),
                           'git': git('--version')},
           'counts': {'nonMerge': 430, 'mergeExcluded': 10, 'changeRows': 4886, 'uniquePaths': 1603, 'unassigned': 0},
           'repairPinsUnchanged': repair_pins, 'dependencyConfigPins': config_pins,
           'dependencyConfigFingerprint': hashlib.sha256(json.dumps(config_pins, sort_keys=True).encode()).hexdigest(),
           'artifactHashes': artifacts, 'commands': COMMANDS,
           'evidenceReuse': 'G0.2 runtime evidence retained as prior accepted evidence; no runtime gate claimed or rerun. No tracked application input changed.',
           'notRun': ['Flutter', 'backend', 'Android', 'GPU', 'full release', 'physical/live/human'],
           'limitations': 'Git/JSON/path/hash completeness validates the source-disposition record; manual authority review is in G0.3-authority.md. No intermediate R15 commit runtime tested.'}
(OUT / 'verification.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'result': 'PASS', 'counts': payload['counts'], 'durationMs': payload['durationMs']}))
