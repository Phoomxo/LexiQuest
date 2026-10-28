"""Merge explicit observations without erasing earlier review/cross-check data."""
import datetime
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[6]
out = Path(__file__).resolve().parent
ledger_path = out / 'G8.2-review-ledger.json'
ledger = json.loads(ledger_path.read_text(encoding='utf-8'))
notes = {}
for observations in sorted(out.glob('review_observations_rev*.json')):
    incoming = json.loads(observations.read_text(encoding='utf-8'))['notes']
    if notes.keys() & incoming.keys():
        raise RuntimeError('Duplicate explicit observation paths')
    notes.update(incoming)
by_path = {row['path']: row for row in ledger['files']}
for path, note in notes.items():
    row = by_path[path]
    if hashlib.sha256((root / path).read_bytes()).hexdigest() != row['sha256']:
        raise RuntimeError('Reviewed bytes changed: ' + path)
    if not note.strip():
        raise RuntimeError('Missing semantic observation: ' + path)
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
for path, note in notes.items():
    row = by_path[path]
    if row.get('reviewNotes') == note:
        continue
    if row['status'] not in ('pending-review', 'source-read-awaiting-cross-check'):
        raise RuntimeError('Refusing to replace completed or partial review: ' + path)
    row.update(status='source-read-awaiting-cross-check', sourceReadDate=now,
               reviewNotes=note, readRanges=[[1, row['lines']]])
for finding in json.loads((out / 'defects.json').read_text(encoding='utf-8'))['findings']:
    row = by_path[finding['file']]
    row['findingIDs'] = sorted(set(row['findingIDs']) | {finding['id']})
temporary = ledger_path.with_suffix('.json.tmp')
temporary.write_text(json.dumps(ledger, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
temporary.replace(ledger_path)
print(json.dumps({'explicitObservations': len(notes), 'zoneAccepted': False}))
