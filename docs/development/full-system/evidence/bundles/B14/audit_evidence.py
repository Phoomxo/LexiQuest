"""Preserve bounded verifier manifests/raw bytes and audit current inputs."""
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[6]
OUT = Path(__file__).resolve().parent

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run():
    rows = []
    for source in sorted((ROOT / 'build/verification').glob('*/targeted-*.json')):
        data = json.loads(source.read_text(encoding='utf-8-sig'))
        dest = OUT / 'gates' / source.parent.name / source.name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, dest)
        mismatches = [entry['path'] for entry in data['inputClosure']
                      if not (ROOT / entry['path']).is_file()
                      or digest(ROOT / entry['path']).lower() != entry['sha256'].lower()]
        logs = []
        for command in data['commands']:
            for kind in ('Stdout', 'Stderr'):
                original = Path(command[kind])
                target = dest.parent / original.parent.name / original.name
                target.parent.mkdir(exist_ok=True)
                shutil.copyfile(original, target)
                expected = command.get(kind + 'Hash')
                assert expected is None or digest(target) == expected.lower(), str(target)
                logs.append({'path': str(target.relative_to(ROOT)).replace('\\', '/'),
                             'sha256': digest(target), 'bytes': target.stat().st_size})
        rows.append({'manifest': str(dest.relative_to(ROOT)).replace('\\', '/'),
                     'status': data['status'], 'fingerprint': data['fingerprint'],
                     'inputCount': len(data['inputClosure']),
                     'currentInputMismatches': mismatches, 'logs': logs})
    (OUT / 'gate-audit.json').write_text(json.dumps(rows, indent=2) + '\n', encoding='utf-8')
    print(json.dumps([{'status': r['status'], 'inputs': r['inputCount'],
                       'mismatches': len(r['currentInputMismatches'])} for r in rows]))

if __name__ == '__main__':
    run()
