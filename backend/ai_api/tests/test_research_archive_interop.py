import base64
import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

from lexiquest_ai.research import OPERATION_KEYS, PARTICIPATION_KEYS, StudyUploadRequest, json_bytes

import research_support
from research_support import Harness, UID


def test_actual_dart_sqlite_archive_bytes_upload_without_projection_rewriting(monkeypatch):
    raw = (Path(__file__).parent / 'fixtures/research_client_archive_v1.json').read_bytes()
    expected = 'b319819f0466d7840326128e9ec9f3700a54822c8c6fa748e316c9386b0dbec0'
    assert hashlib.sha256(raw).hexdigest() == expected
    payload = json.loads(raw)
    monkeypatch.setattr(research_support, 'NOW', datetime(2026, 10, 29, 12, 4, tzinfo=UTC))
    h = Harness()
    h.record.update(protocolVersion=payload['protocolVersion'], consentVersion=payload['consentVersion'])
    for scope in h.record['scopes']:
        metadata = payload['motivation'] if scope['role'] == 'motivation' else payload['assessments'][0]
        pins = scope['requirements']
        pins.update(protocolId=payload['protocolId'], protocolRevision=payload['protocolRevision'],
            assignmentRevision=payload['assignmentRevision'], instrumentId=metadata['instrumentId'],
            instrumentRevision=metadata['instrumentRevision'])
        operations = []
        for encoded in scope['operationDocuments']:
            document = json.loads(base64.b64decode(encoded))
            for key in ('protocolId', 'protocolRevision', 'assignmentRevision', 'instrumentId', 'instrumentRevision'):
                document[key] = pins[key]
            signed = json_bytes({key: document[key] for key in OPERATION_KEYS})
            document['signature'] = base64.urlsafe_b64encode(h.ed.sign(signed)).decode().rstrip('=')
            operations.append(base64.b64encode(json_bytes(document)).decode())
        scope['operationDocuments'] = operations
        participant = json.loads(scope['participationDocuments'][0])
        participant.update(protocolId=payload['protocolId'], protocolVersion=payload['protocolVersion'])
        signed = json_bytes({key: participant[key] for key in PARTICIPATION_KEYS})
        r, s = decode_dss_signature(h.p256.sign(signed, ec.ECDSA(hashes.SHA256())))
        participant.update(payloadSha256=hashlib.sha256(signed).hexdigest(),
            signature=base64.b64encode(r.to_bytes(32, 'big') + s.to_bytes(32, 'big')).decode())
        scope['participationDocuments'] = [json_bytes(participant).decode()]
        scope['receipts'][0]['consentVersion'] = payload['consentVersion']
        if scope['role'] == 'motivation':
            scope['archivePins'] = {key: payload['motivation'][key] for key in
                ('instrumentVersion', 'instrumentChecksumSha256', 'formId', 'formVersion', 'itemCatalogVersion', 'scoringRuleVersion')}
            # Matches the independent actual Dart synthetic instrument, not submitted answer values.
            scope['archivePins']['items'] = {f'synthetic-{point}': {
                'timepoint': point, 'responseCodes': {'low': 0, 'high': 1}} for point in ('baseline', 'post')}
        else:
            scope['archivePins'] = {key: metadata[key] for key in
                ('instrumentVersion', 'instrumentChecksumSha256', 'featureContractRevision', 'featureContractHash')}
            scope['archivePins']['forms'] = {section['phase']: {
                **{key: section[key] for key in ('formId', 'formVersion', 'formContentRevision', 'formChecksumSha256')},
                'items': {'synthetic-assessment-item': {'responseCodes': {'correct': True, 'incorrect': False}}}}
                for section in payload['assessments']}
    h.record['scopes'][1]['participationDocuments'] = list(h.record['scopes'][0]['participationDocuments'])
    h.accept()
    request = StudyUploadRequest(schemaVersion=1, scope=h.scope(), assessmentScope=h.scope('assessment'),
        cycleKey='synthetic-original-cycle', payloadBase64=base64.b64encode(raw).decode(), payloadSha256=expected)
    receipt = h.service.upload(UID, request)
    assert receipt['payloadSha256'] == expected
    saved = h.documents.values['research_study_archives/' + receipt['uploadId']]
    assert base64.b64decode(saved['payloadBase64']) == raw
    assert h.service.upload(UID, request) == receipt
