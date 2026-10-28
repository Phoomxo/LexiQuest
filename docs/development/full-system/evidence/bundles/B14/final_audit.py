"""Audit inherited evidence, gate hashes and the source delta for G6 closure."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[6]
OUT = Path(__file__).resolve().parent
BASE = 'c02b612a9b287b0cbd8aac2a49d00736d3e004c7'

def sha(data):
    return hashlib.sha256(data).hexdigest()

inherited = json.loads((OUT.parent / 'B13/B13-artifact-index.json').read_text(encoding='utf-8-sig'))
checkout_deltas = []
for item in inherited['artifacts']:
    actual = (ROOT / item['path']).read_bytes()
    committed = subprocess.check_output(['git', 'show', BASE + ':' + item['path']], cwd=ROOT)
    assert sha(committed) == item['sha256'].lower(), item['path']
    assert len(committed) == item['bytes'], item['path']
    if actual != committed:
        assert actual.replace(b'\r\n', b'\n') == committed.replace(b'\r\n', b'\n'), item['path']
        checkout_deltas.append({'path': item['path'], 'reason': 'checkout line endings only'})

rows = []
for manifest in sorted((OUT / 'gates').glob('*/*.json')):
    data = json.loads(manifest.read_text(encoding='utf-8-sig'))
    deltas = []
    for entry in data['inputClosure']:
        current = (ROOT / entry['path']).read_bytes()
        expected = entry['sha256'].lower()
        if sha(current) == expected:
            continue
        lf = current.replace(b'\r\n', b'\n')
        newline_only = expected in (sha(lf), sha(lf.replace(b'\n', b'\r\n')))
        deltas.append({'path': entry['path'], 'newlineOnly': newline_only,
                       'recorded': expected, 'current': sha(current)})
    for command in data['commands']:
        for stream in ('Stdout', 'Stderr'):
            original = Path(command[stream])
            copied = manifest.parent / original.parent.name / original.name
            assert sha(copied.read_bytes()) == command[stream + 'Hash'].lower(), str(copied)
    rows.append({'gate': str(manifest.relative_to(OUT)).replace('\\', '/'),
                 'status': data['status'], 'inputs': len(data['inputClosure']),
                 'exact': len(data['inputClosure']) - len(deltas), 'deltas': deltas})

changes = subprocess.check_output(['git', 'diff', BASE, '--name-only', '--', 'lib'], cwd=ROOT, text=True).splitlines()
assert not any(p.startswith('lib/features/ai_tutor/') for p in changes)
result = {'baseSha': BASE, 'inheritedArtifactCount': len(inherited['artifacts']),
          'inheritedCommittedByteHashesVerified': True, 'inheritedCheckoutDeltas': checkout_deltas, 'productionDelta': changes,
          'B13Reuse': 'AI request/adapters/accounting source unchanged. UI plus shared speech consumers reverified in B14. No global fingerprint equivalence claimed.',
          'gates': rows}
(OUT / 'final-input-audit.json').write_bytes((json.dumps(result, indent=2) + '\n').encode())
print(json.dumps({'inheritedVerified': len(inherited['artifacts']), 'gatesAudited': len(rows), 'productionDelta': changes}))
