import copy
from datetime import timedelta
import json
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient

from lexiquest_ai.app import create_app
from lexiquest_ai.auth import AuthenticatedUser
from lexiquest_ai.config import Settings

from conftest import FakeContentService
from content_report_support import Harness, MODERATOR, OTHER, UID, envelope, submission, target_v2, wire_json
from lexiquest_ai.content_reports import ContentReportError, case_key, digest


class ReportTokenVerifier:
    def verify(self, token):
        return AuthenticatedUser(uid='synthetic-reporter', is_anonymous=False)


def test_content_reports_are_default_off_without_disabling_learning():
    client = TestClient(create_app(
        content_service=FakeContentService(),
        token_verifier=ReportTokenVerifier(),
        settings=Settings(_env_file=None),
    ))
    response = client.post('/v1/content-reports', json={}, headers={
        'Authorization': 'Bearer synthetic-token',
    })
    assert response.status_code == 503
    assert response.json()['detail']['code'] == 'REPORTS_DISABLED'
    assert client.get('/health/live').status_code == 200


def test_content_report_transport_requires_a_verified_token():
    client = TestClient(create_app(
        content_service=FakeContentService(),
        token_verifier=ReportTokenVerifier(),
        settings=Settings(_env_file=None),
    ))
    assert client.post('/v1/content-reports', json={}).status_code == 401


def test_v1_exact_target_bytes_are_stored_and_receipt_means_received_only():
    h = Harness()
    request = submission(report_id='word-report:synthetic/α')
    response = h.post(request)
    assert response.status_code == 200
    assert response.headers['cache-control'] == 'no-store'
    receipt = response.json()
    assert receipt['receipt']['reportId'] == 'word-report:synthetic/α'
    assert receipt['receipt']['reportSha256'] == request['reportSha256']
    assert receipt['receipt']['receivedAtUtc'] == '2026-11-01T12:00:00.123Z'
    assert receipt['moderation'] == {'revision': 1, 'status': 'received',
                                    'decisionId': None, 'publicNote': None, 'decidedAtUtc': None}
    stored = h.documents.values['content_reports/' + case_key(UID, 'word-report:synthetic/α')]
    assert stored['reportJson'] == request['reportJson']
    assert json.loads(stored['reportJson'])['snapshotJson'] == json.loads(request['reportJson'])['snapshotJson']
    assert 'firebaseUid' not in wire_json(receipt)


@pytest.mark.parametrize('kind', ['packEntry', 'aiOutput', 'tutorReply', 'readingDocument'])
def test_each_closed_nonword_target_is_received_without_an_invented_word(kind):
    h = Harness()
    request = submission(report_id='content-report:' + kind, target=target_v2(kind))
    assert h.post(request).status_code == 200
    stored = next(value for path, value in h.documents.values.items() if path.startswith('content_reports/'))
    assert stored['reportJson'] == request['reportJson']
    assert 'wordId' not in json.loads(json.loads(stored['reportJson'])['snapshotJson'])


@pytest.mark.parametrize('token', ['anonymous', 'uncertain'])
def test_unregistered_or_uncertain_identity_never_writes(token):
    h = Harness()
    assert h.post(token=token).status_code == 403
    assert h.documents.values == {}


def test_old_ai_snapshot_may_explicitly_report_unrecorded_provider_origin():
    h = Harness()
    target = target_v2('aiOutput')
    target['source']['origin'] = 'unrecorded'
    request = submission(report_id='content-report:old-ai', target=target)
    assert h.post(request).status_code == 200
    target['source']['origin'] = 'invented-provider'
    assert h.post(submission(report_id='content-report:bad-ai', target=target)).status_code == 400


def test_same_local_id_is_uid_scoped_and_foreign_receipts_and_bodies_are_not_disclosed():
    h = Harness()
    first = h.post().json()
    assert h.client.get('/v1/content-reports/receipt', params={'reportId': 'word-report:synthetic-1'},
                        headers=h.headers('other')).status_code == 404
    assert h.client.get('/v1/content-reports', headers=h.headers('other')).json()['items'] == []
    other = h.post(token='other').json()
    assert first['receipt']['receiptId'] != other['receipt']['receiptId']
    own = h.client.get('/v1/content-reports', headers=h.headers()).json()['items']
    assert len(own) == 1 and own[0]['receipt'] == first['receipt']
    assert 'reportJson' not in own[0]


