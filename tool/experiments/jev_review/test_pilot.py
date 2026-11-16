import copy
import unittest
import json
import sqlite3
import tempfile
from contextlib import closing, redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch
import pilot
from guard import Guard
from pilot import payload, parse_response
from guard import Halt, MODEL


def response():
    return {'model': MODEL, 'answers': {
        'category': {'type': 'choice', 'choice': 'owner', 'confidence': 0.9,
                     'probabilities': {k: float(k == 'owner') for k in
                         ['ui', 'storage', 'owner', 'async', 'config', 'insufficient']}},
        'uncertain': {'type': 'noul', 'noul': 0.1},
        'suggested_check_group': {'type': 'choice', 'choice': 'owner-isolation',
            'confidence': 0.9, 'probabilities': {k: float(k == 'owner-isolation') for k in
                ['widget', 'persistence', 'owner-isolation', 'lifecycle', 'configuration', 'investigate']}}},
        'usage': {'input_tokens': 100, 'output_tokens': 20},
        'provider_metadata': {'gateway': {'cost': '0', 'gatewayCost': '0',
            'surchargeCost': '0', 'generationId': 'gen_fixture',
            'routing': {'canonicalSlug': MODEL, 'finalProvider': 'typesafe-ai'}}}}


class PilotTests(unittest.TestCase):
    def test_review_cli_uses_review_quota_and_source_context(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ledger = root / 'ledger.sqlite'
            Guard.create(ledger, tranche='fixture', expires=2000)
            evidence = dict(observed_at=1000, expires=2000, free_usd='5', paid_usd='0',
                auto_reload=False, shared_pending_usd='0', model=MODEL,
                input_per_million='1', output_per_million='1', surcharge_max_usd='0',
                max_input_tokens=8000, max_output_tokens=1000)
            (root/'evidence.json').write_text(json.dumps(evidence))
            (root/'case.json').write_text(json.dumps(dict(sanitized_reviewed=True,
                summary='Sanitized review', source_fingerprint='a'*64)))
            argv=['pilot','--live','--ledger',str(ledger),'--evidence',str(root/'evidence.json'),
                  '--case',str(root/'case.json'),'--purpose','review']
            credit=dict(balance='5',total_used='0')
            with patch('sys.argv',argv), patch.dict('os.environ',{'LEXIQUEST_JEV_GATEWAY_KEY':'fixture'}), \
                    patch('pilot.time.time',return_value=1000), \
                    patch('pilot.request',side_effect=[credit,response(),credit]), redirect_stdout(StringIO()):
                try:
                    pilot.main()
                except SystemExit as error:
                    self.fail('Review purpose rejected by CLI: '+str(error))
            with closing(sqlite3.connect(ledger)) as db:
                self.assertEqual(db.execute('SELECT purpose,source FROM call_context').fetchall(),
                                 [('review','a'*64)])

    def test_only_fixed_questions_and_model_are_sent(self):
        body = payload('Sanitized summary')
        self.assertEqual(body['model'], MODEL)
        self.assertEqual(set(body['questions']), {'category', 'uncertain', 'suggested_check_group'})

    def test_response_cost_is_not_market_cost(self):
        value = response()
        value['provider_metadata']['gateway']['marketCost'] = '1'
        receipt = parse_response(value)
        self.assertEqual(receipt['cost_usd'], '0')
        self.assertEqual(receipt['result']['category'], 'owner')

    def test_unknown_route_malformed_answer_and_cost_are_rejected(self):
        original = response()
        variants = []
        for field, value in [('model', 'other'), ('answers', {}), ('usage', {})]:
            variants.append(original | {field: value})
        for key, value in [('cost', None), ('gatewayCost', '1'), ('generationId', '')]:
            item = copy.deepcopy(original)
            item['provider_metadata']['gateway'][key] = value
            variants.append(item)
        for key, value in [('confidence', float('nan')), ('choice', 'dismiss'),
                           ('probabilities', {'owner': 1})]:
            item = copy.deepcopy(original)
            item['answers']['category'][key] = value
            variants.append(item)
        for item in variants:
            with self.subTest(item=item), self.assertRaises(Halt):
                parse_response(item)


if __name__ == '__main__':
    unittest.main()
