"""Audit recorded gates against final B13 files without repeating passed tests."""
import hashlib
import json
import subprocess
from pathlib import Path

root = Path.cwd()
evidence = root / 'docs/development/full-system/evidence/bundles/B13'
base = 'c24ddd04492816f07676daf094fa1297f13078b7'
allowed = {
    '.gitattributes': 'Evidence-only binary log/LF JSON rules.',
    'lib/screens/ai_tutor_screen.dart': 'G6.2 scoped mic-stop catch, tested UI/speech40; LF/CRLF normalized separately.',
    'lib/features/ai_tutor/data/ai_tutor_gateway_factory.dart': 'G6.3 bridge guard, tested adapters and provider lifecycle74.',
    'test/features/ai_tutor/ai_tutor_use_cases_test.dart': 'G6.3 appended no-key test passed; existing tests unchanged.',
    'test/screens/ai_tutor_screen_test.dart': 'G6.2 regression and G6.3 no-key coverage; no old tests removed.',
    'test/features/ai_tutor/ai_gateway_adapters_test.dart': 'G6.3 bridge regression and full adapter rerun.',
    'test/features/ai_tutor/ai_gateway_loopback_test.dart': 'G6.3 additive5xx/retry cases;5new cases passed; prior21 cases unchanged.',
}
results = []
for path in sorted(evidence.glob('G6.*-gate*/targeted-*.json')):
    gate = json.loads(path.read_text(encoding='utf-8-sig'))
    exact = 0
    deltas = []
    for item in gate['inputClosure']:
        current = root / item['path']
        digest = hashlib.sha256(current.read_bytes()).hexdigest()
        if digest.lower() == item['sha256'].lower():
            exact += 1
        else:
            deltas.append({'path': item['path'], 'recorded': item['sha256'],
                           'current': digest, 'disposition': allowed.get(item['path'], 'Pre-fix input retained in red gate'),
                           'crlfOnly': hashlib.sha256(current.read_bytes().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')).hexdigest().lower() == item['sha256'].lower()})
    # Failed/red gates intentionally retain pre-fix input hashes.
    status = gate.get('status', '')
    if status == 'Passed':
        assert all(d['path'] in allowed for d in deltas), deltas
        assert all(c['ExitCode'] == 0 for c in gate['commands'])
    for command in gate['commands']:
        for kind in ('Stdout', 'Stderr'):
            original = Path(command[kind])
            retained = path.parent / original.parent.name / original.name
            assert hashlib.sha256(retained.read_bytes()).hexdigest().lower() == command[kind + 'Hash'].lower(), retained
    results.append({'gate': str(path.relative_to(evidence)), 'fingerprint': gate['fingerprint'],
                    'status': status, 'rawExactInputs': exact, 'deltas': deltas})

changed = subprocess.check_output(['git', 'diff', base, '--name-only', '--', 'lib', 'test'], text=True).splitlines()
expected = set(allowed) | {'lib/features/ai_tutor/application/ai_tutor_use_cases.dart', 'lib/runtime/app_bootstrap.dart'}
assert set(changed) <= expected, changed
baseline_paths = ['lib/features/device_model/domain/model_manifest.dart', 'tools/camera_development_evaluation.py']
for name in baseline_paths:
    accepted = subprocess.check_output(['git', 'show', f'{base}:{name}'])
    current = (root / name).read_bytes()
    assert accepted.replace(b'\r\n', b'\n') == current.replace(b'\r\n', b'\n'), name
report = {'baseSha': base, 'gates': results, 'reviewedRuntimeDelta': changed,
          'unchangedBaselineAndEvaluation': baseline_paths,
          'globalFingerprintEquivalent': False,
          'reuseDecision': 'Use-case/bootstrap/Gemini original tests retained for unchanged behavior; UI40 and adapters74 supersede affected paths; five new sockets and two no-key tests supplement. Raw red failures are not reusable PASS.',
          'limitations': 'No physical/live/fullrelease claim. CRLF-only normalized source is not raw equality.'}
(evidence / 'input-audit.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'gates': len(results), 'runtimeDelta': changed, 'baselineUnchanged': True}))