def test_lost_ack_retry_keeps_original_bytes_time_and_budget():
    h = Harness(budget=1)
    h.documents.lose_next_ack = True
    assert h.post().status_code == 503
    committed = copy.deepcopy(h.documents.values)
    h.now += timedelta(seconds=5)
    response = h.post()
    assert response.status_code == 200
    assert response.json()['receipt']['receivedAtUtc'] == '2026-11-01T12:00:00.123Z'
    assert h.documents.values == committed
    assert h.post(submission(report_id='word-report:synthetic-2')).status_code == 429


def test_concurrent_same_request_creates_one_case_and_one_budget_unit():
    h = Harness()
    with ThreadPoolExecutor(max_workers=8) as pool:
        replies = list(pool.map(lambda _: h.service.submit(UID, submission()), range(16)))
    assert all(reply == replies[0] for reply in replies)
    assert len(h.documents.values) == 2
    counter = h.documents.values['content_report_limits/' + digest(UID)]
    assert counter['submissions'] == 1


def test_changed_same_id_conflicts_without_changing_original_report_or_counter():
    h = Harness()
    assert h.post().status_code == 200
    before = copy.deepcopy(h.documents.values)
    assert h.post(submission(comment='Synthetic changed review')).status_code == 409
    assert h.documents.values == before


@pytest.mark.parametrize('field,value', [('firebaseUid', OTHER), ('status', 'resolved'),
                                        ('receivedAtUtcMs', 1), ('moderator', MODERATOR)])
def test_client_cannot_supply_trusted_owner_or_delivery_state(field, value):
    h = Harness()
    assert h.post(submission(**{field: value})).status_code == 400
    assert h.documents.values == {}


@pytest.mark.parametrize('layer', ['envelope', 'report', 'snapshot'])
def test_duplicate_keys_are_rejected_at_every_encoded_boundary(layer):
    h = Harness()
    request = submission()
    if layer == 'envelope':
        raw = wire_json(request).replace('{', '{"schemaVersion":1,', 1)
    elif layer == 'report':
        request['reportJson'] = request['reportJson'].replace('{', '{"schemaVersion":1,', 1)
        request['reportSha256'] = digest(request['reportJson'])
        raw = wire_json(request)
    else:
        report = json.loads(request['reportJson'])
        report['snapshotJson'] = report['snapshotJson'].replace('{', '{"wordId":"synthetic-word",', 1)
        report['snapshotSha256'] = digest(report['snapshotJson'])
        raw = wire_json(envelope(report))
    response = h.client.post('/v1/content-reports', content=raw.encode(), headers=h.headers())
    assert response.status_code == 400
    assert h.documents.values == {}


@pytest.mark.parametrize('change', ['outer', 'snapshot', 'text'])
def test_digests_bind_exact_reviewed_bytes(change):
    h = Harness()
    request = submission(target=target_v2('tutorReply'))
    if change == 'outer':
        request['reportSha256'] = 'f' * 64
    else:
        report = json.loads(request['reportJson'])
        if change == 'snapshot':
            report['snapshotSha256'] = 'f' * 64
        else:
            target = json.loads(report['snapshotJson'])
            target['text'] += ' synthetic mutation'
            report['snapshotJson'] = wire_json(target)
            report['snapshotSha256'] = digest(report['snapshotJson'])
        request = envelope(report)
    assert h.post(request).status_code == 400
    assert h.documents.values == {}


@pytest.mark.parametrize('field', ['learnerPrompt', 'chatHistory', 'answers', 'audio', 'research'])
def test_target_extra_private_context_is_not_an_allowed_upload_field(field):
    h = Harness()
    target = target_v2('tutorReply')
    target[field] = 'Synthetic excluded private context'
    assert h.post(submission(target=target)).status_code == 400
    assert h.documents.values == {}


@pytest.mark.parametrize('field,value', [('schemaVersion', True), ('queuedAtUtcMs', True),
                                        ('reason', 'unknown'), ('comment', ''), ('comment', ' untrimmed '),
                                        ('comment', 'x' * 501), ('reportId', 'not-a-report')])
def test_report_metadata_is_closed_strict_and_bounded(field, value):
    h = Harness()
    assert h.post(submission(**{field: value})).status_code == 400
    assert h.documents.values == {}


