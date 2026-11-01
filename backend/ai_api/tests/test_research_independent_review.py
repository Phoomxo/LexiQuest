"""Synthetic behavioral canaries from the independent R2 review."""

import base64
import copy
import json
from datetime import timedelta

import pytest

from lexiquest_ai.research import OPERATION_KEYS, ResearchError, json_bytes, wire_time
from research_support import Harness, NOW, UID


@pytest.mark.parametrize('purpose', ['collect', 'export'])
@pytest.mark.parametrize('state', ['expired', 'revoked'])
def test_current_dual_upload_grants_survive_retirement_of_another_purpose(purpose, state):
    h = Harness()
    h.accept()
    for scope in h.record['scopes']:
        for index, encoded in enumerate(scope['operationDocuments']):
            permit = json.loads(base64.b64decode(encoded))
            if permit['operation'] != purpose:
                continue
            if state == 'revoked':
                scope['operationStates'][permit['permitId']]['revoked'] = True
            else:
                permit['expiresAtUtcMs'] = int((NOW - timedelta(seconds=1)).timestamp() * 1000)
                message = json_bytes({key: permit[key] for key in OPERATION_KEYS})
                permit['signature'] = base64.urlsafe_b64encode(h.ed.sign(message)).decode().rstrip('=')
                scope['operationDocuments'][index] = base64.b64encode(json_bytes(permit)).decode()
    request = h.upload()
    receipt = h.service.upload(UID, request)
    assert receipt['payloadSha256'] == request.payloadSha256
    assert h.documents.values['research_study_archives/' + receipt['uploadId']]['payloadBase64'] == request.payloadBase64


def test_completed_motivation_cannot_omit_both_survey_phases_and_index():
    h = Harness()
    h.accept()
    payload = h.archive()
    payload.update(state='completed', closedAtUtc=wire_time(NOW))
    before = copy.deepcopy(h.documents.values)
    with pytest.raises(ResearchError, match='archive_denied'):
        h.service.upload(UID, h.upload(payload))
    assert h.documents.values == before


def test_completed_index_end_must_equal_its_canonical_completion_time():
    h = Harness()
    h.accept()
    payload = h.archive(complete=True)
    payload['index']['endedAtUtc'] = wire_time(NOW - timedelta(minutes=12))
    before = copy.deepcopy(h.documents.values)
    with pytest.raises(ResearchError, match='archive_denied'):
        h.service.upload(UID, h.upload(payload))
    assert h.documents.values == before
