"""Explicit, single-call Jev pilot; no automatic retry, fallback or billing setup."""
import argparse
import json
import math
import os
import time
import urllib.request
from pathlib import Path
from guard import Guard, Halt, MODEL, money, validate_input

CATEGORIES = dict(ui='Layout or controls', storage='Persistence or data loss',
                  owner='Owner isolation or data provenance', async_='Async lifecycle',
                  config='Configuration', insufficient='Insufficient evidence')
CATEGORIES['async'] = CATEGORIES.pop('async_')
CHECKS = dict(widget='Widget behavior', persistence='Storage correctness',
              lifecycle='Async lifecycle', configuration='Configuration checks',
              investigate='Collect evidence')
CHECKS['owner-isolation'] = 'Owner boundaries and late attachment'


def payload(text):
    validate_input(text)
    return {'model': MODEL, 'state': text, 'questions': {
        'category': {'type': 'choice', 'instructions': 'Classify the primary defect risk.',
                     'criteria': CATEGORIES},
        'uncertain': {'type': 'noul', 'instructions': 'Is evidence insufficient for confident triage?'},
        'suggested_check_group': {'type': 'choice',
            'instructions': 'Which check group should be prioritized? Never dismiss required checks.',
            'criteria': CHECKS}}}


def probability(value):
    if type(value) not in (float, int) or not math.isfinite(value) or not 0 <= value <= 1:
        raise Halt('Invalid probability')
    return value


def parse_response(body):
    try:
        if body['model'] != MODEL:
            raise Halt('Model changed')
        answers = body['answers']
        result = {}
        for key, options in [('category', CATEGORIES), ('suggested_check_group', CHECKS)]:
            answer = answers[key]
            dist = answer['probabilities']
            if (answer['type'] != 'choice' or answer['choice'] not in options or
                    set(dist) != set(options) or
                    abs(sum(probability(x) for x in dist.values()) - 1) > 0.001):
                raise Halt('Malformed choice')
            probability(answer['confidence'])
            result[key] = answer['choice']
        if answers['uncertain']['type'] != 'noul':
            raise Halt('Malformed uncertainty')
        result['uncertain'] = probability(answers['uncertain']['noul'])
        usage = body['usage']
        if any(type(usage[k]) is not int or usage[k] < 0 for k in ['input_tokens', 'output_tokens']):
            raise Halt('Malformed token usage')
        gateway = body['provider_metadata']['gateway']
        routing = gateway['routing']
        if (routing['canonicalSlug'] != MODEL or routing['finalProvider'] != 'typesafe-ai' or
                not gateway['generationId'] or
                money(gateway['cost']) != money(gateway['gatewayCost'])):
            raise Halt('Unknown route or billing')
        money(gateway['surchargeCost'])
        return {'cost_usd': str(money(gateway['cost'])), 'model': MODEL,
                'generation_id': gateway['generationId'], 'result': result,
                'usage': {k: usage[k] for k in ['input_tokens', 'output_tokens']}}
    except (KeyError, TypeError, ValueError):
        raise Halt('Malformed Jev response') from None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise Halt('Redirect refused')


def request(path, key, body=None):
    req = urllib.request.Request('https://ai-gateway.vercel.sh' + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
    with urllib.request.build_opener(NoRedirect).open(req, timeout=30) as response:
        raw = response.read(256001)
        if len(raw) > 256000:
            raise Halt('Oversized response')
        return json.loads(raw)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--live', action='store_true')
    parser.add_argument('--ledger', required=True)
    parser.add_argument('--evidence', required=True)
    parser.add_argument('--case', required=True)
    parser.add_argument('--purpose', choices=('synthetic', 'review'), default='synthetic')
    args = parser.parse_args()
    if not args.live:
        raise Halt('Disabled by default; no network sent')
    evidence = json.loads(Path(args.evidence).read_text(encoding='utf-8-sig'))
    case = json.loads(Path(args.case).read_text(encoding='utf-8-sig'))
    if case.get('sanitized_reviewed') is not True:
        raise Halt('Only manually reviewed synthetic or sanitized summaries are eligible')
    body = payload(case['summary'])
    guard = Guard(args.ledger)
    state = guard.status()
    if state['pending'] or state['paused']:
        raise Halt('Pending or paused ledger')
    key = os.environ.get('LEXIQUEST_JEV_GATEWAY_KEY')
    if not key:
        raise Halt('Credential unavailable')
    # Credit lookup is read-only. Inference is gated by the durable reservation.
    credit = request('/v1/credits', key)
    def send(reservation):
        receipt = parse_response(request('/typesafe/v1/systemone', key, body))
        after = request('/v1/credits', key)
        # Never infer a paid deduction as acceptable. Unknown balance movement
        # leaves the request pending for separate dashboard reconciliation.
        used = money(after['total_used']) - money(credit['total_used'])
        if (used < money(receipt['cost_usd']) or used > money(reservation) or
                money(after['balance']) > money(credit['balance']) or
                money(after['balance']) <= 0):
            raise Halt('Credit movement requires reconciliation')
        receipt['paid_usd'] = '0'  # Preflight requires paid balance zero and auto-reload off.
        return receipt
    result = guard.run(case['summary'], evidence=evidence, balance=credit['balance'],
                       now=time.time(), send=send, purpose=args.purpose,
                       source=case.get('source_fingerprint', 'legacy'))
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Jev paused: preflight failed or outcome needs reconciliation. No automatic retry.')
        raise SystemExit(2)