def test_explicit_excerpt_is_retained_and_content_is_never_silently_truncated():
    h = Harness()
    target = target_v2('readingDocument')
    target['isExcerpt'] = True
    target['text'] = 'x' * 4096
    target['textSha256'] = digest(target['text'])
    request = submission(report_id='content-report:excerpt', target=target)
    assert h.post(request).status_code == 200
    before = copy.deepcopy(h.documents.values)
    target['text'] += 'x'
    target['textSha256'] = digest(target['text'])
    assert h.post(submission(target=target)).status_code == 400
    assert h.documents.values == before


def test_http_body_limit_and_safe_errors_do_not_echo_selected_content():
    h = Harness()
    marker = 'synthetic-private-marker'
    response = h.client.post('/v1/content-reports', content=(marker * 5000).encode(), headers=h.headers())
    assert response.status_code == 413
    assert marker not in response.text
    response = h.client.post('/v1/content-reports', content=marker.encode(), headers=h.headers())
    assert response.status_code == 400
    assert marker not in response.text
    assert h.documents.values == {}


def test_persistent_budget_has_uid_isolation_minute_rollover_and_clock_rollback_guard():
    h = Harness(budget=1)
    assert h.post().status_code == 200
    assert h.post(submission(report_id='word-report:synthetic-2')).status_code == 429
    assert h.post(token='other').status_code == 200
    h.now += timedelta(minutes=1)
    assert h.post(submission(report_id='word-report:synthetic-2')).status_code == 200
    h.now -= timedelta(minutes=2)
    before = copy.deepcopy(h.documents.values)
    assert h.post(submission(report_id='word-report:synthetic-3')).status_code == 503
    assert h.documents.values == before


@pytest.mark.parametrize('operation', ['new', 'replay', 'read', 'list', 'decision'])
def test_pending_account_deletion_blocks_each_boundary_without_recreation(operation):
    h = Harness()
    assert h.post().status_code == 200
    key = case_key(UID, 'word-report:synthetic-1')
    h.documents.values['account_deletion_operations/' + UID] = {'synthetic': True}
    before = copy.deepcopy(h.documents.values)
    if operation == 'new':
        response = h.post(submission(report_id='word-report:new'))
    elif operation == 'replay':
        response = h.post()
    elif operation == 'read':
        response = h.client.get('/v1/content-reports/receipt', params={'reportId': 'word-report:synthetic-1'}, headers=h.headers())
    elif operation == 'list':
        response = h.client.get('/v1/content-reports', headers=h.headers())
    else:
        response = h.decision(key)
    assert response.status_code == 409
    assert h.documents.values == before


def test_firestore_transaction_retry_rechecks_deletion_before_report_and_budget_commit():
    h = Harness()
    h.documents.before_retry = lambda values: values.update({'account_deletion_operations/' + UID: {'synthetic': True}})
    assert h.post().status_code == 409
    assert set(h.documents.values) == {'account_deletion_operations/' + UID}


def test_moderator_permission_is_server_allowlist_only():
    h = Harness(moderators=frozenset())
    assert h.client.get('/v1/content-report-moderation', headers=h.headers('moderator')).status_code == 403
    assert h.client.get('/v1/content-report-moderation/pending', headers=h.headers()).status_code == 403
    assert h.documents.values == {}
    h = Harness()
    assert h.client.get('/v1/content-report-moderation', headers=h.headers('moderator')).json() == {
        'schemaVersion': 1, 'canModerate': True}


@pytest.mark.parametrize('operation', ['permission', 'pending', 'decision'])
def test_deleting_moderator_cannot_read_or_decide_other_accounts_reports(operation):
    h = Harness()
    assert h.post().status_code == 200
    key = case_key(UID, 'word-report:synthetic-1')
    h.documents.values['account_deletion_operations/' + MODERATOR] = {'synthetic': True}
    before = copy.deepcopy(h.documents.values)
    read_count = len(h.documents.reads)
    if operation == 'permission':
        response = h.client.get('/v1/content-report-moderation', headers=h.headers('moderator'))
    elif operation == 'pending':
        response = h.client.get('/v1/content-report-moderation/pending', headers=h.headers('moderator'))
    else:
        response = h.decision(key)
    assert response.status_code == 409
    assert response.json()['detail']['code'] == 'REPORTS_DELETION_PENDING'
    assert h.documents.values == before
    assert not any(path.startswith('content_reports/') for path in h.documents.reads[read_count:])


