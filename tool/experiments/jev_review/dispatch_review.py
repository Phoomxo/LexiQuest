"""Durable OFFLINE coordinator review journal, never a process launcher.

The owning coordinator supplies observed pins/runtime and reviews evidence.
This is not an OS sandbox, distributed lease or evidence oracle. Use one audit
database for the sequential run; repository writer ownership is still required.
Worker execution remains disabled until live routing prerequisites are proven.
"""
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sqlite3

from model_route import fallback_receipt, incident_decision


class DispatchHalt(ValueError):
    pass


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def relative_path(value):
    if (not isinstance(value, str) or not value or '\\' in value or ':' in value
            or PurePosixPath(value).is_absolute()
            or any(p in ('', '.', '..') for p in value.split('/'))):
        raise DispatchHalt('Expected canonical relative file path')


def fingerprint(pins):
    if not isinstance(pins, dict) or not pins:
        raise DispatchHalt('Nonempty observed source pins required')
    for path, digest in pins.items():
        relative_path(path)
        if not isinstance(digest, str) or not re.fullmatch('[0-9a-f]{64}', digest):
            raise DispatchHalt('Invalid source digest')
    return hashlib.sha256(encoded(pins).encode()).hexdigest()


class ReviewController:
    def __init__(self, database):
        self.db = sqlite3.connect(database, timeout=5)
        self.db.executescript('''
            CREATE TABLE IF NOT EXISTS packages (
              id TEXT PRIMARY KEY, state TEXT NOT NULL, active INTEGER NOT NULL,
              card TEXT NOT NULL, route TEXT NOT NULL);
            CREATE UNIQUE INDEX IF NOT EXISTS sole_active ON packages(active) WHERE active=1;
            CREATE TABLE IF NOT EXISTS events (
              seq INTEGER PRIMARY KEY, package TEXT NOT NULL, event TEXT NOT NULL,
              detail TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS incidents (
              id TEXT PRIMARY KEY, package TEXT NOT NULL, identity TEXT NOT NULL,
              attempts INTEGER NOT NULL);
        ''')

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.db.close()

    @contextmanager
    def transaction(self):
        try:
            self.db.execute('BEGIN IMMEDIATE')
            yield
            self.db.commit()
        except sqlite3.IntegrityError as error:
            self.db.rollback()
            raise DispatchHalt('Duplicate identity or another active package') from error
        except Exception:
            self.db.rollback()
            raise

    def get(self, package):
        row = self.db.execute('SELECT state,card,route FROM packages WHERE id=?',
                              (package,)).fetchone()
        if row is None:
            raise DispatchHalt('Unknown package')
        return dict(state=row[0], card=json.loads(row[1]), route=json.loads(row[2]))

    def events(self, package):
        return [dict(event=r[0], detail=json.loads(r[1])) for r in self.db.execute(
            'SELECT event,detail FROM events WHERE package=? ORDER BY seq', (package,))]

    def _event(self, package, event, detail):
        self.db.execute('INSERT INTO events(package,event,detail) VALUES(?,?,?)',
                        (package, event, encoded(detail)))

    def _state(self, package, expected):
        value = self.get(package)
        if value['state'] not in expected:
            raise DispatchHalt('Invalid state transition')
        return value

    def prepare(self, card, route):
        required = {'id', 'owner', 'cwd', 'sourcePins', 'sourceFingerprint',
                    'scope', 'acceptance', 'invariants', 'mode'}
        if not isinstance(card, dict) or set(card) != required:
            raise DispatchHalt('Complete bounded task card required')
        if (card['mode'] not in ('read-only', 'coordinator-write')
                or not all(isinstance(card[k], str) and card[k].strip()
                           for k in ('id', 'owner', 'cwd'))):
            raise DispatchHalt('Invalid identity or operation')
        root = Path(card['cwd'])
        if not root.is_absolute() or not root.is_dir():
            raise DispatchHalt('Existing absolute source cwd required')
        for field in ('scope', 'acceptance', 'invariants'):
            values = card[field]
            if (not isinstance(values, list) or not values
                    or not all(isinstance(v, str) and v.strip() for v in values)):
                raise DispatchHalt('Scope, acceptance and invariants required')
        for path in card['scope']:
            relative_path(path)
            if not (root/path).resolve().is_relative_to(root.resolve()):
                raise DispatchHalt('Scope escapes source cwd')
        source = fingerprint(card['sourcePins'])
        if source != card['sourceFingerprint']:
            raise DispatchHalt('Source fingerprint mismatch')
        if (not isinstance(route, dict) or not isinstance(route.get('reason'), str)
                or not route['reason'].strip()):
            raise DispatchHalt('Explicit fallback receipt required')
        if route != fallback_receipt(reason=route['reason'], source=source):
            raise DispatchHalt('Worker dispatch disabled; exact coordinator fallback required')
        with self.transaction():
            self.db.execute('INSERT INTO packages VALUES(?,?,1,?,?)',
                            (card['id'], 'ROUTED', encoded(card), encoded(route)))
            self._event(card['id'], 'ROUTED', dict(route=route, execution='NONE'))

    def start(self, package, runtime, observed_pins):
        if (not isinstance(runtime, dict) or not isinstance(runtime.get('cwd'), str)
                or not Path(runtime['cwd']).is_absolute()):
            raise DispatchHalt('Explicit absolute observed cwd required')
        with self.transaction():
            saved = self._state(package, ('ROUTED',))
            card, route = saved['card'], saved['route']
            if (fingerprint(observed_pins) != card['sourceFingerprint']
                    or Path(runtime.get('cwd', '')).resolve() != Path(card['cwd']).resolve()
                    or runtime.get('model') != route['selectedModel']
                    or runtime.get('effort') != route['effort']
                    or runtime.get('tier') not in (None, 'standard', 'default')
                    or runtime.get('workerStarted') is not False):
                raise DispatchHalt('Source/cwd/model/effort/tier/worker mismatch')
            self.db.execute('UPDATE packages SET state=? WHERE id=?', ('RUNNING', package))
            self._event(package, 'RUNNING', dict(runtime=runtime,
                        runtimeTierVerified=runtime.get('tier') is not None,
                        execution='COORDINATOR_ONLY'))

    def finish(self, package, observed_pins, *, exit_code):
        after = fingerprint(observed_pins)
        if type(exit_code) is not int:
            raise DispatchHalt('Exact exit code required')
        with self.transaction():
            card = self._state(package, ('RUNNING',))['card']
            before = card['sourcePins']
            changed = sorted(p for p in set(before) | set(observed_pins)
                             if before.get(p) != observed_pins.get(p))
            scope_ok = not changed if card['mode'] == 'read-only' else set(changed) <= set(card['scope'])
            state = 'REVIEW' if scope_ok and exit_code == 0 else 'RECOVERY'
            self.db.execute('UPDATE packages SET state=? WHERE id=?', (state, package))
            self._event(package, state, dict(changed=changed, sourceFingerprint=after,
                                            exit=exit_code, scopeOK=scope_ok))

    def review(self, package, *, accepted, evidence):
        if (type(accepted) is not bool or not isinstance(evidence, list) or not evidence):
            raise DispatchHalt('Explicit controller decision and evidence required')
        for path in evidence:
            relative_path(path)
        with self.transaction():
            self._state(package, ('REVIEW',))
            state = 'VERIFIED' if accepted else 'RECOVERY'
            self.db.execute('UPDATE packages SET state=?,active=? WHERE id=?',
                            (state, 0 if accepted else 1, package))
            self._event(package, state, dict(evidence=evidence, reviewer='owning_coordinator'))

    def defer(self, package, *, reason):
        if not isinstance(reason, str) or not reason.strip():
            raise DispatchHalt('Deferred package needs reason/next action')
        with self.transaction():
            self._state(package, ('ROUTED', 'RUNNING', 'REVIEW', 'RECOVERY'))
            self.db.execute('UPDATE packages SET state=?,active=0 WHERE id=?', ('DEFERRED', package))
            self._event(package, 'DEFERRED', dict(reason=reason))

    def incident(self, package, incident_id, facts, advice, *, now):
        if not isinstance(incident_id, str) or not incident_id.strip():
            raise DispatchHalt('Durable incident ID required')
        identity = encoded({k:v for k,v in facts.items() if k != 'attempts'})
        with self.transaction():
            card = self._state(package, ('RUNNING', 'REVIEW', 'RECOVERY'))['card']
            if facts.get('source') != card['sourceFingerprint']:
                raise DispatchHalt('Incident source differs from package')
            row = self.db.execute('SELECT package,identity,attempts FROM incidents WHERE id=?',
                                  (incident_id,)).fetchone()
            if row and row[:2] != (package, identity):
                raise DispatchHalt('Incident identity changed; diagnose and record new incident')
            attempts = row[2] if row else 0
            decision = incident_decision(advice, incident=dict(facts, attempts=attempts), now=now)
            # Consume advice at issuance. A crash cannot reissue the same retry.
            attempts += int(decision['action'] in ('retry_once', 'reroute_once'))
            self.db.execute('INSERT OR REPLACE INTO incidents VALUES(?,?,?,?)',
                            (incident_id, package, identity, attempts))
            self._event(package, 'INCIDENT', dict(id=incident_id, attempts=attempts,
                                                decision=decision, execution='NONE'))
            return decision
