import unittest

from model_route import (build_request, candidate_catalog, dispatch_plan, parse_decision,
                         normalize_effort, RouteHalt)


AGY = '''gemini-3.8-flash-high\tGemini 3.8 Flash (High)
gemini-3.8-flash-medium\tGemini 3.8 Flash (Medium)
gemini-3.8-flash-low\tGemini 3.8 Flash (Low)
claude-opus-4-6-thinking\tClaude Opus 4.6 (Thinking)'''


class ModelRouteTests(unittest.TestCase):
    def test_supported_candidates_are_exact_and_exclude_other_provider_models(self):
        candidates = candidate_catalog(AGY)
        self.assertEqual(len(candidates), 20)
        self.assertEqual(len([c for c in candidates.values() if c['executor'] == 'antigravity']), 3)
        self.assertNotIn('claude-opus-4-6-thinking', [c['model'] for c in candidates.values()])
        self.assertIn('gpt-6-astra', [c['model'] for c in candidates.values()])
        self.assertEqual({c['model'] for c in candidates.values() if c['effort']=='ultra'}, {'gpt-6-astra','gpt-6-sol'})

    def test_missing_antigravity_slug_is_not_invented(self):
        candidates = candidate_catalog('gemini-3.8-flash-medium\tGemini')
        self.assertEqual(len([c for c in candidates.values() if c['executor'] == 'antigravity']), 1)

    def test_effort_aliases_and_unsupported_ultra(self):
        self.assertEqual(normalize_effort('light'), 'low')
        self.assertEqual(normalize_effort('extra high'), 'xhigh')
        with self.assertRaises(RouteHalt):
            normalize_effort('ultra')
        self.assertEqual(normalize_effort('ultra', model='gpt-6-astra'), 'ultra')
        with self.assertRaises(RouteHalt):
            normalize_effort('ultra', model='gpt-6-luna')

    def test_choice_is_restricted_to_available_candidates(self):
        candidates = candidate_catalog(AGY)
        request = build_request('Review a failed migration with owner separation.', candidates)
        options = request['questions']['model_route']['criteria']
        self.assertEqual(set(options), set(candidates) | {'defer'})
        self.assertNotIn('claude-opus-4-6-thinking', str(options))

    def test_low_confidence_and_high_risk_underpowered_selection_defer(self):
        candidates = candidate_catalog(AGY)
        flash = next(k for k,v in candidates.items() if v['model'] == 'gemini-3.8-flash' and v['effort'] == 'low')
        response = {'model':'typesafe-ai/jev','answers':{'model_route':{'type':'choice','choice':flash,
            'probabilities':{k:(1.0 if k == flash else 0.0) for k in [*candidates,'defer']},'confidence':0.9},
            'needs_review':{'type':'noul','noul':0.1}}}
        self.assertEqual(parse_decision(response,candidates,risk='owner_or_data_loss')['status'], 'defer')
        self.assertEqual(parse_decision(response,candidates,risk='routine')['status'], 'selected')
        response['answers']['model_route']['confidence'] = 0.49
        self.assertEqual(parse_decision(response,candidates,risk='routine')['status'], 'defer')
        response['answers']['model_route']['confidence'] = 0.9
        response['answers']['model_route']['choice'] = 'unknown'
        with self.assertRaises(RouteHalt):
            parse_decision(response,candidates,risk='routine')

    def test_dispatch_plan_maps_to_each_official_cli_without_execution(self):
        candidates = candidate_catalog(AGY)
        for key, target in candidates.items():
            plan = dispatch_plan({'status':'selected','candidate':key,'target':target},
                                 candidates, workdir='C:/isolated/fixture')
            self.assertEqual(plan['execution'], 'manual_review_required')
            self.assertEqual(plan['model'], target['model_slug'])
            if target['executor'] == 'codex':
                self.assertIn('exec', plan['argv'])
                self.assertIn('model_reasoning_effort='+target['effort'], plan['argv'])
                self.assertIn('read-only', plan['argv'])
            else:
                self.assertIn('--model', plan['argv'])
                self.assertIn(target['model_slug'], plan['argv'])
                self.assertIn('--sandbox', plan['argv'])
        with self.assertRaises(RouteHalt):
            dispatch_plan({'status':'selected','candidate':'fake','target':{}},
                          candidates, workdir='C:/isolated/fixture')


if __name__ == '__main__':
    unittest.main()
