"""Offline controller acceptance. No provider or worker is started."""
import copy
import tempfile
import unittest
from pathlib import Path

import model_route

try:
    from dispatch_review import ReviewController, DispatchHalt, fingerprint
except ImportError:
    ReviewController = None


class DispatchReviewTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(ReviewController, 'durable reviewed controller required')
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.db = self.root / 'audit.sqlite'
        self.pins = {'fixture.py': 'a' * 64}
        self.card = dict(id='fixture-01', owner='coordinator', cwd=str(self.root),
                         sourcePins=self.pins, sourceFingerprint=fingerprint(self.pins),
                         scope=['fixture.py'], acceptance=['owner preserved'],
                         invariants=['no external calls'], mode='read-only')
        self.runtime = dict(cwd=str(self.root), model='gpt-6-astra', effort='medium',
                            tier=None, workerStarted=False)
        self.route = model_route.fallback_receipt(reason='billing unknown',
                                                 source=fingerprint(self.pins))

    def controller(self):
        return ReviewController(self.db)

    def start(self, ctl):
        ctl.prepare(self.card, self.route)
        ctl.start(self.card['id'], self.runtime, self.pins)

    def test_review_is_required_and_durable(self):
        with self.controller() as ctl:
            self.start(ctl)
            with self.assertRaises(DispatchHalt):
                ctl.review('fixture-01', accepted=True, evidence=['receipt.json'])
            ctl.finish('fixture-01', self.pins, exit_code=0)
        with self.controller() as ctl:
            self.assertEqual(ctl.get('fixture-01')['state'], 'REVIEW')
            ctl.review('fixture-01', accepted=True, evidence=['receipt.json'])
            self.assertEqual(ctl.get('fixture-01')['state'], 'VERIFIED')
            self.assertEqual([e['event'] for e in ctl.events('fixture-01')],
                             ['ROUTED', 'RUNNING', 'REVIEW', 'VERIFIED'])

    def test_one_active_package_including_review_or_recovery(self):
        with self.controller() as a, self.controller() as b:
            self.start(a)
            a.finish('fixture-01', self.pins, exit_code=1)
            next_card = dict(self.card, id='fixture-02')
            with self.assertRaises(DispatchHalt):
                b.prepare(next_card, self.route)
            a.defer('fixture-01', reason='corrected method needs new source review')
            b.prepare(next_card, self.route)

    def test_runtime_mismatch_does_not_start(self):
        for key, value in [('cwd', str(self.root/'wrong')), ('model', 'gpt-6-luna'),
                           ('effort', 'low'), ('tier', 'priority'), ('workerStarted', True)]:
            with self.subTest(key=key), self.controller() as ctl:
                card = dict(self.card, id=key)
                ctl.prepare(card, self.route)
                with self.assertRaises(DispatchHalt):
                    ctl.start(key, dict(self.runtime, **{key: value}), self.pins)
                self.assertEqual(ctl.get(key)['state'], 'ROUTED')
                ctl.defer(key, reason='mismatch rejected')

    def test_source_change_before_start_rejected(self):
        with self.controller() as ctl:
            ctl.prepare(self.card, self.route)
            with self.assertRaises(DispatchHalt):
                ctl.start('fixture-01', self.runtime, {'fixture.py': 'b'*64})

    def test_read_only_diff_and_out_of_scope_changes_recover(self):
        for mode, after in [('read-only', {'fixture.py': 'b'*64}),
                            ('coordinator-write', dict(self.pins, other='b'*64))]:
            with self.subTest(mode=mode), self.controller() as ctl:
                self.card.update(id=mode, mode=mode)
                self.start(ctl)
                ctl.finish(mode, after, exit_code=0)
                self.assertEqual(ctl.get(mode)['state'], 'RECOVERY')
                with self.assertRaises(DispatchHalt):
                    ctl.review(mode, accepted=True, evidence=['fake-pass.json'])
                ctl.defer(mode, reason='scope violation requires diagnosis')

    def test_bounded_coordinator_write_needs_evidence_and_review(self):
        with self.controller() as ctl:
            self.card['mode'] = 'coordinator-write'
            self.start(ctl)
            ctl.finish('fixture-01', {'fixture.py': 'b'*64}, exit_code=0)
            with self.assertRaises(DispatchHalt):
                ctl.review('fixture-01', accepted=True, evidence=[])
            ctl.review('fixture-01', accepted=True, evidence=['targeted-pass.json'])
            self.assertEqual(ctl.get('fixture-01')['state'], 'VERIFIED')

    def test_forged_fallback_and_invalid_card_rejected(self):
        variants = [dict(self.route, sourceFingerprint='b'*64),
                    dict(self.route, selectedModel='gpt-6-luna'),
                    dict(self.route, jevChoiceCalled=True)]
        with self.controller() as ctl:
            for route in variants:
                with self.assertRaises(DispatchHalt):
                    ctl.prepare(self.card, route)
            for key, value in [('scope', ['../escape']), ('acceptance', []),
                               ('sourceFingerprint', 'b'*64), ('mode', 'worker-write')]:
                with self.assertRaises(DispatchHalt):
                    ctl.prepare(dict(self.card, **{key:value}), self.route)

    def test_incident_attempts_survive_restart_and_no_replay(self):
        incident = dict(kind='transient_read', billing_known=True,
                        source=fingerprint(self.pins), current_source=fingerprint(self.pins),
                        one_writer=True, acceptance_preserved=True, evidence_conflict=False,
                        deadline=200, attempts=0, idempotent=True, corrected_method=True)
        advice = dict(action='retry_once', confidence=0.9)
        with self.controller() as ctl:
            self.start(ctl)
            first=ctl.incident('fixture-01', 'incident-01', incident, advice, now=100)
            self.assertEqual(first['action'], 'retry_once')
        with self.controller() as ctl:
            second=ctl.incident('fixture-01', 'incident-01', incident, advice, now=101)
            self.assertEqual(second['action'], 'defer')
            changed=copy.deepcopy(incident); changed['kind']='quota'
            with self.assertRaises(DispatchHalt):
                ctl.incident('fixture-01', 'incident-01', changed, advice, now=102)

    def test_incident_must_bind_package_source(self):
        facts = dict(kind='transient_read', billing_known=True, source='b'*64,
                     current_source='b'*64, one_writer=True, acceptance_preserved=True,
                     evidence_conflict=False, deadline=200, idempotent=True,
                     corrected_method=True)
        with self.controller() as ctl:
            self.start(ctl)
            with self.assertRaises(DispatchHalt):
                ctl.incident('fixture-01', 'other-source', facts,
                             dict(action='retry_once', confidence=0.9), now=100)

    def test_blank_fallback_reason_is_controller_halt(self):
        with self.controller() as ctl:
            with self.assertRaises(DispatchHalt):
                ctl.prepare(self.card, dict(self.route, reason=' '))

    def test_missing_cwd_cannot_borrow_process_cwd(self):
        with self.controller() as ctl:
            self.card['cwd'] = str(Path.cwd())
            ctl.prepare(self.card, self.route)
            runtime = dict(self.runtime); del runtime['cwd']
            with self.assertRaises(DispatchHalt):
                ctl.start('fixture-01', runtime, self.pins)


if __name__ == '__main__':
    unittest.main()
