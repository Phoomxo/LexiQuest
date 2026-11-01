import base64
import copy
import hashlib
import json
import threading
from datetime import UTC, datetime, timedelta

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

from lexiquest_ai.config import Settings
from lexiquest_ai.firestore_research import FirestoreResearchStore
from lexiquest_ai.research import (
    OPERATION_KEYS, PARTICIPATION_KEYS, ResearchConsentRequest, ResearchRefreshRequest,
    ResearchScope, ResearchService, ResearchSignatures, StudyUploadRequest, json_bytes, wire_time,
)

NOW = datetime(2026, 11, 1, 12, tzinfo=UTC)
UID = 'synthetic-research-uid'
OWNER = 'synthetic-research-owner'


class Documents:
    def __init__(self):
        self.values = {}
        self.lock = threading.Lock()
        self.writes = 0

    def transact(self, paths, update):
        with self.lock:
            current = {path: copy.deepcopy(self.values.get(path)) for path in paths}
            writes, result = update(current)
            for path, value in writes.items():
                assert path in paths
                self.values[path] = copy.deepcopy(value)
                self.writes += 1
            return result


class Harness:
    def __init__(self, *, minor=False):
        # Explicitly synthetic deterministic signing keys: tests only, never runtime assets/config.
        self.ed = ed25519.Ed25519PrivateKey.from_private_bytes(bytes(range(32)))
        self.p256 = ec.derive_private_key(1, ec.SECP256R1())
        self.ed_public = self.ed.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        self.p256_public = self.p256.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
        self.documents = Documents()
        self.now = NOW
        self.signatures = ResearchSignatures({'synthetic-ed': self.ed_public}, {'synthetic-p256': self.p256_public})
        self.service = ResearchService(store=FirestoreResearchStore(self.documents), signatures=self.signatures, now_utc=lambda: self.now)
        self.record = self.enrollment(minor=minor)
        self.documents.values['research_enrollments/' + UID] = self.record

    def settings(self):
        return Settings(_env_file=None, research_enabled=True,
            research_operation_public_keys_json=json.dumps({'synthetic-ed': base64.b64encode(self.ed_public).decode()}),
            research_participation_public_keys_json=json.dumps({'synthetic-p256': self.p256_public.hex()}))

    def scope(self, role='motivation'):
        item = next(item for item in self.record['scopes'] if item['role'] == role)
        return ResearchScope.model_validate({'binding': {'ownerId': OWNER, 'authSubjectId': UID, 'generation': 3},
            'requirements': item['requirements'], 'protocolVersion': self.record['protocolVersion'], 'consentVersion': self.record['consentVersion']})

    def consent(self, decision='accepted', **changes):
        return ResearchConsentRequest.model_validate({'schemaVersion': 1, 'enrollmentId': self.record['enrollmentId'],
            'ownerId': OWNER, 'consentVersion': self.record['consentVersion'], 'decision': decision, 'requestId': 'synthetic-request', **changes})

    def accept(self):
        current = self.now
        self.now = NOW - timedelta(hours=1)
        try:
            return self.service.decide(UID, self.consent())
        finally:
            self.now = current

    def refresh(self, role='motivation'):
        return ResearchRefreshRequest(schemaVersion=1, scope=self.scope(role), requestId='synthetic-refresh',
            clockSessionId='synthetic-clock', monotonicEpoch=5)

    def upload(self, payload=None):
        payload = self.archive() if payload is None else payload
        encoded = json_bytes(payload)
        return StudyUploadRequest(schemaVersion=1, scope=self.scope(), assessmentScope=self.scope('assessment'),
            cycleKey='synthetic-cycle', payloadBase64=base64.b64encode(encoded).decode(), payloadSha256=hashlib.sha256(encoded).hexdigest())

    def enrollment(self, *, minor):
        participant = {'schema': 'lexiquest.research-participation-permit.v1', 'id': 'synthetic-participation',
            'ownerId': OWNER, 'participantClass': 'minor' if minor else 'adult', 'ageBandCode': 'synthetic-age-band',
            'assignmentId': 'synthetic-assignment', 'assignedTreatment': 'standard', 'consentReceiptId': 'synthetic-consent',
            'guardianPermissionReceiptRef': 'synthetic-guardian' if minor else None,
            'learnerAssentReceiptRef': 'synthetic-assent' if minor else None,
            'protocolId': 'synthetic-protocol', 'protocolVersion': 'synthetic-protocol-v1',
            'issuedAtUtc': wire_time(NOW - timedelta(days=1)), 'expiresAtUtc': wire_time(NOW + timedelta(days=1)),
            'revokedAtUtc': None, 'issuerKeyId': 'synthetic-p256', 'localRevision': 1, 'cloudRevision': 1, 'isDeleted': False}
        signed = json_bytes({key: participant[key] for key in PARTICIPATION_KEYS})
        r, s = decode_dss_signature(self.p256.sign(signed, ec.ECDSA(hashes.SHA256())))
        participant.update(payloadSha256=hashlib.sha256(signed).hexdigest(),
            signature=base64.b64encode(r.to_bytes(32, 'big') + s.to_bytes(32, 'big')).decode())
        scopes = []
        for role in ('motivation', 'assessment'):
            pins = {'supportedFormatVersion': 1, 'trustedIssuerId': 'synthetic-issuer', 'trustedIssuerKeyId': 'synthetic-ed',
                'signatureAlgorithm': 'EdDSA', 'assignmentId': 'synthetic-assignment', 'assignmentRevision': 1,
                'protocolId': 'synthetic-protocol', 'protocolRevision': 1, 'instrumentId': 'synthetic-' + role, 'instrumentRevision': 1}
            operations, states = [], {}
            for purpose in ('collect', 'export', 'upload'):
                permit = {'formatVersion': 1, 'permitId': f'synthetic-{role}-{purpose}', 'issuerId': 'synthetic-issuer',
                    'issuerKeyId': 'synthetic-ed', 'signatureAlgorithm': 'EdDSA', 'ownerId': OWNER, 'operation': purpose,
                    'assignmentId': 'synthetic-assignment', 'assignmentRevision': 1, 'protocolId': 'synthetic-protocol',
                    'protocolRevision': 1, 'instrumentId': pins['instrumentId'], 'instrumentRevision': 1, 'revision': 1,
                    'issuedAtUtcMs': int((NOW - timedelta(days=1)).timestamp() * 1000),
                    'expiresAtUtcMs': int((NOW + timedelta(days=1)).timestamp() * 1000)}
                permit['signature'] = base64.urlsafe_b64encode(self.ed.sign(json_bytes({key: permit[key] for key in OPERATION_KEYS}))).decode().rstrip('=')
                operations.append(base64.b64encode(json_bytes(permit)).decode())
                states[permit['permitId']] = {'currentRevision': 1, 'revoked': False}
            receipts = [{'ownerId': OWNER, 'receiptId': 'synthetic-consent', 'kind': 'consent', 'revision': 1, 'active': True,
                'issuedAtUtc': wire_time(NOW - timedelta(days=1)), 'expiresAtUtc': wire_time(NOW + timedelta(days=1)),
                'consentVersion': 1, 'decidedAtUtc': None}]
            if minor:
                receipts.extend({**receipts[0], 'receiptId': 'synthetic-' + suffix, 'kind': kind,
                    'consentVersion': None} for suffix, kind in (('guardian', 'guardianPermission'), ('assent', 'learnerAssent')))
            authored = {'instrumentVersion': 'synthetic-v1', 'instrumentChecksumSha256': 'a' * 64,
                'formId': 'synthetic-motivation-form', 'formVersion': 'synthetic-v1', 'itemCatalogVersion': 'synthetic-v1',
                'scoringRuleVersion': 'normalized-score-v1', 'items': {
                    'baseline-item': {'timepoint': 'baseline', 'responseCodes': {'agree': 1, 'disagree': 0}},
                    'post-item': {'timepoint': 'post', 'responseCodes': {'agree': 1, 'disagree': 0}}}}
            if role == 'assessment':
                authored = {'instrumentVersion': 'synthetic-v1', 'instrumentChecksumSha256': 'b' * 64,
                    'featureContractRevision': 'synthetic-v1', 'featureContractHash': 'c' * 64,
                    'forms': {phase: {'formId': 'synthetic-form-' + phase, 'formVersion': 'synthetic-v1',
                        'formContentRevision': 1, 'formChecksumSha256': 'd' * 64,
                        'items': {phase + '-item': {'responseCodes': {'correct': True, 'other': False}}}}
                        for phase in ('pre', 'post')}}
            scopes.append({'role': role, 'requirements': pins, 'operationDocuments': operations, 'operationStates': states,
                'participationDocuments': [json_bytes(participant).decode()], 'receipts': receipts, 'archivePins': authored})
        return {'schemaVersion': 1, 'firebaseUid': UID, 'enrollmentId': 'synthetic-enrollment', 'ownerId': OWNER,
            'revision': 1, 'active': True, 'consentVersion': 1, 'consentReceiptId': 'synthetic-consent',
            'protocolVersion': 'synthetic-protocol-v1', 'issuedAtUtc': wire_time(NOW - timedelta(days=1)),
            'expiresAtUtc': wire_time(NOW + timedelta(days=1)), 'scopes': scopes}

    def archive(self, *, complete=False):
        def time(minutes):
            return wire_time(NOW - timedelta(minutes=20 - minutes))
        motivation = {key: value for key, value in self.record['scopes'][0]['archivePins'].items() if key != 'items'}
        motivation.update(instrumentId='synthetic-motivation', instrumentRevision=1, primaryAnalysisEligible=False, responses=[])
        result = {'schema': 'lexiquest.controlled-study-archive.v1', 'cycle': 'r1', 'assignment': 'r2',
            'participationPermit': 'r3', 'assignmentRevision': 1, 'protocolId': 'synthetic-protocol',
            'protocolVersion': 'synthetic-protocol-v1', 'protocolRevision': 1, 'consentVersion': 1,
            'treatment': 'standard', 'state': 'started', 'startedAtUtc': time(0), 'closedAtUtc': None,
            'appVersion': 'synthetic-app', 'buildId': 'synthetic-build', 'databaseSchemaVersion': 22,
            'contentRevision': 'synthetic-v1', 'evidencePolicyVersion': 'synthetic-v1', 'catalogVersion': 'synthetic-v1',
            'motivation': motivation, 'exposures': [], 'firstExposureEvent': None, 'index': None, 'assessments': [],
            'missingPhases': ['motivation-baseline', 'motivation-post', 'first-exposure', 'index-session',
                'index-completion', 'assessment-pre', 'assessment-post']}
        if not complete:
            return result
        result.update(state='completed', closedAtUtc=time(10), missingPhases=[], firstExposureEvent='r5',
            exposures=[{'opportunity': 'r4', 'openedAtUtc': time(4), 'presentedEvent': 'r5', 'presentedAtUtc': time(5),
                'effectivePresentation': 'standard', 'switchCount': 0, 'isIndex': True, 'session': 'r6'}],
            index={'session': 'r6', 'state': 'completed', 'completionRecorded': True, 'startedAtUtc': time(5),
                'completedAtUtc': time(7), 'endedAtUtc': time(7), 'answers': [{'evidence': 'r11', 'correct': True,
                    'occurredAtUtc': time(6), 'responseTimeMs': 1200, 'evidenceClass': 'independentRecall'}]})
        motivation.update(primaryAnalysisEligible=True, responses=[{'response': alias, 'itemId': point + '-item',
            'timepoint': point, 'responseCode': 'agree', 'ordinalValue': 1, 'answeredAtUtc': time(at)}
            for alias, point, at in (('r7', 'baseline', 2), ('r15', 'post', 9))])
        for phase, run, session, evidence, start, finish in (
                ('post', 'r12', 'r13', 'r14', 8, 9), ('pre', 'r8', 'r9', 'r10', 2, 4)):
            authored = self.record['scopes'][1]['archivePins']
            form = authored['forms'][phase]
            result['assessments'].append({**{key: value for key, value in authored.items() if key != 'forms'},
                **{key: value for key, value in form.items() if key != 'items'},
                'instrumentId': 'synthetic-assessment', 'instrumentRevision': 1, 'run': run, 'session': session,
                'phase': phase, 'state': 'completed', 'startedAtUtc': time(start), 'completedAtUtc': time(finish),
                'abandonedAtUtc': None, 'outcomes': [{'evidence': evidence, 'itemId': phase + '-item', 'responseCode': 'correct',
                    'correct': True, 'responseTimeMs': 900, 'occurredAtUtc': time(start + 1)}]})
        return result
