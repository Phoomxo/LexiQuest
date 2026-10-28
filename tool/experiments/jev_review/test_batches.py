import inspect
import hashlib
import json
import sqlite3
from contextlib import closing
import unittest
import test_guard
from guard import Guard, Halt

class BatchTests(unittest.TestCase):
    setUp = test_guard.GuardTests.setUp
    send = test_guard.GuardTests.send
    run_request = test_guard.GuardTests.run_request
    def request(self, text='synthetic', **context):
        self.assertIn('purpose', inspect.signature(self.guard.run).parameters,
                      'purpose-aware guarded requests required')
        return self.guard.run(text, evidence=self.evidence, balance='5',
                              now=self.now, send=self.unique_send, **context)

    def unique_send(self, reserve):
        result=self.send(reserve)
        return result | {'generation_id':'fixture-'+str(len(self.calls))}

    def test_each_purpose_has_independent_fixed_quota_without_batch_reset(self):
        for purpose in ['synthetic','review','routing']:
            for i in range(12): self.request(str(i),purpose=purpose)
            with self.assertRaises(Halt): self.request('thirteenth',purpose=purpose)
            with self.assertRaises(Halt): self.request('new',purpose=purpose,batch='reset')
        self.assertEqual(len(self.calls),36)

    def test_cache_binds_purpose_source_schema_policy_and_durable_request_id(self):
        self.request()
        self.request()
        for context in [dict(purpose='review'),dict(source='a'*64),
                        dict(schema='new-schema'),dict(policy_version='new-policy')]:
            self.request(**context)
        self.assertEqual(len(self.calls),5)
        with closing(sqlite3.connect(self.path)) as db:
            rows=db.execute('SELECT request_id FROM call_context').fetchall()
        self.assertEqual(len(set(rows)),5)

    def test_global_tranche_includes_every_purpose(self):
        self.request(purpose='review')
        with closing(sqlite3.connect(self.path)) as db,db:
            db.execute("UPDATE calls SET cost='4.99999'")
        with self.assertRaises(Halt): self.request(purpose='routing')
        self.assertEqual(len(self.calls),1)

    def test_stale_evidence_blocks_even_cached_result(self):
        self.request()
        self.now+=61
        with self.assertRaises(Halt): self.request()
        self.assertEqual(len(self.calls),1)

    def test_nonfinite_times_never_send(self):
        for field in ['observed_at','expires']:
            for value in [float('nan'),float('inf'),True]:
                with self.subTest(field=field,value=value), self.assertRaises(Halt):
                    self.run_request(**{field:value})
        self.assertEqual(self.calls,[])

    def test_duplicate_generation_receipt_remains_pending(self):
        self.request('first')
        self.assertIn('purpose',inspect.signature(self.guard.run).parameters)
        with self.assertRaises(Halt):
            self.guard.run('second',evidence=self.evidence,balance='5',now=self.now,
                send=lambda _:dict(cost_usd='0',paid_usd='0',model='typesafe-ai/jev',
                                   generation_id='fixture-1',result={}))
        self.assertEqual(self.guard.status()['pending'],1)

    def test_migrated_legacy_rows_consume_original_purpose_quota(self):
        self.request('first')
        with closing(sqlite3.connect(self.path)) as db,db:
            # Retained old rows already have context after explicit migration.
            for i in range(11):
                key='legacy-'+str(i)
                db.execute('INSERT INTO calls VALUES (?,?,?,?,?,?)',(key,'0.1','0','settled','{}','{}'))
                db.execute('INSERT INTO call_context VALUES (?,?,?,?,?,?,?)',(key,'synthetic','synthetic-v1',key,'legacy','jev-triage-v1','legacy'))
        with self.assertRaises(Halt): self.request('next')
        self.assertEqual(len(self.calls),1)

    def test_migrated_identical_review_uses_old_cache_without_another_send(self):
        digest=hashlib.sha256(json.dumps(['typesafe-ai/jev','jev-triage-v1','synthetic']).encode()).hexdigest()
        with closing(sqlite3.connect(self.path)) as db,db:
            db.execute('DROP TABLE call_context')
            db.execute('PRAGMA user_version=0')
            db.execute('INSERT INTO calls VALUES (?,?,?,?,?,?)',
                       (digest,'0.14','0','settled','{}','{"category":"owner"}'))
        self.guard.migrate({digest:'review'})
        self.assertEqual(self.request(purpose='review'),{'category':'owner'})
        self.assertEqual(self.calls,[])
        self.request(purpose='review',source='b'*64)
        self.assertEqual(len(self.calls),1)
