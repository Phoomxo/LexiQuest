"""Offline transport integration against a disposable ledger, never the live tranche."""
import importlib.util
import tempfile
import unittest
from pathlib import Path
from guard import Guard, Halt, MODEL


class ChoiceTransportTests(unittest.TestCase):
    def setUp(self):
        spec=importlib.util.find_spec('choice_transport')
        self.assertIsNotNone(spec, 'Guarded Choice adapter must exist')
        import choice_transport
        self.route=choice_transport.route
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.guard=Guard.create(Path(self.tmp.name)/'test.sqlite',tranche='fixture',expires=2000)
        self.capabilities={'gpt-6-astra':['medium','ultra'],'gpt-6-luna':['medium']}
        self.observations={'codex_gpt_6_astra_medium':dict(observed_at=1000,available=True,quota_ok=True)}
        self.evidence=dict(observed_at=1000,expires=2000,free_usd='5',paid_usd='0',auto_reload=False,shared_pending_usd='0',model=MODEL,input_per_million='0.04',output_per_million='0',surcharge_max_usd='0',max_input_tokens=32768,max_output_tokens=4096)
        self.calls=[];self.bad=False;self.serial=0
    def send(self,path,key,body=None):
        self.assertEqual(self.guard.status()['pending'],1,'reserve before every network call')
        self.calls.append(path)
        if path=='/v1/credits':
            used='0.00001' if self.calls.count('/v1/credits')%2==0 else '0'
            return {'balance':'4.99','total_used':used}
        self.serial+=1
        if self.bad:raise TimeoutError('fixture')
        options=body['questions']['model_route']['criteria'];chosen=next(k for k in options if k!='defer')
        return {'model':MODEL,'answers':{'model_route':{'type':'choice','choice':chosen,'confidence':0.95,'probabilities':{k:float(k==chosen) for k in options}},'needs_review':{'type':'noul','noul':0.1}},'usage':{'input_tokens':200,'output_tokens':30},'provider_metadata':{'gateway':{'routing':{'canonicalSlug':MODEL,'finalProvider':'typesafe-ai'},'generationId':'fixture-'+str(self.serial),'cost':'0.00001','gatewayCost':'0.00001','surchargeCost':'0'}}}
    def run_route(self,**changes):
        args=dict(summary='Review isolated navigation and audio cancellation.',sanitized_reviewed=True,source='a'*64,risk='routine',capabilities=self.capabilities,capabilities_observed_at=1000,observations=self.observations,guard=self.guard,evidence=self.evidence,balance='5',key='offline-fixture',clock=lambda:1000,transport=self.send)
        return self.route(**(args|changes))
    def test_reserves_settles_and_reuses_same_contract_cache(self):
        first=self.run_route();self.assertEqual(first['status'],'selected')
        self.assertEqual(self.guard.status()['pending'],0)
        count=len(self.calls);self.assertEqual(self.run_route(),first);self.assertEqual(len(self.calls),count)
    def test_stale_billing_or_capability_or_unsanitized_sends_nothing(self):
        for change in [dict(evidence=self.evidence|{'observed_at':900}),dict(capabilities_observed_at=900),dict(sanitized_reviewed=False),dict(observations={}),dict(summary='owner_id=private')]:
            with self.subTest(change=change),self.assertRaises((Halt,ValueError)):self.run_route(**change)
        self.assertEqual(self.calls,[])
    def test_timeout_stays_pending_and_retry_never_sends(self):
        self.bad=True
        with self.assertRaises(Halt):self.run_route()
        count=len(self.calls)
        with self.assertRaises(Halt):self.run_route()
        self.assertEqual(len(self.calls),count);self.assertEqual(self.guard.status()['pending'],1)
    def test_schema_does_not_offer_luna_ultra_even_if_claimed_available(self):
        with self.assertRaises((Halt,ValueError)):
            self.run_route(capabilities={'gpt-6-luna':['ultra']},observations={'codex_gpt_6_luna_ultra':dict(observed_at=1000,available=True,quota_ok=True)})
        self.assertEqual(self.calls,[])
    def test_changed_source_does_not_reuse_prior_selection(self):
        self.run_route();self.run_route(source='b'*64);self.assertEqual(self.serial,2)
    def test_changed_candidate_contract_does_not_reuse_cache(self):
        self.run_route()
        changed=self.observations|{'codex_gpt_6_astra_ultra':dict(observed_at=1000,available=True,quota_ok=True)}
        self.run_route(observations=changed);self.assertEqual(self.serial,2)
    def test_unknown_provider_receipt_remains_pending(self):
        def bad_receipt(path,key,body=None):
            result=self.send(path,key,body)
            if body is not None:result['provider_metadata']['gateway']['routing']['finalProvider']='unknown'
            return result
        with self.assertRaises(Halt):self.run_route(transport=bad_receipt)
        self.assertEqual(self.guard.status()['pending'],1)
    def test_expiry_during_credit_lookup_prevents_inference(self):
        ticks=iter([1000,1100])
        with self.assertRaises(Halt):self.run_route(clock=lambda:next(ticks))
        self.assertEqual(self.calls,['/v1/credits']);self.assertEqual(self.guard.status()['pending'],1)
    def test_live_default_never_uses_network(self):
        with self.assertRaises(Halt):self.run_route(transport=None)
        self.assertEqual(self.calls,[]);self.assertEqual(self.guard.status()['pending'],0)

if __name__=='__main__':unittest.main()
