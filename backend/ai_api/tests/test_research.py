import base64
import copy
import hashlib
import json
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from lexiquest_ai.app import create_app
from lexiquest_ai.auth import AuthenticatedUser
from lexiquest_ai.config import Settings
from lexiquest_ai.research import OPERATION_KEYS, ResearchError, json_bytes, wire_time

from research_support import Harness, NOW, OWNER, UID


def test_research_routes_default_off_and_do_not_echo_submitted_data(content_service, token_verifier):
    client = TestClient(create_app(content_service=content_service, token_verifier=token_verifier,
        settings=Settings(_env_file=None)))
    response = client.get('/v1/research/enrollment-context', headers={'Authorization': 'Bearer valid-token'})
    assert response.status_code == 503
    assert response.json()['detail']['code'] == 'RESEARCH_DISABLED'


def test_context_is_read_only_and_never_provisions_nonparticipants():
    h = Harness()
    before = copy.deepcopy(h.documents.values)
    result = h.service.context(UID)
    assert result['ownerId'] == OWNER
    assert [entry['role'] for entry in result['scopes']] == ['motivation', 'assessment']
    assert h.documents.values == before
    for command in (lambda: h.service.context('unknown'), lambda: h.service.decide('unknown', h.consent()),
                    lambda: h.service.refresh('unknown', h.refresh()), lambda: h.service.upload('unknown', h.upload())):
        with pytest.raises(ResearchError):
            command()
    assert h.documents.values == before


def test_authoritative_consent_retry_is_stable_and_terminal_withdrawal_beats_late_accept():
    h = Harness()
    accepted = h.accept()
    h.now += timedelta(minutes=3)
    again = h.service.decide(UID, h.consent(requestId='retry-after-lost-ack'))
    assert {key: value for key, value in again.items() if key != 'requestId'} == {key: value for key, value in accepted.items() if key != 'requestId'}
    withdrawn = h.service.decide(UID, h.consent('withdrawn'))
    assert withdrawn['decidedAtUtc'] == accepted['decidedAtUtc']
    assert withdrawn['revision'] == 2
    h.now += timedelta(minutes=2)
    late_accept = h.service.decide(UID, h.consent())
    assert late_accept['state'] == 'withdrawn'
    assert late_accept['withdrawnAtUtc'] == withdrawn['withdrawnAtUtc']
    for call in (lambda: h.service.refresh(UID, h.refresh()), lambda: h.service.upload(UID, h.upload())):
        before = copy.deepcopy(h.documents.values)
        with pytest.raises(ResearchError):
            call()
        assert h.documents.values == before


def test_withdrawal_reconciles_existing_consent_even_after_authority_removal():
    h = Harness()
    h.accept()
    h.documents.values.pop('research_enrollments/' + UID)
    withdrawn = h.service.decide(UID, h.consent('withdrawn'))
    assert withdrawn['state'] == 'withdrawn'
    assert h.service.decide(UID, h.consent())['state'] == 'withdrawn'
    with pytest.raises(ResearchError):
        h.service.context(UID)


def test_two_real_signed_scopes_echo_correlation_and_exact_server_consent_time():
    h = Harness()
    ack = h.accept()
    for role in ('motivation', 'assessment'):
        request = h.refresh(role)
        packet = h.service.refresh(UID, request)
        assert packet['requestId'] == request.requestId
        assert packet['scope'] == request.scope.model_dump()
        assert packet['clockSessionId'] == request.clockSessionId
        assert packet['monotonicEpoch'] == request.monotonicEpoch
        assert packet['anchorUtc'] == '2026-11-01T12:00:00.000Z'
        assert packet['maximumAgeMs'] == 300000
        assert packet['receipts'][0]['decidedAtUtc'] == ack['decidedAtUtc']
        assert 'publicKeys' not in packet
        assert len(packet['operationDocuments']) == 3


