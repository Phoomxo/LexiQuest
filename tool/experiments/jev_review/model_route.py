"""Offline, bounded Jev model-choice contract. Does not send or execute work.

Model availability is an input observed from the executor. A decision is only
advice until the caller checks current quota, permissions and billing again.
"""

import math
import re

from guard import MODEL, validate_input


class RouteHalt(ValueError):
    pass


CODEX_MODELS = ('gpt-6-astra', 'gpt-6-sol', 'gpt-6-luna')
CODEX_EFFORTS = ('low', 'medium', 'high', 'xhigh', 'max')
CODEX_MODEL_EFFORTS = {model: CODEX_EFFORTS + (('ultra',) if model != 'gpt-6-luna' else ())
                      for model in CODEX_MODELS}
GEMINI_SLUGS = ('gemini-3.8-flash-low', 'gemini-3.8-flash-medium',
                'gemini-3.8-flash-high')


def eligible_candidates(candidates, observations, *, now, risk):
    """A catalog is not proof of live availability or quota; fail closed."""
    if risk not in ('routine', 'owner_or_data_loss'):
        raise RouteHalt('Risk must be explicit')
    result = {}
    authorized = candidate_catalog('\n'.join(s + '\tallowed' for s in GEMINI_SLUGS))
    for key, target in candidates.items():
        observed = observations.get(key, {})
        at = observed.get('observed_at')
        if (authorized.get(key) != target or
                type(at) not in (int, float) or not math.isfinite(at) or
                type(now) not in (int, float) or not math.isfinite(now) or
                not 0 <= now - at <= 60 or
                observed.get('available') is not True or
                observed.get('quota_ok') is not True):
            continue
        if risk == 'owner_or_data_loss' and not (
                target['executor'] == 'codex' and
                target['model'] in ('gpt-6-astra', 'gpt-6-sol') and
                target['effort'] in ('high', 'xhigh', 'max', 'ultra')):
            continue
        result[key] = target
    return result


def fallback_receipt(*, reason, source):
    """Coordinator continuation only; this does not select/launch a worker."""
    if (not isinstance(reason, str) or not reason.strip() or
            not isinstance(source, str) or not re.fullmatch('[0-9a-f]{64}', source)):
        raise RouteHalt('Fallback requires a reason and exact source pin')
    return {'routeStatus': 'DETERMINISTIC_FALLBACK', 'reason': reason,
            'selectedModel': 'gpt-6-astra', 'effort': 'medium',
            'sourceFingerprint': source, 'jevChoiceCalled': False,
            'dispatch': 'NONE_COORDINATOR_CONTINUES', 'paidSpend': 0,
            'tierPolicy': 'Standard/default requested; runtime tier not exposed'}


def incident_decision(response, *, incident, now):
    """Interpret bounded advice; never execute, retry network, or certify PASS.

    Attempts belong to the incident and must be persisted by its controller.
    A new decision is allowed after new evidence, not a reset of an old retry.
    """
    def result(action, reason):
        return {'action': action, 'reason': reason,
                'proposedAction': response.get('action') if isinstance(response, dict) else None,
                'execution': 'NONE_CONTROLLER_REVIEW'}
    try:
        kind = incident['kind']
        if kind in ('owner_isolation', 'data_loss', 'original_data_restore'):
            return result('escalate', 'data_safety_veto')
        if (incident['billing_known'] is not True or
                kind in ('jev_timeout', 'receipt_mismatch', 'malformed_response')):
            return result('defer', 'billing_reconciliation_required')
        if (not re.fullmatch('[0-9a-f]{64}', incident['source']) or
                incident['source'] != incident['current_source'] or
                incident['one_writer'] is not True or
                incident['acceptance_preserved'] is not True or
                incident['evidence_conflict'] is not False):
            return result('defer', 'source_writer_or_evidence_veto')
        deadline, attempts = incident['deadline'], incident['attempts']
        if (type(deadline) not in (int, float) or not math.isfinite(deadline) or
                type(now) not in (int, float) or not math.isfinite(now) or now >= deadline or
                type(attempts) is not int or attempts < 0):
            return result('defer', 'invalid_or_expired_incident')
        action = response['action']
        if (action not in ('continue', 'collect_evidence', 'retry_once',
                           'reroute_once', 'escalate', 'defer') or
                _probability(response['confidence']) < 0.7):
            return result('defer', 'invalid_or_uncertain_advice')
        if kind == 'command_failure':
            return result(action if action in ('collect_evidence', 'escalate', 'defer')
                          else 'collect_evidence', 'diagnose_failed_method')
        if kind == 'quota':
            allowed = (action == 'reroute_once' and attempts == 0 and
                       incident['eligibility_refreshed'] is True)
            return result('reroute_once' if allowed else 'defer', 'quota_policy')
        if kind == 'transient_read':
            allowed = (action == 'retry_once' and attempts == 0 and
                       incident['idempotent'] is True and incident['corrected_method'] is True)
            return result('retry_once' if allowed else 'defer', 'bounded_corrected_read')
        if kind == 'recovery':
            allowed = action == 'continue' and incident['recovered'] is True
            return result('continue' if allowed else 'collect_evidence', 'verify_recovery')
        return result('defer', 'unknown_incident')
    except (KeyError, TypeError, RouteHalt):
        return result('defer', 'malformed_incident_or_advice')