def test_capability_is_not_returned_when_moderator_deletion_begins_after_permission_check():
    h = Harness()
    original = h.service.require_moderator

    def start_deletion_after_check(uid):
        original(uid)
        h.documents.values['account_deletion_operations/' + MODERATOR] = {'synthetic': True}

    h.service.require_moderator = start_deletion_after_check
    response = h.client.get('/v1/content-report-moderation', headers=h.headers('moderator'))
    assert response.status_code == 409
    assert 'canModerate' not in response.json()


@pytest.mark.parametrize('has_reports', [False, True])
def test_moderator_page_rechecks_actor_fence_after_query_even_when_empty(has_reports):
    h = Harness()
    if has_reports:
        assert h.post().status_code == 200
    original = h.documents.list_cases

    def start_deletion_during_query(**arguments):
        rows = original(**arguments)
        h.documents.values['account_deletion_operations/' + MODERATOR] = {'synthetic': True}
        return rows

    h.documents.list_cases = start_deletion_during_query
    response = h.client.get('/v1/content-report-moderation/pending', headers=h.headers('moderator'))
    assert response.status_code == 409
    assert 'items' not in response.json()


def test_moderator_deletion_after_case_discovery_prevents_decision():
    h = Harness()
    assert h.post().status_code == 200
    key = case_key(UID, 'word-report:synthetic-1')
    before = copy.deepcopy(h.documents.values['content_reports/' + key])
    original = h.service.store.get_case

    def start_deletion_after_discovery(value):
        result = original(value)
        h.documents.values['account_deletion_operations/' + MODERATOR] = {'synthetic': True}
        return result

    h.service.store.get_case = start_deletion_after_discovery
    response = h.decision(key)
    assert response.status_code == 409
    assert h.documents.values['content_reports/' + key] == before


def test_moderator_deletion_during_decision_retry_preserves_pending_case():
    h = Harness()
    assert h.post().status_code == 200
    key = case_key(UID, 'word-report:synthetic-1')
    before = copy.deepcopy(h.documents.values['content_reports/' + key])
    original = h.service.store.get_case

    def schedule_deletion_after_discovery(value):
        result = original(value)
        h.documents.before_retry = lambda values: values.update({
            'account_deletion_operations/' + MODERATOR: {'synthetic': True},
        })
        return result

    h.service.store.get_case = schedule_deletion_after_discovery
    response = h.decision(key)
    assert response.status_code == 409
    assert h.documents.values['content_reports/' + key] == before


def test_deleting_moderator_cannot_replay_its_previously_committed_decision():
    h = Harness()
    assert h.post().status_code == 200
    key = case_key(UID, 'word-report:synthetic-1')
    assert h.decision(key).status_code == 200
    h.documents.values['account_deletion_operations/' + MODERATOR] = {'synthetic': True}
    before = copy.deepcopy(h.documents.values)
    assert h.decision(key).status_code == 409
    assert h.documents.values == before


def test_direct_moderator_page_rejects_actor_deletion_after_reading_a_case():
    h = Harness()
    assert h.post().status_code == 200
    key = case_key(UID, 'word-report:synthetic-1')
    original = h.documents.transact

    def start_deletion_after_read(paths, update):
        result = original(paths, update)
        if 'content_reports/' + key in paths:
            h.documents.values['account_deletion_operations/' + MODERATOR] = {'synthetic': True}
        return result

    h.documents.transact = start_deletion_after_read
    with pytest.raises(ContentReportError, match='deletion_pending'):
        h.service.page(MODERATOR, moderation=True)


def test_moderation_terminal_cas_and_lost_ack_retry_keep_received_receipt_immutable():
    h = Harness()
    received = h.post().json()
    key = case_key(UID, 'word-report:synthetic-1')
    pending = h.client.get('/v1/content-report-moderation/pending', headers=h.headers('moderator')).json()
    assert pending['items'][0]['reportJson'] == submission()['reportJson']
    h.now += timedelta(seconds=5)
    h.documents.lose_next_ack = True
    assert h.decision(key).status_code == 503
    committed = copy.deepcopy(h.documents.values)
    result = h.decision(key)
    assert result.status_code == 200
    assert result.json()['receipt'] == received['receipt']
    assert result.json()['moderation']['status'] == 'resolved'
    assert result.json()['moderation']['revision'] == 2
    assert h.documents.values == committed
    assert h.decision(key, {'publicNote': 'Synthetic changed terminal note'}).status_code == 409
    assert h.decision(key, {'status': 'dismissed'}).status_code == 409
    assert h.documents.values == committed
    assert h.client.get('/v1/content-report-moderation/pending', headers=h.headers('moderator')).json()['items'] == []
    assert h.post().json() == result.json()


