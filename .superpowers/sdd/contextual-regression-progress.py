import json
from pathlib import Path

base = Path('build/verification/remediation-20260907')
folder = sorted(base.glob('contextual-regression-final-*'))[-1]
passed = failed = skipped = 0
latest = ''
elapsed = 0
for line in (folder / 'stdout.log').read_text(encoding='utf-8-sig').splitlines():
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue  # Ongoing redirected log may end mid-event; final parser is strict.
    elapsed = event.get('time', elapsed)
    if event.get('type') == 'testStart':
        latest = event['test']['name']
    if event.get('type') == 'testDone' and event.get('hidden') is False:
        if event.get('skipped'):
            skipped += 1
        elif event.get('result') == 'success':
            passed += 1
        else:
            failed += 1
print(json.dumps({'provisionalPassed': passed, 'provisionalFailed': failed, 'provisionalSkipped': skipped, 'elapsedSeconds': elapsed / 1000, 'latest': latest}))
