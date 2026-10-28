"""Check source binding and arithmetic oracle values, not Dart runtime behavior."""
import hashlib
import json
import math
import subprocess
from datetime import datetime, timedelta, timezone
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[6]
OUT = Path(__file__).parent
registry = json.loads((OUT / 'G0.7-formula-registry.json').read_text(encoding='utf-8'))
rows = registry['records']
assert [r['formulaId'] for r in rows] == [f'FORM-{i:02}' for i in range(1, 13)]
pins = {}
for row in rows:
    for key in ['policyVersion', 'authorities', 'writers', 'readers', 'inputs', 'denominator', 'missingBehavior', 'sourceFormula', 'ownerPackages', 'plannedTestTargets', 'fixtures', 'compatibility']:
        assert row[key], (row['formulaId'], key)
    for pin in row['authorities']:
        p = ROOT / pin['path']
        assert hashlib.sha256(p.read_bytes()).hexdigest() == pin['sha256'], pin['path']
        assert pin['symbol'] in p.read_text(encoding='utf-8-sig').splitlines()[pin['line']-1]
        assert subprocess.check_output(['git', 'rev-parse', registry['sourceSha'] + ':' + pin['path']], cwd=ROOT).decode().strip() == pin['gitBlob']
    paths = [p['path'] for p in row['authorities']] + row['writers'] + row['readers'] + row['plannedTestTargets']
    for path in paths:
        p = ROOT / path
        assert p.is_file(), path
        pins[path] = hashlib.sha256(p.read_bytes()).hexdigest()
    for case in row['fixtures']:
        assert case['input'] and case['expected'] and case['basis']
        assert case['runtimeStatus'] == 'NOT RUN in B01'

def fixture(n, i): return rows[n-1]['fixtures'][i-1]
assert Fraction(fixture(1, 1)['expected']['firstAccuracyFraction']) == Fraction(5, 6)
assert Fraction(fixture(1, 1)['expected']['currentAggregateFraction']) == Fraction(6, 7)
for i in [2, 3, 4]:
    f = fixture(2, i); p = f['input']
    assert f['expected']['stars'] == (3 if p['perfect'] else 2 if p['independent']*4 >= p['matched']*3 else 1)
assert fixture(3, 1)['expected']['intervalDays'] == [1, 3, 7, 14, 14*2]
assert math.isclose(fixture(3, 1)['expected']['difficulty'], 0.3-5*0.03)
assert fixture(3, 3)['expected']['intervalDays'] == min(36500, min(36500, 50000)*2)
assert (datetime(2026, 9, 13)+timedelta(days=28)).isoformat()+'Z' == fixture(3, 5)['expected']['dueAtUtc']
f = fixture(4, 1)
assert [xp//20+1 for xp in f['input']['lifetimeXp']] == f['expected']['level']
assert [xp%20 for xp in f['input']['lifetimeXp']] == f['expected']['xpIntoLevel']
assert [level*20 for level in f['expected']['level']] == f['expected']['nextLevelAt']
assert fixture(5, 3)['expected'] == {'current': 5, 'longest': 8, 'freeze': 0}
assert fixture(6, 1)['expected']['activeMs'] == sum(fixture(6, 1)['input']['activeSeconds'])*1000
f = fixture(7, 1)
local = [datetime.fromisoformat(t.replace('Z', '+00:00')).astimezone(timezone(timedelta(hours=7))).date() for t in f['input']['utc']]
assert [d.isoformat() for d in local] == f['expected']['dates']
assert [(d-timedelta(days=d.weekday())).isoformat() for d in local] == f['expected']['weekStarts']
f = fixture(8, 1)['expected']
assert Fraction(f['postFraction'])-Fraction(f['preFraction']) == Fraction(f['deltaFraction'])
assert 100*Fraction(f['deltaFraction']) == Fraction(f['deltaPercentagePoints'])
f = fixture(9, 1); k, n, z = 3, 4, 1.959963984540054
p=k/n; d=1+z*z/n; center=(p+z*z/(2*n))/d; margin=z*math.sqrt(p*(1-p)/n+z*z/(4*n*n))/d
assert all(math.isclose(a,b,abs_tol=1e-12) for a,b in zip([center-margin, center+margin], f['expected']['wilson95Approx']))
assert fixture(10, 2)['expected']['similarityPercent'] == math.floor(100*(1-1/3)+0.5)
assert fixture(11, 2)['input']['wordTarget'] != fixture(11, 2)['input']['response']
assert ' '.join(fixture(11, 3)['input']['sentenceTarget'].split()) == ' '.join(fixture(11, 3)['input']['response'].split())
for i in [4,5]:
    f=fixture(12,i); total=sum(f['input']['requiredCentralMonthlyThb'])
    assert f['expected']['total']==total
    assert f['expected']['state']==('withinBudget' if total<=100 else 'outOfBudget')
defects=json.loads((OUT/'defects.json').read_text(encoding='utf-8'))['defects']
for d in ['B01-FORM-01','B01-FORM-02']:
    assert any(x['id']==d and x['status']=='open-owned-downstream' for x in defects)
changed=subprocess.check_output(['git','diff','--name-only',registry['sourceSha']],cwd=ROOT).decode().splitlines()
assert all(p.startswith('docs/') for p in changed)
result={'schemaVersion':1,'packageId':'G0.7','bundleId':'B01','status':'passed','kind':'formula-inspection',
        'sourceSha':registry['sourceSha'],'formulaCount':12,'fixtureCount':sum(len(r['fixtures']) for r in rows),
        'sourceInputCount':len(pins),'sourcePins':pins,'runtimeVerified':False,
        'verificationScope':'Source symbols, versions, writer/reader/test paths,60 fixture specifications and selected independent arithmetic oracles. No application behavior tests executed.',
        'registrySha256':hashlib.sha256((OUT/'G0.7-formula-registry.json').read_bytes()).hexdigest(),
        'verifierSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'openDefects':['B01-FORM-01','B01-FORM-02'],
        'acceptance':'All12 authorities/inputs/denominators/missing states/owners/expected cases registered. Source deviations explicitly separated from proposals; no formula/version/history mutation.',
        'gatesReused':'G0.4 bounded verifier and G0.5 source acceptance unchanged; no Flutter/backend/build/GPU/full release invocation for document delta.'}
(OUT/'G0.7-verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:result[k] for k in ['status','formulaCount','fixtureCount','sourceInputCount','runtimeVerified','openDefects']}))