@pytest.mark.parametrize('change', [
    lambda h: h.record.update(active=False),
    lambda h: h.record.update(expiresAtUtc='2026-11-01T11:59:59.999Z'),
    lambda h: h.record.update(issuedAtUtc='2026-11-01T12:00:00.001Z'),
    lambda h: h.record['scopes'][0]['receipts'][0].update(active=False),
    lambda h: h.record['scopes'][0]['receipts'][0].update(ownerId='foreign-owner'),
    lambda h: h.record['scopes'][1]['requirements'].update(protocolRevision=2),
])
def test_changed_current_authority_denies_refresh_and_upload_without_writes(change):
    h = Harness()
    h.accept()
    request = h.upload()
    change(h)
    before = copy.deepcopy(h.documents.values)
    with pytest.raises(ResearchError):
        h.service.refresh(UID, h.refresh())
    with pytest.raises(ResearchError):
        h.service.upload(UID, request)
    assert h.documents.values == before


def change_operation(h, scope, purpose, condition):
    for index, encoded in enumerate(scope['operationDocuments']):
        permit = json.loads(base64.b64decode(encoded))
        if permit['operation'] != purpose:
            continue
        state = scope['operationStates'][permit['permitId']]
        if condition == 'revoked':
            state['revoked'] = True
        elif condition == 'superseded':
            state['currentRevision'] = permit['revision'] + 1
        elif condition == 'expired':
            permit['expiresAtUtcMs'] = int(NOW.timestamp() * 1000)
        elif condition == 'future':
            permit['issuedAtUtcMs'] = int((NOW + timedelta(milliseconds=1)).timestamp() * 1000)
        else:
            raise AssertionError(condition)
        permit['signature'] = base64.urlsafe_b64encode(h.ed.sign(
            json_bytes({key: permit[key] for key in OPERATION_KEYS}))).decode().rstrip('=')
        scope['operationDocuments'][index] = base64.b64encode(json_bytes(permit)).decode()
        return
    raise AssertionError(purpose)


@pytest.mark.parametrize('purpose', ['collect', 'export'])
@pytest.mark.parametrize('condition', ['expired', 'revoked', 'superseded', 'future'])
def test_fresh_asgi_authority_then_upload_preserves_unrelated_operation_facts(content_service, purpose, condition):
    h = Harness()
    h.accept()
    for scope in h.record['scopes']:
        change_operation(h, scope, purpose, condition)
    client = TestClient(create_app(content_service=content_service, token_verifier=Verifier(),
        settings=h.settings(), research_service=h.service))
    headers = {'Authorization': 'Bearer synthetic-id-token'}
    for role in ('motivation', 'assessment'):
        response = client.post('/v1/research/authority/refresh', headers=headers,
            json=h.refresh(role).model_dump())
        assert response.status_code == 200
        packet = response.json()
        scope = next(scope for scope in h.record['scopes'] if scope['role'] == role)
        assert packet['operationDocuments'] == scope['operationDocuments']
        assert packet['operationStates'] == scope['operationStates']
        assert packet['anchorUtc'] == wire_time(NOW)
        assert packet['validUntilUtc'] == wire_time(NOW + timedelta(minutes=5))
    request = h.upload()
    response = client.post('/v1/research/study-archives', headers=headers, json=request.model_dump())
    assert response.status_code == 200
    assert response.json()['payloadSha256'] == request.payloadSha256
    assert client.post('/v1/research/study-archives', headers=headers,
        json=request.model_dump()).json() == response.json()


@pytest.mark.parametrize('role', ['motivation', 'assessment'])
@pytest.mark.parametrize('condition', ['expired', 'revoked', 'superseded', 'future'])
def test_refresh_reports_inactive_upload_facts_but_upload_and_retry_reject_them(role, condition):
    h = Harness()
    h.accept()
    request = h.upload()
    h.service.upload(UID, request)
    scope = next(scope for scope in h.record['scopes'] if scope['role'] == role)
    change_operation(h, scope, 'upload', condition)
    before = copy.deepcopy(h.documents.values)
    assert h.service.refresh(UID, h.refresh(role))['operationStates'] == scope['operationStates']
    for upload in (request, h.upload(h.archive(complete=True))):
        with pytest.raises(ResearchError, match='authority_denied'):
            h.service.upload(UID, upload)
    assert h.documents.values == before