@pytest.mark.parametrize('change', [{'expectedRevision': 2}, {'expectedRevision': True},
                                  {'reportSha256': 'f' * 64}, {'moderator': MODERATOR}])
def test_changed_or_forged_moderation_command_cannot_change_the_case(change):
    h = Harness()
    h.post()
    before = copy.deepcopy(h.documents.values)
    assert h.decision(case_key(UID, 'word-report:synthetic-1'), change).status_code in {400, 409}
    assert h.documents.values == before


def test_own_pagination_is_bounded_pure_and_has_no_foreign_content():
    h = Harness()
    for index in range(5):
        assert h.post(submission(report_id='word-report:page-' + str(index))).status_code == 200
    h.post(token='other')
    before = copy.deepcopy(h.documents.values)
    items = []
    cursor = None
    for _ in range(3):
        params = {'limit': 2}
        if cursor is not None:
            params['after'] = cursor
        page = h.client.get('/v1/content-reports', params=params, headers=h.headers()).json()
        items.extend(page['items'])
        cursor = page['nextCursor']
    assert len(items) == 5
    assert len({item['caseKey'] for item in items}) == 5
    assert all(item['receipt']['reportId'].startswith('word-report:page-') for item in items)
    assert cursor is None
    assert h.documents.values == before


@pytest.mark.parametrize('query', ['limit=0', 'limit=51', 'limit=1&limit=2', 'after=not-a-key', 'firebaseUid=' + OTHER])
def test_own_listing_rejects_unbounded_or_owner_override_query(query):
    h = Harness()
    assert h.client.get('/v1/content-reports?' + query, headers=h.headers()).status_code == 400
    assert h.documents.values == {}


def test_transport_enabled_without_composed_authority_fails_closed_and_readiness_reports_it():
    client = TestClient(create_app(content_service=FakeContentService(), token_verifier=ReportTokenVerifier(),
                                   settings=Settings(_env_file=None, content_reports_enabled=True)))
    response = client.post('/v1/content-reports', json={}, headers={'Authorization': 'Bearer synthetic-token'})
    assert response.status_code == 503
    assert response.json()['detail']['code'] == 'REPORTS_UNAVAILABLE'
    assert client.get('/health/ready').status_code == 503
    assert client.get('/health/live').status_code == 200


def test_moderator_default_empty_configuration_and_budget_bounds():
    settings = Settings(_env_file=None)
    assert settings.content_reports_enabled is False
    assert settings.content_report_moderators() == frozenset()
    assert settings.content_report_submissions_per_minute == 10
    assert Settings(_env_file=None, content_report_moderator_uids_json='["synthetic-moderator"]').content_report_moderators() == {MODERATOR}


@pytest.mark.parametrize('value', ['{}', '["synthetic","synthetic"]', '[true]', '[""]', '["bad/uid"]', 'invalid'])
def test_invalid_server_moderator_configuration_is_rejected(value):
    with pytest.raises(ValueError):
        Settings(_env_file=None, content_report_moderator_uids_json=value)


@pytest.mark.parametrize('value', [0, 61])
def test_server_submission_budget_is_bounded(value):
    with pytest.raises(ValueError):
        Settings(_env_file=None, content_report_submissions_per_minute=value)


def test_two_authorized_moderators_cannot_replace_another_operators_terminal_decision():
    h = Harness(moderators=frozenset({MODERATOR, OTHER}))
    h.post()
    key = case_key(UID, 'word-report:synthetic-1')
    assert h.decision(key).status_code == 200
    before = copy.deepcopy(h.documents.values)
    assert h.decision(key, token='other').status_code == 409
    assert h.documents.values == before


def test_concurrent_distinct_terminal_decisions_commit_only_one_result():
    h = Harness()
    h.post()
    key = case_key(UID, 'word-report:synthetic-1')
    def decide(index):
        value = {'schemaVersion': 1, 'decisionId': 'synthetic-decision-' + str(index),
                 'reportSha256': submission()['reportSha256'], 'expectedRevision': 1,
                 'status': 'resolved', 'publicNote': 'Synthetic disposition'}
        try:
            return h.service.decide(MODERATOR, key, value)
        except ContentReportError as error:
            return error.code
    with ThreadPoolExecutor(max_workers=2) as pool:
        replies = list(pool.map(decide, [1, 2]))
    assert len([reply for reply in replies if isinstance(reply, dict)]) == 1
    assert replies.count('conflict') == 1
    assert h.documents.values['content_reports/' + key]['revision'] == 2