def normalize_effort(value, *, model=None):
    if not isinstance(value, str):
        raise RouteHalt('Unknown effort')
    effort = {'light': 'low', 'extra high': 'xhigh'}.get(value.lower().strip(),
                                                     value.lower().strip())
    if effort not in (CODEX_EFFORTS if model is None else CODEX_MODEL_EFFORTS.get(model, ())):
        raise RouteHalt('Unsupported effort; no silent downgrade')
    return effort


def candidate_catalog(agy_models_output):
    """Intersect current Antigravity slugs with the user-authorized pool."""
    if not isinstance(agy_models_output, str):
        raise RouteHalt('Model catalog unavailable')
    available = {line.split('\t', 1)[0].strip() for line in
                 agy_models_output.splitlines() if '\t' in line}
    catalog = {}
    for slug in GEMINI_SLUGS:
        if slug in available:
            effort = slug.rsplit('-', 1)[1]
            catalog['agy_gemini38_' + effort] = {
                'executor': 'antigravity', 'model': 'gemini-3.8-flash',
                'model_slug': slug, 'effort': effort}
    for model in CODEX_MODELS:
        for effort in CODEX_MODEL_EFFORTS[model]:
            key = 'codex_' + model.replace('-', '_') + '_' + effort
            catalog[key] = {'executor': 'codex', 'model': model,
                            'model_slug': model, 'effort': effort}
    return catalog


def build_request(task_summary, candidates):
    validate_input(task_summary)
    if not candidates or len(candidates) > 254:
        raise RouteHalt('Candidate catalog empty or too large')
    options = {}
    for key, value in candidates.items():
        if not re.fullmatch(r'[a-z0-9_]+', key):
            raise RouteHalt('Invalid candidate key')
        options[key] = (f"{value['executor']} {value['model']} "
                        f"effort {value['effort']}; select only if sufficient "
                        'for the task and current quota allows it.')
    options['defer'] = ('No candidate has adequate known capability or quota; '
                        'or the task needs additional evidence before routing.')
    return {'model': MODEL, 'state': task_summary,
            'questions': {
                'model_route': {'type': 'choice',
                    'instructions': ('Choose the least costly adequate option '
                                     'from the supplied list. Favor quality for '
                                     'owner isolation, data loss and migrations. '
                                     'If adequate quality is uncertain choose defer.'),
                    'criteria': options},
                'needs_review': {'type': 'noul',
                    'instructions': ('Is there insufficient evidence to select '
                                     'a reliable model and effort for this task?')}}}


def _probability(value):
    if type(value) not in (float, int) or not math.isfinite(value) or not 0 <= value <= 1:
        raise RouteHalt('Invalid probability')
    return value


def parse_decision(response, candidates, *, risk):
    if risk not in ('routine', 'owner_or_data_loss'):
        raise RouteHalt('Risk must be explicit')
    try:
        if response['model'] != MODEL:
            raise RouteHalt('Unexpected decision model')
        answer = response['answers']['model_route']
        probs = answer['probabilities']
        options = set(candidates) | {'defer'}
        if (answer['type'] != 'choice' or answer['choice'] not in options or
                set(probs) != options or
                abs(sum(_probability(x) for x in probs.values()) - 1) > 0.001):
            raise RouteHalt('Malformed model choice')
        confidence = _probability(answer['confidence'])
        review = response['answers']['needs_review']
        if review['type'] != 'noul':
            raise RouteHalt('Malformed review signal')
        review_probability = _probability(review['noul'])
        chosen = answer['choice']
        if (chosen == 'defer' or confidence < 0.7 or probs[chosen] < 0.5 or
                review_probability >= 0.5):
            return {'status': 'defer', 'reason': 'uncertain_or_no_adequate_choice'}
        target = candidates[chosen]
        if risk == 'owner_or_data_loss' and not (
            target['executor'] == 'codex' and
            target['model'] in ('gpt-6-astra', 'gpt-6-sol') and
            target['effort'] in ('high', 'xhigh', 'max', 'ultra')
        ):
            return {'status': 'defer', 'reason': 'critical_quality_floor'}
        return {'status': 'selected', 'candidate': chosen, 'target': target,
                'confidence': confidence, 'review_probability': review_probability}
    except (KeyError, TypeError):
        raise RouteHalt('Malformed decision response') from None


def dispatch_plan(decision, candidates, *, workdir):
    """Return a reviewable argv; this function never starts an agent."""
    if (not isinstance(decision, dict) or decision.get('status') != 'selected'
            or not isinstance(workdir, str) or not workdir.strip()):
        raise RouteHalt('No selected route or working directory')
    key = decision.get('candidate')
    if key not in candidates or decision.get('target') != candidates[key]:
        raise RouteHalt('Selection differs from current allowlist')
    target = candidates[key]
    if target['executor'] == 'antigravity':
        # The CLI's model slug already embeds Flash effort. Its normal
        # permission policy still applies; this plan grants no write access.
        argv = ['agy', '-p', '<reviewed bounded task>', '--model',
                target['model_slug'], '--output-format', 'json', '--sandbox']
    elif target['executor'] == 'codex':
        argv = ['codex', 'exec', '-m', target['model_slug'], '-c',
                'model_reasoning_effort=' + target['effort'], '--sandbox',
                'read-only', '--json', '-C', workdir, '-']
    else:
        raise RouteHalt('Unknown executor')
    return {'execution': 'manual_review_required',
            'executor': target['executor'], 'model': target['model_slug'],
            'effort': target['effort'], 'workdir': workdir, 'argv': argv}