@pytest.mark.parametrize('kind', ['operation', 'participation'])
def test_real_crypto_rejects_signature_tampering_without_writes(kind):
    h = Harness()
    h.accept()
    scope = h.record['scopes'][0]
    if kind == 'operation':
        permit = json.loads(base64.b64decode(scope['operationDocuments'][0]))
        permit['signature'] = 'A' * 86
        scope['operationDocuments'][0] = base64.b64encode(json_bytes(permit)).decode()
    else:
        permit = json.loads(scope['participationDocuments'][0])
        permit['signature'] = base64.b64encode(bytes(64)).decode()
        scope['participationDocuments'][0] = json.dumps(permit)
    before = copy.deepcopy(h.documents.values)
    with pytest.raises(ResearchError):
        h.service.refresh(UID, h.refresh())
    assert h.documents.values == before


def test_minor_requires_both_existing_current_guardian_and_assent_receipts():
    h = Harness(minor=True)
    h.accept()
    assert len(h.service.refresh(UID, h.refresh())['receipts']) == 3
    h.record['scopes'][1]['receipts'][2]['active'] = False
    with pytest.raises(ResearchError):
        h.service.upload(UID, h.upload())


def test_upload_complete_and_incomplete_preserve_state_and_exact_lost_ack_receipt():
    h = Harness()
    h.accept()
    for complete in (False, True):
        request = h.upload(h.archive(complete=complete))
        before = copy.deepcopy(h.documents.values)
        receipt = h.service.upload(UID, request)
        assert receipt['payloadSha256'] == request.payloadSha256
        assert receipt['receiptId'] == 'research-upload:' + receipt['uploadId']
        h.now += timedelta(minutes=1)
        assert h.service.upload(UID, request) == receipt
        assert h.documents.values['research_enrollments/' + UID] == before['research_enrollments/' + UID]
    assert len([key for key in h.documents.values if key.startswith('research_study_archives/')]) == 2


def test_concurrent_same_upload_creates_one_receipt_and_never_changes_learning_or_authority():
    h = Harness()
    h.accept()
    request = h.upload(h.archive(complete=True))
    with ThreadPoolExecutor(max_workers=8) as executor:
        receipts = list(executor.map(lambda _: h.service.upload(UID, request), range(16)))
    assert all(receipt == receipts[0] for receipt in receipts)
    assert len([key for key in h.documents.values if key.startswith('research_study_archives/')]) == 1
    assert not any(key.startswith(('events_v2/', 'learning_sessions/', 'answer_attempts/')) for key in h.documents.values)


@pytest.mark.parametrize('change', [
    lambda p: p.update(ownerId='private-owner-must-not-upload'),
    lambda p: p.update(cycle='local:raw-cycle'),
    lambda p: p.update(protocolRevision=2),
    lambda p: p.update(firstExposureEvent='r999'),
    lambda p: p['motivation']['responses'][0].update(ordinalValue=9),
    lambda p: p['motivation']['responses'][0].update(answeredAtUtc='2026-11-01T13:00:00.000Z'),
    lambda p: p['assessments'][0].update(formChecksumSha256='f' * 64),
    lambda p: p['assessments'][0]['outcomes'][0].update(correct=False),
    lambda p: p['assessments'][0]['outcomes'][0].update(responseTimeMs=-1),
    lambda p: p['index'].update(session='r999'),
    lambda p: p.update(missingPhases=['assessment-post']),
    lambda p: p['exposures'][0].update(presentedAtUtc='2026-11-01T11:41:00.000Z'),
])
def test_complete_archive_rejects_allowlist_pin_response_timing_or_linkage_tampering(change):
    h = Harness()
    h.accept()
    payload = h.archive(complete=True)
    change(payload)
    before = copy.deepcopy(h.documents.values)
    with pytest.raises(ResearchError):
        h.service.upload(UID, h.upload(payload))
    assert h.documents.values == before