@pytest.mark.parametrize('field,value', [('schemaVersion', True), ('schemaVersion', 1.0),
                                        ('revision', True), ('revision', 1.0)])
def test_corrupt_stored_receipt_integer_types_are_unavailable_without_repair(field, value):
    h = Harness()
    h.post()
    key = case_key(UID, 'word-report:synthetic-1')
    h.documents.values['content_reports/' + key][field] = value
    before = copy.deepcopy(h.documents.values)
    response = h.client.get('/v1/content-reports/receipt', params={'reportId': 'word-report:synthetic-1'}, headers=h.headers())
    assert response.status_code == 503
    assert h.documents.values == before


@pytest.mark.parametrize('field', ['schemaVersion', 'expectedRevision'])
def test_corrupt_terminal_decision_integer_types_are_unavailable_without_repair(field):
    h = Harness()
    h.post()
    key = case_key(UID, 'word-report:synthetic-1')
    h.decision(key)
    h.documents.values['content_reports/' + key]['decision'][field] = True
    before = copy.deepcopy(h.documents.values)
    response = h.client.get('/v1/content-reports/receipt', params={'reportId': 'word-report:synthetic-1'}, headers=h.headers())
    assert response.status_code == 503
    assert h.documents.values == before


def test_corrupt_budget_version_does_not_reset_or_overwrite_its_existing_count():
    h = Harness()
    h.post()
    h.documents.values['content_report_limits/' + digest(UID)]['schemaVersion'] = True
    before = copy.deepcopy(h.documents.values)
    assert h.post(submission(report_id='word-report:synthetic-2')).status_code == 503
    assert h.documents.values == before


def test_moderator_pagination_bounds_total_selected_content_without_losing_cases():
    h = Harness(budget=60)
    target = target_v2('readingDocument')
    target['text'] = '"' * 4096
    target['textSha256'] = digest(target['text'])
    for index in range(25):
        assert h.post(submission(report_id='content-report:bounded-' + str(index), target=target)).status_code == 200
    before = copy.deepcopy(h.documents.values)
    items = []
    cursor = None
    for _ in range(5):
        params = {'limit': 25}
        if cursor is not None:
            params['after'] = cursor
        response = h.client.get('/v1/content-report-moderation/pending', params=params, headers=h.headers('moderator'))
        assert response.status_code == 200
        assert len(response.content) <= 512 * 1024
        page = response.json()
        items.extend(page['items'])
        cursor = page['nextCursor']
        if cursor is None:
            break
    assert cursor is None
    assert len(items) == 25
    assert len({item['caseKey'] for item in items}) == 25
    assert all(json.loads(json.loads(item['reportJson'])['snapshotJson'])['text'] == target['text'] for item in items)
    assert h.documents.values == before


def test_pending_moderator_list_skips_accounts_already_waiting_for_deletion():
    h = Harness()
    h.post()
    other = h.post(token='other').json()
    h.documents.values['account_deletion_operations/' + UID] = {'synthetic': True}
    before = copy.deepcopy(h.documents.values)
    page = h.client.get('/v1/content-report-moderation/pending', headers=h.headers('moderator'))
    assert page.status_code == 200
    assert [item['receipt'] for item in page.json()['items']] == [other['receipt']]
    assert h.documents.values == before


def test_current_report_receipt_is_revalidated_after_discovery_before_moderation_commit():
    h = Harness()
    h.post()
    key = case_key(UID, 'word-report:synthetic-1')
    original = h.service.store.get_case
    def changing_owner(value):
        result = original(value)
        h.documents.values['content_reports/' + key]['firebaseUid'] = OTHER
        return result
    h.service.store.get_case = changing_owner
    assert h.decision(key).status_code == 503
    stored = h.documents.values['content_reports/' + key]
    assert stored['revision'] == 1 and stored['decision'] is None


def test_registered_auth_verifier_failure_cannot_reach_any_report_store_operation():
    h = Harness()
    assert h.post(token='synthetic-invalid-token').status_code == 401
    assert h.documents.values == {}
