"""Single guarded Choice call; no CLI launch, ledger initialization or automatic retry.

Caller supplies fresh reviewed account evidence and executor schema/quota.
Production transport is opt-in. Tests inject HTTP only; the real Guard is reused.
"""
import hashlib
import json
import re
import time

from guard import Halt, MODEL, money, timestamp, validate_input
from model_route import build_request, candidate_catalog, eligible_candidates, parse_decision
from pilot import request


def route(*, summary, sanitized_reviewed, source, risk, capabilities,
          capabilities_observed_at, observations, guard, evidence, balance,
          key, clock=time.time, transport=None, live=False):
    validate_input(summary)
    now=timestamp(clock())
    if (sanitized_reviewed is not True or not isinstance(source,str) or
            not re.fullmatch('[0-9a-f]{64}',source) or
            not isinstance(capabilities,dict) or not key or
            not 0 <= now-timestamp(capabilities_observed_at) <= 60):
        raise Halt('Reviewed summary, source and fresh executor capabilities required')
    if transport is None:
        if live is not True:
            raise Halt('Live Choice disabled by default')
        transport=request
    # No Antigravity dispatch without its separate fresh CLI/isolation evidence.
    candidates={k:v for k,v in candidate_catalog('').items()
                if v['effort'] in capabilities.get(v['model'],[])}
    candidates=eligible_candidates(candidates,observations,now=now,risk=risk)
    if not candidates:
        raise Halt('No fresh authorized executor candidate')
    body=build_request(summary,candidates)
    schema='jev-choice-v1-'+hashlib.sha256(json.dumps(
        [body,risk,candidates],sort_keys=True).encode()).hexdigest()

    def send(reservation):
        # Guard.run has durably reserved the original shared tranche before any HTTP.
        before=transport('/v1/credits',key)
        free=min(money(before['balance']),money(evidence['free_usd']))
        if free-money(evidence['shared_pending_usd']) < money(reservation):
            raise Halt('Fresh balance cannot cover reservation')
        fresh=timestamp(clock())
        if (not 0 <= fresh-timestamp(evidence['observed_at']) <= 60 or
                not 0 <= fresh-timestamp(capabilities_observed_at) <= 60 or
                eligible_candidates(candidates,observations,now=fresh,risk=risk)!=candidates):
            raise Halt('Evidence expired before inference')
        response=transport('/typesafe/v1/systemone',key,body)
        decision=parse_decision(response,candidates,risk=risk)
        usage=response['usage']
        for field,limit in [('input_tokens','max_input_tokens'),('output_tokens','max_output_tokens')]:
            if type(usage[field]) is not int or not 0 <= usage[field] <= evidence[limit]:
                raise Halt('Usage exceeds reviewed bound')
        gateway=response['provider_metadata']['gateway']
        routing=gateway['routing']
        generation=gateway['generationId']
        cost=money(gateway['cost'])
        if (routing['canonicalSlug']!=MODEL or routing['finalProvider']!='typesafe-ai' or
                not isinstance(generation,str) or not generation.strip() or
                cost!=money(gateway['gatewayCost']) or
                money(gateway['surchargeCost'])>money(evidence['surcharge_max_usd'])):
            raise Halt('Unknown gateway route or billing')
        after=transport('/v1/credits',key)
        used=money(after['total_used'])-money(before['total_used'])
        if (not cost <= used <= money(reservation) or
                money(after['balance'])>money(before['balance']) or money(after['balance'])<=0):
            raise Halt('Credit movement needs reconciliation')
        return dict(cost_usd=str(cost),paid_usd='0',model=MODEL,generation_id=generation,
                    result=decision,usage=usage)

    # Cache identity changes with candidates, question contract, risk and source.
    # The unchanged guard enforces fresh billing even for cache reads and retains
    # uncertain requests as pending. Returned choice is advice, never a dispatch.
    return guard.run(summary,evidence=evidence,balance=balance,now=now,send=send,
                     purpose='routing',source=source,schema=schema,policy_version='ux-v5-route-1')