def test_archive_cannot_predate_authoritative_consent():
    h = Harness()
    h.service.decide(UID, h.consent())
    with pytest.raises(ResearchError):
        h.service.upload(UID, h.upload())


@pytest.mark.parametrize(('change', 'missing'), [
    (lambda p: p['motivation'].update(responses=p['motivation']['responses'][:1]), ['motivation-post']),
    (lambda p: p['index'].update(completionRecorded=False), ['index-completion']),
])
def test_completed_motivation_requires_both_phases_and_canonical_index_even_if_ineligible(change, missing):
    h = Harness()
    h.accept()
    payload = h.archive(complete=True)
    payload['motivation']['primaryAnalysisEligible'] = False
    change(payload)
    payload['missingPhases'] = missing
    before = copy.deepcopy(h.documents.values)
    with pytest.raises(ResearchError, match='archive_denied'):
        h.service.upload(UID, h.upload(payload))
    assert h.documents.values == before


@pytest.mark.parametrize('post_state', ['active', 'abandoned', 'omitted'])
def test_completed_motivation_can_preserve_an_incomplete_post_assessment(post_state):
    h = Harness()
    h.accept()
    payload = h.archive(complete=True)
    post = next(section for section in payload['assessments'] if section['phase'] == 'post')
    if post_state == 'omitted':
        payload['assessments'].remove(post)
    else:
        post.update(state=post_state, completedAtUtc=None)
        if post_state == 'abandoned':
            post['abandonedAtUtc'] = wire_time(NOW - timedelta(minutes=10))
    payload['missingPhases'] = ['assessment-post']
    request = h.upload(payload)
    assert h.service.upload(UID, request)['payloadSha256'] == request.payloadSha256


def test_abandoned_motivation_preserves_genuinely_incomplete_phases():
    h = Harness()
    h.accept()
    payload = h.archive()
    payload.update(state='abandoned', closedAtUtc=wire_time(NOW))
    request = h.upload(payload)
    assert h.service.upload(UID, request)['payloadSha256'] == request.payloadSha256


def test_upload_requires_distinct_current_upload_permits_and_same_owner_for_both_scopes():
    h = Harness()
    h.accept()
    request = h.upload()
    with pytest.raises(ResearchError):
        h.service.upload(UID, request.model_copy(update={'assessmentScope': h.scope()}))
    foreign = h.scope('assessment').model_copy(update={'binding': h.scope().binding.model_copy(update={'ownerId': 'foreign'})})
    with pytest.raises(ResearchError):
        h.service.upload(UID, request.model_copy(update={'assessmentScope': foreign}))
    scope = h.record['scopes'][1]
    scope['operationDocuments'].pop()
    scope['operationStates'].pop('synthetic-assessment-upload')
    with pytest.raises(ResearchError):
        h.service.upload(UID, request)


@pytest.mark.parametrize('operation', ['context', 'consent', 'refresh', 'upload'])
def test_durable_account_deletion_fence_precedes_every_research_path(operation):
    h = Harness()
    h.accept()
    h.documents.values['account_deletion_operations/' + UID] = {'synthetic': 'pending'}
    before = copy.deepcopy(h.documents.values)
    calls = {'context': lambda: h.service.context(UID), 'consent': lambda: h.service.decide(UID, h.consent()),
        'refresh': lambda: h.service.refresh(UID, h.refresh()), 'upload': lambda: h.service.upload(UID, h.upload())}
    with pytest.raises(ResearchError, match='deletion_pending'):
        calls[operation]()
    assert h.documents.values == before


class Verifier:
    def __init__(self, anonymous=False):
        self.anonymous = anonymous
    def verify(self, token):
        assert token == 'synthetic-id-token'
        return AuthenticatedUser(uid=UID, is_anonymous=self.anonymous)


