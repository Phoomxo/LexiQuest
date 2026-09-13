"""Match requested Flutter tests to prior passed receipts by actual import inputs."""
import hashlib
import json
import re
from pathlib import Path

root = Path.cwd()
evidence = Path(__file__).parent

def closure(target):
    todo = [root / target]
    seen = {'pubspec.yaml', 'pubspec.lock'}
    while todo:
        path = todo.pop().resolve()
        if not path.is_file() or not path.is_relative_to(root):
            continue
        name = path.relative_to(root).as_posix()
        if name in seen:
            continue
        seen.add(name)
        for directive in re.findall(r'\b(?:import|export|part)\s+(?!of\b)[^;]+;', path.read_text(encoding='utf-8-sig')):
            for ref in re.findall(r"['\"]([^'\"]+\.dart)['\"]", directive):
                if ref.startswith('package:vocab_learning_app/'):
                    todo.append(root / 'lib' / ref.split('/', 1)[1])
                elif ':' not in ref:
                    todo.append(path.parent / ref)
    return {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in seen}

results = []
for target in ['test/features/ai_tutor/ai_gateway_loopback_test.dart', 'test/runtime/central_cost_policy_test.dart', 'test/scenarios/ai_voice_fallback_journey_test.dart', 'test/voice/voice_service_factory_test.dart']:
    inputs = closure(target)
    candidates = []
    for bundle in ['B13', 'B14', 'B16']:
        for path in (evidence.parent/bundle).rglob('*.json'):
            data = json.loads(path.read_text(encoding='utf-8-sig'))
            if not isinstance(data, dict) or not data.get('inputClosure'):
                continue
            selection = data.get('selection', [])
            if not any(target in c.get('Arguments', []) for c in selection):
                continue
            commands = data.get('results', data.get('commands', []))
            if not commands or any(c.get('Status') not in ['Passed', 'Reused'] for c in commands):
                continue
            # Name-filtered executions do not establish the whole target.
            if any('--plain-name' in c.get('Arguments', []) or '--name' in c.get('Arguments', []) for c in selection):
                continue
            pins = {r['path']: r['sha256'].lower() for r in data['inputClosure']}
            changed, eol = [], []
            for n,h in inputs.items():
                if pins.get(n) == h:
                    continue
                raw = (root/n).read_bytes()
                normalized = raw.replace(b'\r\n', b'\n')
                variants = [normalized, normalized.replace(b'\n', b'\r\n')]
                if b'\0' not in raw and pins.get(n) in [hashlib.sha256(v).hexdigest() for v in variants]:
                    eol.append(n)
                else:
                    changed.append(n)
            candidates.append({'receipt': path.relative_to(root).as_posix(), 'changedOrMissing': changed, 'verifiedEolOnly': eol})
    matches = [c for c in candidates if not c['changedOrMissing']]
    results.append({'target': target, 'inputs': len(inputs), 'reuse': matches[-1] if matches else None, 'candidates': candidates,
                    'scope': 'Exact own-package import/export/part closure plus pubspec; no blanket environment or verifier fingerprint equality'})
evidence.joinpath('G7.6-flutter-reuse.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
print(json.dumps([{k:v for k,v in r.items() if k != 'candidates'} for r in results]))
