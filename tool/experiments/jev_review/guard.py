"""Local USD5 tranche guard. No network, credentials, or automatic initialization.

This is a local reservation, not a provider-side spending cap. Evidence must
include current free-credit classification and bounds for shared spending.
Uncertain outcomes remain reserved until a separately reviewed reconciliation.
"""
import hashlib
import json
import math
import re
import sqlite3
from contextlib import closing, contextmanager
from decimal import Decimal, InvalidOperation
from pathlib import Path

MODEL = 'typesafe-ai/jev'
SCHEMA = 'jev-triage-v1'
BATCHES = {'synthetic': 'synthetic-v1', 'review': 'review-v1',
           'routing': 'routing-v1'}


def request_identity(text, purpose, batch, source, schema, policy_version):
    batch = BATCHES.get(purpose) if batch is None else batch
    if (purpose not in BATCHES or batch != BATCHES[purpose] or
            any(not isinstance(v, str) or not v or len(v) > 128
                for v in (source, schema, policy_version))):
        raise Halt('Unknown batch or missing request context')
    digest = hashlib.sha256(json.dumps(
        [MODEL, schema, text, purpose, batch, source, policy_version]).encode()).hexdigest()
    return digest, batch


def timestamp(value):
    if type(value) not in (int, float) or not math.isfinite(value):
        raise Halt('Unknown timestamp')
    return value


class Halt(RuntimeError):
    pass


def money(value):
    try:
        result = Decimal(str(value))
        if not result.is_finite() or result < 0:
            raise ValueError()
        return result
    except (InvalidOperation, ValueError):
        raise Halt('Unknown or invalid monetary value') from None


def validate_input(text):
    if not isinstance(text, str) or not text.strip() or len(text) > 8000:
        raise Halt('Input must contain 1..8000 characters; no silent truncation')
    # Defense in depth: only manually sanitized summaries belong at this API.
    patterns = [r'(?i)authorization\s*:', r'(?i)bearer\s+\S+',
                r'(?i)(api[_-]?key|password|secret|token)\s*[:=]',
                r'(?i)[a-z]:[/\\]', r'(?i)/(users|home)/',
                r'[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}',
                r'(?i)(owner|account|user)[_-]?id\s*[:=]', r'(?i)owner:']
    if any(re.search(pattern, text) for pattern in patterns):
        raise Halt('Input requires manual sanitization')