def test_actual_asgi_consent_refresh_upload_and_withdrawal(content_service):
    h = Harness()
    client = TestClient(create_app(content_service=content_service, token_verifier=Verifier(),
        settings=h.settings(), research_service=h.service))
    headers = {'Authorization': 'Bearer synthetic-id-token'}
    assert client.get('/v1/research/enrollment-context', headers=headers).json()['ownerId'] == OWNER
    h.now = NOW - timedelta(hours=1)
    ack = client.post('/v1/research/consent', json=h.consent().model_dump(), headers=headers)
    assert ack.status_code == 200
    h.now = NOW
    refresh = client.post('/v1/research/authority/refresh', json=h.refresh().model_dump(), headers=headers)
    assert refresh.status_code == 200
    assert refresh.headers['cache-control'] == 'no-store'
    assert refresh.json()['receipts'][0]['decidedAtUtc'] == ack.json()['decidedAtUtc']
    upload = h.upload(h.archive(complete=True)).model_dump()
    first = client.post('/v1/research/study-archives', json=upload, headers=headers)
    assert first.status_code == 200
    assert client.post('/v1/research/study-archives', json=upload, headers=headers).json() == first.json()
    assert client.post('/v1/research/consent', json=h.consent('withdrawn').model_dump(), headers=headers).status_code == 200
    assert client.post('/v1/research/study-archives', json=upload, headers=headers).status_code == 409
    assert client.post('/v1/content', json={'text': 'cat', 'kind': 'sentence', 'language': 'en', 'cefr': 'a1'}, headers=headers).status_code == 200


def test_asgi_rejects_unregistered_unknown_fields_duplicate_keys_and_secret_echo(content_service):
    h = Harness()
    client = TestClient(create_app(content_service=content_service, token_verifier=Verifier(True),
        settings=h.settings(), research_service=h.service))
    headers = {'Authorization': 'Bearer synthetic-id-token'}
    assert client.get('/v1/research/enrollment-context', headers=headers).status_code == 403
    malformed = client.post('/v1/research/consent', headers=headers,
        json={**h.consent().model_dump(), 'signature': 'synthetic-secret-must-not-echo'})
    assert malformed.status_code == 422
    assert 'synthetic-secret' not in malformed.text
    duplicate = client.post('/v1/research/consent', headers=headers,
        content=b'{"ownerId":"private","ownerId":"other"}')
    assert duplicate.status_code == 400
    assert 'private' not in duplicate.text
    assert h.documents.writes == 0


def test_upload_route_only_gets_larger_bounded_transport_limit(content_service):
    h = Harness()
    client = TestClient(create_app(content_service=content_service, token_verifier=Verifier(), settings=h.settings(), research_service=h.service))
    headers = {'Authorization': 'Bearer synthetic-id-token'}
    body = b' ' * 100001 + b'{}'
    assert client.post('/v1/content', content=body, headers=headers).status_code == 413
    assert client.post('/v1/research/authority/refresh', content=body, headers=headers).status_code == 413
    assert client.post('/v1/research/study-archives', content=body, headers=headers).status_code == 422
    assert client.post('/v1/research/study-archives', content=b' ' * (768 * 1024 + 1), headers=headers).status_code == 413


@pytest.mark.parametrize('value', [{}, {'research_enabled': True}, {'research_enabled': True, 'research_operation_public_keys_json': '{"bad":"secret"}'}])
def test_research_config_defaults_off_or_fails_closed_without_trusted_keys(value):
    if not value:
        assert Settings(_env_file=None).research_enabled is False
    else:
        with pytest.raises(ValidationError):
            Settings(_env_file=None, **value)


def test_real_server_microsecond_clock_is_projected_to_canonical_milliseconds():
    h = Harness()
    h.accept()
    h.now = NOW.replace(microsecond=123456)
    packet = h.service.refresh(UID, h.refresh())
    assert packet['anchorUtc'] == '2026-11-01T12:00:00.123Z'


def test_corrupted_upload_receipt_never_becomes_an_acknowledgement():
    h = Harness()
    h.accept()
    request = h.upload()
    receipt = h.service.upload(UID, request)
    path = 'research_study_archives/' + receipt['uploadId']
    h.documents.values[path]['receipt']['uploadId'] = 'f' * 64
    with pytest.raises(ResearchError):
        h.service.upload(UID, request)


