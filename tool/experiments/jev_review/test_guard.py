"""Offline acceptance: no credentials or network required."""
import json
import tempfile
import unittest
from pathlib import Path

from guard import Guard, Halt


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'ledger.sqlite'
        self.now = 1000
        self.guard = Guard.create(self.path, tranche='authorized-2026-09-23', expires=2000)
        self.evidence = dict(observed_at=1000, expires=2000, free_usd='5',
                             paid_usd='0', auto_reload=False, shared_pending_usd='0',
                             model='typesafe-ai/jev', input_per_million='0.042',
                             output_per_million='0', surcharge_max_usd='0',
                             max_input_tokens=32768, max_output_tokens=4096)
        self.calls = []

    def run_request(self, **changes):
        evidence = self.evidence | changes
        return self.guard.run('sanitized synthetic failure', evidence=evidence,
                              balance='5', now=self.now, send=self.send)

    def send(self, reservation):
        self.calls.append(reservation)
        self.assertEqual(Guard(self.path).status()['pending'], 1)
        return dict(cost_usd='0.00001', paid_usd='0', model='typesafe-ai/jev',
                    generation_id='gen_fixture_'+str(len(self.calls)), result={'category': 'owner'})

    def test_reserves_durably_before_call_and_reconciles(self):
        result = self.run_request()
        self.assertEqual(result['category'], 'owner')
        state = Guard(self.path).status()
        self.assertEqual(state['pending'], 0)
        self.assertEqual(state['spent_usd'], '0.00001')
        self.assertGreater(float(self.calls[0]), 0.001)

    def test_disabled_by_default(self):
        with self.assertRaises(Halt):
            Guard(Path(self.tmp.name) / 'missing').status()

    def test_no_overwrite_existing_ledger(self):
        with self.assertRaises(Halt):
            Guard.create(self.path, tranche='new', expires=4000)

    def test_unknown_stale_paid_and_changed_route_never_send(self):
        for change in [dict(free_usd=None), dict(observed_at=900),
                       dict(observed_at=1001), dict(paid_usd='1'),
                       dict(auto_reload=True), dict(model='other'),
                       dict(input_per_million='NaN'), dict(free_usd='Infinity'),
                       dict(shared_pending_usd=None), dict(max_input_tokens=0)]:
            with self.subTest(change=change), self.assertRaises(Halt):
                self.run_request(**change)
        self.assertEqual(self.calls, [])

    def test_insufficient_credit_latches_pause_even_after_refill(self):
        with self.assertRaises(Halt):
            self.run_request(free_usd='0.000001')
        with self.assertRaises(Halt):
            self.run_request()
        self.assertEqual(self.calls, [])

    def test_shared_reservations_reduce_available_balance(self):
        with self.assertRaises(Halt):
            self.run_request(shared_pending_usd='5')
        self.assertEqual(self.calls, [])

    def test_timeout_survives_restart_without_retry(self):
        def timeout(_):
            self.calls.append('timeout')
            raise TimeoutError('sensitive provider body must not be logged')
        with self.assertRaises(Halt):
            self.guard.run('synthetic', evidence=self.evidence, balance='5',
                           now=self.now, send=timeout)
        self.guard = Guard(self.path)
        with self.assertRaises(Halt):
            self.run_request()
        self.assertEqual(self.calls, ['timeout'])
        self.assertEqual(self.guard.status()['pending'], 1)

    def test_reentrant_request_is_blocked(self):
        def nested(reservation):
            with self.assertRaises(Halt):
                Guard(self.path).run('different', evidence=self.evidence,
                                    balance='5', now=self.now, send=self.send)
            return self.send(reservation)
        self.guard.run('synthetic', evidence=self.evidence, balance='5',
                       now=self.now, send=nested)
        self.assertEqual(len(self.calls), 1)

    def test_reviewed_reconciliation_releases_only_matching_reservation(self):
        def timeout(_):
            raise TimeoutError()
        with self.assertRaises(Halt):
            self.guard.run('synthetic', evidence=self.evidence, balance='5',
                           now=self.now, send=timeout)
        receipt = dict(cost_usd='0', paid_usd='0', model='typesafe-ai/jev',
                       generation_id='gen_reconciled', result={'category': 'owner'})
        with self.assertRaises(Halt):
            self.guard.reconcile('wrong summary', receipt, evidence_ref='reviewed-dashboard-receipt')
        self.guard.reconcile('synthetic', receipt, evidence_ref='reviewed-dashboard-receipt')
        self.assertEqual(self.guard.status()['pending'], 0)

    def test_http_failure_is_not_retried(self):
        def limited(_):
            self.calls.append('429')
            raise RuntimeError('429')
        with self.assertRaises(Halt):
            self.guard.run('synthetic', evidence=self.evidence, balance='5',
                           now=self.now, send=limited)
        with self.assertRaises(Halt):
            self.run_request()
        self.assertEqual(self.calls, ['429'])

    def test_missing_or_excess_cost_preserves_pending(self):
        for cost in [None, '-1', 'NaN', '4']:
            with self.subTest(cost=cost):
                path = Path(self.tmp.name) / ('bad' + str(cost))
                guard = Guard.create(path, tranche='test', expires=2000)
                with self.assertRaises(Halt):
                    guard.run('synthetic', evidence=self.evidence, balance='5',
                              now=self.now, send=lambda _: dict(cost_usd=cost,
                                  paid_usd='0', model='typesafe-ai/jev',
                                  generation_id='gen_fixture', result={}))
                self.assertEqual(guard.status()['pending'], 1)

    def test_cache_avoids_duplicate_calls(self):
        self.run_request()
        self.run_request()
        self.assertEqual(len(self.calls), 1)

    def test_expired_tranche_does_not_resume_monthly(self):
        self.now = 2001
        with self.assertRaises(Halt):
            self.run_request(observed_at=2001, expires=5000)
        self.assertEqual(self.calls, [])

    def test_oversized_and_sensitive_input_never_sent(self):
        for value in ['a' * 8001, 'Authorization: Bearer secret',
                      'C:/Users/Someone/file', 'person@example.com',
                      'api_key=secret', 'owner:private-user']:
            with self.subTest(value=value[:30]), self.assertRaises(Halt):
                self.guard.run(value, evidence=self.evidence, balance='5',
                               now=self.now, send=self.send)
        self.assertEqual(self.calls, [])

    def test_max_twelve_calls_persisted(self):
        for i in range(12):
            self.guard.run(f'synthetic {i}', evidence=self.evidence, balance='5',
                           now=self.now, send=self.send)
        with self.assertRaises(Halt):
            self.guard.run('thirteenth', evidence=self.evidence, balance='5',
                           now=self.now, send=self.send)
        self.assertEqual(len(self.calls), 12)


if __name__ == '__main__':
    unittest.main()