class Guard:
    def __init__(self, path):
        self.path = Path(path)

    def migrate(self, legacy_purposes):
        """Explicit transactional upgrade; retain all original billing columns.

        The caller backs up the ledger and classifies every legacy request from
        its reviewed receipt. No default classification can hide old usage.
        """
        with self._connect() as db:
            db.execute('BEGIN IMMEDIATE')
            version = db.execute('PRAGMA user_version').fetchone()[0]
            if version == 2:
                return
            if version != 0:
                raise Halt('Unsupported ledger version')
            hashes = {r[0] for r in db.execute('SELECT hash FROM calls')}
            if (set(legacy_purposes) != hashes or
                    any(p not in BATCHES for p in legacy_purposes.values())):
                raise Halt('Every legacy request needs a reviewed purpose')
            db.execute('''CREATE TABLE call_context (
                hash TEXT PRIMARY KEY REFERENCES calls(hash),
                purpose TEXT NOT NULL, batch TEXT NOT NULL,
                request_id TEXT NOT NULL UNIQUE,
                source TEXT NOT NULL, schema_id TEXT NOT NULL,
                policy_version TEXT NOT NULL)''')
            for digest, purpose in legacy_purposes.items():
                db.execute('INSERT INTO call_context VALUES (?,?,?,?,?,?,?)',
                           (digest, purpose, BATCHES[purpose], digest,
                            'legacy', SCHEMA, 'legacy'))
            db.execute('PRAGMA user_version=2')

    @classmethod
    def create(cls, path, *, tranche, expires):
        path = Path(path)
        try:
            with path.open('xb'):
                pass
        except FileExistsError:
            raise Halt('Existing ledger must never be replaced') from None
        with closing(sqlite3.connect(path)) as db, db:
            db.executescript('''
                CREATE TABLE policy (tranche TEXT, expires REAL, paused TEXT);
                CREATE TABLE calls (hash TEXT PRIMARY KEY, reservation TEXT,
                    cost TEXT, state TEXT, receipt TEXT, result TEXT);
            ''')
            db.execute('INSERT INTO policy VALUES (?, ?, NULL)', (tranche, expires))
        guard = cls(path)
        guard.migrate({})
        return guard

    @contextmanager
    def _connect(self):
        if not self.path.is_file():
            raise Halt('Disabled: no initialized ledger')
        with closing(sqlite3.connect(self.path, timeout=0)) as db, db:
            db.row_factory = sqlite3.Row
            db.execute('PRAGMA synchronous=FULL')
            yield db

    def status(self):
        with self._connect() as db:
            policy = dict(db.execute('SELECT * FROM policy').fetchone())
            calls = db.execute('SELECT cost, state FROM calls').fetchall()
        return policy | {'pending': sum(r['state'] != 'settled' for r in calls),
                         'calls': len(calls), 'spent_usd': str(sum(
                             (money(r['cost']) for r in calls if r['state'] == 'settled'),
                             Decimal(0)))}

    def reconcile(self, text, receipt, *, evidence_ref, purpose='synthetic',
                  batch=None, source='legacy', schema=SCHEMA,
                  policy_version='r3-v2', legacy_hash=None):
        """Explicit operator-reviewed reconciliation; never called by a retry.

        The operator must match provider logs to the pending input, timestamps,
        generation and free-credit debit before invoking this method.
        """
        if not isinstance(evidence_ref, str) or not evidence_ref.strip():
            raise Halt('A reviewed billing evidence reference is required')
        digest, _ = request_identity(text, purpose, batch, source, schema, policy_version)
        if legacy_hash is not None:
            original = hashlib.sha256(json.dumps([MODEL, SCHEMA, text]).encode()).hexdigest()
            if legacy_hash != original:
                raise Halt('Legacy request mismatch')
            digest = legacy_hash
        with self._connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute("SELECT * FROM calls WHERE hash=? AND state='pending'", (digest,)).fetchone()
            if row is None:
                raise Halt('No matching pending request')
            cost = money(receipt['cost_usd'])
            if (cost > money(row['reservation']) or money(receipt['paid_usd']) != 0 or
                    receipt['model'] != MODEL or not receipt['generation_id']):
                raise Halt('Reconciliation is not free-only within reservation')
            audit = receipt | {'reviewed_evidence': evidence_ref}
            self._unique_receipt(db, receipt)
            db.execute("UPDATE calls SET state='settled', cost=?, receipt=?, result=? WHERE hash=?",
                       (str(cost), json.dumps(audit), json.dumps(receipt['result']), digest))

    @staticmethod
    def _unique_receipt(db, receipt):
        generation = receipt['generation_id']
        if not isinstance(generation, str) or not generation.strip():
            raise Halt('Missing generation identity')
        for row in db.execute("SELECT receipt FROM calls WHERE state='settled'"):
            if json.loads(row[0]).get('generation_id') == generation:
                raise Halt('Generation receipt already used')

    def run(self, text, *, evidence, balance, now, send, purpose='synthetic',
            batch=None, source='legacy', schema=SCHEMA, policy_version='r3-v2'):
        validate_input(text)
        digest, batch = request_identity(text, purpose, batch, source, schema, policy_version)
        try:
            with self._connect() as db:
                db.execute('BEGIN IMMEDIATE')
                if db.execute('PRAGMA user_version').fetchone()[0] != 2:
                    raise Halt('Explicit ledger migration required before network')
                policy = db.execute('SELECT * FROM policy').fetchone()
                if policy['paused']:
                    raise Halt('Tranche paused; no automatic resumption')
                if timestamp(now) >= timestamp(policy['expires']):
                    db.execute("UPDATE policy SET paused='expired'")
                    db.commit()
                    raise Halt('Authorized tranche expired')
                if db.execute("SELECT 1 FROM calls WHERE state != 'settled'").fetchone():
                    raise Halt('Unreconciled or in-flight request')
                # Fresh evidence is required even for cache lookup.
                if (evidence.get('model') != MODEL or
                        evidence.get('auto_reload') is not False or
                        not 0 <= now - timestamp(evidence['observed_at']) <= 60 or
                        now >= timestamp(evidence['expires']) or money(evidence['paid_usd']) != 0):
                    raise Halt('Billing evidence stale, unknown, or not free-only')
                max_in, max_out = evidence['max_input_tokens'], evidence['max_output_tokens']
                if (type(max_in) is not int or type(max_out) is not int or
                        max_in <= 0 or max_out <= 0):
                    raise Halt('Missing bounded token limits')
                rate = (money(evidence['input_per_million']) * max_in +
                        money(evidence['output_per_million']) * max_out) / Decimal(1000000)
                reserve = max(Decimal('0.001'), rate * 2 + money(evidence['surcharge_max_usd']))
                free = min(money(evidence['free_usd']), money(balance))
                shared = money(evidence['shared_pending_usd'])
                spent = sum((money(r[0]) for r in db.execute(
                    "SELECT cost FROM calls WHERE state='settled'")), Decimal(0))
                if reserve > min(free - shared, Decimal(5) - spent):
                    db.execute("UPDATE policy SET paused='insufficient'")
                    db.commit()
                    raise Halt('Insufficient free credits; tranche paused')
                cached = db.execute('SELECT result FROM calls WHERE hash=?', (digest,)).fetchone()
                # Adopt legacy triage cache only in its original unpinned
                # context; a source/schema/policy change requires a new key.
                if (cached is None and source == 'legacy' and schema == SCHEMA
                        and policy_version == 'r3-v2'):
                    legacy = hashlib.sha256(json.dumps([MODEL, SCHEMA, text]).encode()).hexdigest()
                    cached = db.execute('''SELECT c.result FROM calls c
                        JOIN call_context x ON x.hash=c.hash
                        WHERE c.hash=? AND x.purpose=? AND x.batch=?
                          AND x.source='legacy' AND x.policy_version='legacy'
                          AND x.schema_id=?''', (legacy, purpose, batch, schema)).fetchone()
                if cached:
                    return json.loads(cached['result'])
                if db.execute('''SELECT count(*) FROM call_context
                                 WHERE purpose=?''', (purpose,)).fetchone()[0] >= 12:
                    raise Halt('Twelve-request purpose limit reached; no batch reset')
                db.execute('INSERT INTO calls VALUES (?, ?, NULL, ?, NULL, NULL)',
                           (digest, str(reserve), 'pending'))
                db.execute('INSERT INTO call_context VALUES (?,?,?,?,?,?,?)',
                           (digest, purpose, batch, digest, source, schema, policy_version))
                db.commit()  # Must reach durable storage before calling transport.
        except (KeyError, TypeError, sqlite3.Error):
            raise Halt('Missing evidence or unavailable ledger') from None

        try:
            receipt = send(str(reserve))
            cost = money(receipt['cost_usd'])
            if (cost > reserve or money(receipt['paid_usd']) != 0 or
                    receipt['model'] != MODEL or not receipt['generation_id']):
                raise Halt('Receipt exceeds reservation or does not prove free route')
            result = receipt['result']
            with self._connect() as db:
                db.execute('BEGIN IMMEDIATE')
                self._unique_receipt(db, receipt)
                db.execute("UPDATE calls SET state='settled', cost=?, receipt=?, result=? WHERE hash=?",
                           (str(cost), json.dumps(receipt), json.dumps(result), digest))
            return result
        except Exception:
            # Do not log provider exceptions, response bodies, or headers.
            # Pending reservation survives process death and blocks all retries.
            raise Halt('Outcome unresolved; reconcile before another request') from None