def test_withdrawal_cannot_rewrite_history_when_the_server_clock_regresses():
    h = Harness()
    h.service.decide(UID, h.consent())
    h.now -= timedelta(seconds=1)
    before = copy.deepcopy(h.documents.values)
    with pytest.raises(ResearchError):
        h.service.decide(UID, h.consent('withdrawn'))
    assert h.documents.values == before


@pytest.mark.parametrize('point', [bytes(32), bytes([1]) + bytes(31),
    (2 ** 255 - 20).to_bytes(32, 'little'), (2 ** 255 - 19).to_bytes(32, 'little')])
def test_noncanonical_or_small_order_issuer_keys_are_rejected_before_library_verification(point):
    from lexiquest_ai.research import ResearchSignatures
    h = Harness()
    with pytest.raises((ResearchError, ValueError)):
        ResearchSignatures({'synthetic-ed': point}, {'synthetic-p256': h.p256_public})


def test_trusted_key_configuration_rejects_duplicate_ids_and_noncurve_points():
    h = Harness()
    settings = h.settings().model_dump()
    public = base64.b64encode(h.ed_public).decode()
    for overrides in (
        {'research_operation_public_keys_json': '{"synthetic-ed":"' + public + '","synthetic-ed":"' + public + '"}'},
        {'research_participation_public_keys_json': json.dumps({'synthetic-p256': '04' + '00' * 64})},
    ):
        with pytest.raises(ValidationError):
            Settings(_env_file=None, **{**settings, **overrides})


def test_static_server_wire_fixture_contains_only_public_synthetic_authority_and_verifies():
    from lexiquest_ai.research import ResearchSignatures
    fixture = json.loads((Path(__file__).parent / 'fixtures/research_server_wire_v1.json').read_text())
    assert fixture['synthetic'] is True
    assert set(fixture) == {'schema', 'synthetic', 'operationPublicKeysBase64', 'participationPublicKeysSec1Hex', 'enrollment'}
    h = Harness()
    h.service.signatures = ResearchSignatures(
        {key: base64.b64decode(value) for key, value in fixture['operationPublicKeysBase64'].items()},
        {key: bytes.fromhex(value) for key, value in fixture['participationPublicKeysSec1Hex'].items()})
    h.documents.values['research_enrollments/' + UID] = fixture['enrollment']
    assert h.service.context(UID)['ownerId'] == OWNER


def test_distinct_signed_operations_cannot_reuse_one_permit_identity():
    h = Harness()
    item = h.record['scopes'][0]
    from lexiquest_ai.research import OPERATION_KEYS
    document = json.loads(base64.b64decode(item['operationDocuments'][1]))
    item['operationStates'].pop(document['permitId'])
    document['permitId'] = 'synthetic-motivation-collect'
    document['signature'] = base64.urlsafe_b64encode(h.ed.sign(json_bytes({key: document[key] for key in OPERATION_KEYS}))).decode().rstrip('=')
    item['operationDocuments'][1] = base64.b64encode(json_bytes(document)).decode()
    with pytest.raises(ResearchError):
        h.service.context(UID)


def test_authority_lease_cannot_outlive_the_signed_participation_permit():
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
    from lexiquest_ai.research import PARTICIPATION_KEYS
    h = Harness()
    h.accept()
    document = json.loads(h.record['scopes'][0]['participationDocuments'][0])
    document['expiresAtUtc'] = '2026-11-01T12:00:01.000Z'
    message = json_bytes({key: document[key] for key in PARTICIPATION_KEYS})
    r, s = decode_dss_signature(h.p256.sign(message, ec.ECDSA(hashes.SHA256())))
    document.update(payloadSha256=hashlib.sha256(message).hexdigest(),
        signature=base64.b64encode(r.to_bytes(32, 'big') + s.to_bytes(32, 'big')).decode())
    for scope in h.record['scopes']:
        scope['participationDocuments'] = [json_bytes(document).decode()]
    assert h.service.refresh(UID, h.refresh())['validUntilUtc'] == '2026-11-01T12:00:01.000Z'
