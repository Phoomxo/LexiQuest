from __future__ import annotations

import base64
import copy
import hashlib
import json
import re
from collections.abc import Callable, Mapping
from datetime import UTC, datetime, timedelta
from typing import Annotated, Literal, Protocol

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, ed25519
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
from pydantic import BaseModel, ConfigDict, Field

Code = Annotated[str, Field(min_length=1, max_length=128, pattern=r'^[A-Za-z0-9_.:\-]+$')]
Positive = Annotated[int, Field(strict=True, ge=1, le=9007199254740991)]
Nonnegative = Annotated[int, Field(strict=True, ge=0, le=9007199254740991)]
VersionOne = Annotated[int, Field(strict=True, ge=1, le=1)]
Digest = Annotated[str, Field(pattern=r'^[0-9a-f]{64}$')]


class ResearchError(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class WireModel(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True, hide_input_in_errors=True, frozen=True)


class ResearchBinding(WireModel):
    ownerId: Code
    authSubjectId: Code
    generation: Nonnegative


class ResearchRequirements(WireModel):
    supportedFormatVersion: VersionOne
    trustedIssuerId: Code
    trustedIssuerKeyId: Code
    signatureAlgorithm: Literal['EdDSA']
    assignmentId: Code
    assignmentRevision: Positive
    protocolId: Code
    protocolRevision: Positive
    instrumentId: Code
    instrumentRevision: Positive


class ResearchScope(WireModel):
    binding: ResearchBinding
    requirements: ResearchRequirements
    protocolVersion: Code
    consentVersion: Positive


class ResearchRefreshRequest(WireModel):
    schemaVersion: VersionOne
    scope: ResearchScope
    requestId: Code
    clockSessionId: Code
    monotonicEpoch: Nonnegative


class ResearchConsentRequest(WireModel):
    schemaVersion: VersionOne
    enrollmentId: Code
    ownerId: Code
    consentVersion: Positive
    decision: Literal['accepted', 'withdrawn']
    requestId: Code


class StudyUploadRequest(WireModel):
    schemaVersion: VersionOne
    scope: ResearchScope
    assessmentScope: ResearchScope
    cycleKey: Code
    payloadBase64: Annotated[str, Field(min_length=4, max_length=699052, repr=False)]
    payloadSha256: Digest


class ResearchStore(Protocol):
    def transact(self, firebase_uid: str, upload_id: str | None, update: Callable): ...


OPERATION_KEYS = ('formatVersion', 'permitId', 'issuerId', 'issuerKeyId',
    'signatureAlgorithm', 'ownerId', 'operation', 'assignmentId', 'assignmentRevision',
    'protocolId', 'protocolRevision', 'instrumentId', 'instrumentRevision', 'revision',
    'issuedAtUtcMs', 'expiresAtUtcMs')
PARTICIPATION_KEYS = ('schema', 'id', 'ownerId', 'participantClass', 'ageBandCode',
    'assignmentId', 'assignedTreatment', 'consentReceiptId', 'guardianPermissionReceiptRef',
    'learnerAssentReceiptRef', 'protocolId', 'protocolVersion', 'issuedAtUtc', 'expiresAtUtc',
    'revokedAtUtc', 'issuerKeyId', 'localRevision', 'cloudRevision', 'isDeleted')
RECEIPT_KEYS = ('ownerId', 'receiptId', 'kind', 'revision', 'active', 'issuedAtUtc',
    'expiresAtUtc', 'consentVersion', 'decidedAtUtc')


def json_bytes(value: object) -> bytes:
    return json.dumps(value, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode('utf-8')


def unique_json(data: bytes, maximum: int) -> object:
    if not data or len(data) > maximum:
        raise ResearchError('invalid_payload')
    def pairs(values):
        result = {}
        for key, value in values:
            if key in result:
                raise ValueError()
            result[key] = value
        return result
    try:
        return json.loads(data.decode('utf-8'), object_pairs_hook=pairs,
            parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    except (ValueError, UnicodeError, RecursionError):
        raise ResearchError('invalid_payload') from None


def object_keys(value, keys):
    if not isinstance(value, dict) or set(value) != set(keys):
        raise ResearchError('invalid_payload')
    return value


def code(value):
    if not isinstance(value, str) or re.fullmatch(r'[A-Za-z0-9_.:\-]{1,128}', value) is None:
        raise ResearchError('invalid_payload')
    return value


def integer(value, minimum=0, maximum=9007199254740991):
    if type(value) is not int or not minimum <= value <= maximum:
        raise ResearchError('invalid_payload')
    return value


def digest(value):
    if not isinstance(value, str) or re.fullmatch(r'[0-9a-f]{64}', value) is None:
        raise ResearchError('invalid_payload')
    return value


def authored_identifier(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 256 or value != value.strip():
        raise ResearchError('invalid_payload')
    return value


def validate_archive_pins(role, value):
    if role == 'motivation':
        pins = object_keys(value, ('instrumentVersion', 'instrumentChecksumSha256', 'formId',
            'formVersion', 'itemCatalogVersion', 'scoringRuleVersion', 'items'))
        for key in ('instrumentVersion', 'formId', 'formVersion', 'itemCatalogVersion'):
            code(pins[key])
        digest(pins['instrumentChecksumSha256'])
        if pins['scoringRuleVersion'] != 'normalized-score-v1' or not isinstance(pins['items'], dict) or not 2 <= len(pins['items']) <= 64:
            raise ResearchError('authority_unavailable')
        counts = {'baseline': 0, 'post': 0}
        for item_id, item in pins['items'].items():
            code(item_id)
            object_keys(item, ('timepoint', 'responseCodes'))
            if item['timepoint'] not in counts or not isinstance(item['responseCodes'], dict) or not 2 <= len(item['responseCodes']) <= 10:
                raise ResearchError('authority_unavailable')
            counts[item['timepoint']] += 1
            for response, ordinal in item['responseCodes'].items():
                code(response)
                integer(ordinal, 0, 100)
            if len(set(item['responseCodes'].values())) != len(item['responseCodes']):
                raise ResearchError('authority_unavailable')
        if any(not 1 <= count <= 32 for count in counts.values()):
            raise ResearchError('authority_unavailable')
    else:
        pins = object_keys(value, ('instrumentVersion', 'instrumentChecksumSha256',
            'featureContractRevision', 'featureContractHash', 'forms'))
        authored_identifier(pins['instrumentVersion'])
        code(pins['featureContractRevision'])
        for key in ('instrumentChecksumSha256', 'featureContractHash'):
            digest(pins[key])
        object_keys(pins['forms'], ('pre', 'post'))
        for form in pins['forms'].values():
            object_keys(form, ('formId', 'formVersion', 'formContentRevision', 'formChecksumSha256', 'items'))
            authored_identifier(form['formId'])
            authored_identifier(form['formVersion'])
            integer(form['formContentRevision'], 1)
            digest(form['formChecksumSha256'])
            if not isinstance(form['items'], dict) or not form['items']:
                raise ResearchError('authority_unavailable')
            for item_id, item in form['items'].items():
                authored_identifier(item_id)
                object_keys(item, ('responseCodes',))
                if not isinstance(item['responseCodes'], dict) or not 1 <= len(item['responseCodes']) <= 64:
                    raise ResearchError('authority_unavailable')
                for response, correct in item['responseCodes'].items():
                    if not isinstance(response, str) or re.fullmatch(r'[a-z0-9][a-z0-9._:\-]{0,255}', response) is None or type(correct) is not bool:
                        raise ResearchError('authority_unavailable')


def utc(value: datetime) -> datetime:
    if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() != timedelta(0) or value.microsecond % 1000:
        raise ResearchError('invalid_time')
    if value.year < 1970:
        raise ResearchError('invalid_time')
    return value.astimezone(UTC)


def wire_time(value: datetime) -> str:
    return utc(value).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def timestamp(value) -> datetime:
    if not isinstance(value, str):
        raise ResearchError('invalid_time')
    try:
        result = utc(datetime.fromisoformat(value.replace('Z', '+00:00')))
        if wire_time(result) != value:
            raise ValueError()
        return result
    except (ValueError, OverflowError):
        raise ResearchError('invalid_time') from None


def unbase64(value, maximum, *, url=False):
    if not isinstance(value, str) or len(value) > ((maximum + 2) // 3) * 4:
        raise ResearchError('invalid_payload')
    try:
        raw = base64.b64decode(value + ('=' * (-len(value) % 4) if url else ''),
            altchars=b'-_' if url else None, validate=True)
        canonical = base64.urlsafe_b64encode(raw).decode().rstrip('=') if url else base64.b64encode(raw).decode()
        if len(raw) > maximum or canonical != value:
            raise ValueError()
        return raw
    except (ValueError, UnicodeError):
        raise ResearchError('invalid_payload') from None


def _small_order_ed25519_point(encoded: bytes) -> bool:
    # Match the existing Dart verifier's point admission before OpenSSL verification.
    prime = (1 << 255) - 19
    y = int.from_bytes(encoded, 'little') & ((1 << 255) - 1)
    if y >= prime:
        return True
    y_squared = y * y % prime
    d = -121665 * pow(121666, -1, prime) % prime
    denominator = (d * y_squared + 1) % prime
    if denominator == 0:
        return True
    x_squared = (y_squared - 1) * pow(denominator, -1, prime) % prime
    return x_squared == 0 or y == 0 or (x_squared + y_squared) % prime == 0


class ResearchSignatures:
    def __init__(self, operation_keys: Mapping[str, bytes], participation_keys: Mapping[str, bytes]):
        if any(len(value) != 32 or _small_order_ed25519_point(value) for value in operation_keys.values()):
            raise ResearchError('invalid_configuration')
        self.operation_keys = {code(key): ed25519.Ed25519PublicKey.from_public_bytes(value)
            for key, value in operation_keys.items()}
        self.participation_keys = {code(key): ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), value)
            for key, value in participation_keys.items()}
        if not self.operation_keys or not self.participation_keys:
            raise ResearchError('authority_unavailable')

    def operation(self, encoded: str, expected: ResearchRequirements, owner: str):
        raw = unbase64(encoded, 16384)
        value = object_keys(unique_json(raw, 16384), (*OPERATION_KEYS, 'signature'))
        payload = {key: value[key] for key in OPERATION_KEYS}
        if json_bytes({**payload, 'signature': value['signature']}) != raw:
            raise ResearchError('invalid_signature')
        for key in ('permitId', 'issuerId', 'issuerKeyId', 'ownerId', 'assignmentId', 'protocolId', 'instrumentId'):
            code(value[key])
        pins = expected.model_dump()
        comparisons = {'formatVersion': 'supportedFormatVersion', 'issuerId': 'trustedIssuerId',
            'issuerKeyId': 'trustedIssuerKeyId', 'signatureAlgorithm': 'signatureAlgorithm',
            'assignmentId': 'assignmentId', 'assignmentRevision': 'assignmentRevision',
            'protocolId': 'protocolId', 'protocolRevision': 'protocolRevision',
            'instrumentId': 'instrumentId', 'instrumentRevision': 'instrumentRevision'}
        if value['ownerId'] != owner or value['operation'] not in {'collect', 'export', 'upload'} or any(value[key] != pins[target] for key, target in comparisons.items()):
            raise ResearchError('authority_denied')
        for key in ('formatVersion', 'assignmentRevision', 'protocolRevision', 'instrumentRevision', 'revision'):
            integer(value[key], 1)
        issued = integer(value['issuedAtUtcMs'])
        expires = integer(value['expiresAtUtcMs'])
        if issued >= expires:
            raise ResearchError('authority_denied')
        signature = unbase64(value['signature'], 64, url=True)
        if len(signature) != 64 or _small_order_ed25519_point(signature[:32]):
            raise ResearchError('invalid_signature')
        try:
            self.operation_keys[value['issuerKeyId']].verify(signature, json_bytes(payload))
        except (InvalidSignature, KeyError, ValueError):
            raise ResearchError('invalid_signature') from None
        return value

    def participation(self, document: str, enrollment: dict, now: datetime):
        if not isinstance(document, str):
            raise ResearchError('invalid_payload')
        value = object_keys(unique_json(document.encode('utf-8'), 16384), (*PARTICIPATION_KEYS, 'payloadSha256', 'signature'))
        payload = {key: value[key] for key in PARTICIPATION_KEYS}
        for key in ('id', 'ownerId', 'ageBandCode', 'assignmentId', 'assignedTreatment', 'consentReceiptId', 'protocolId', 'protocolVersion', 'issuerKeyId'):
            code(value[key])
        if value['schema'] != 'lexiquest.research-participation-permit.v1' or value['participantClass'] not in {'adult', 'minor'} or value['assignedTreatment'] not in {'standard', 'adventure'} or value['isDeleted'] is not False:
            raise ResearchError('authority_denied')
        if value['ownerId'] != enrollment['ownerId'] or value['consentReceiptId'] != enrollment['consentReceiptId'] or value['protocolVersion'] != enrollment['protocolVersion']:
            raise ResearchError('authority_denied')
        if value['localRevision'] != value['cloudRevision']:
            raise ResearchError('authority_denied')
        integer(value['localRevision'], 1)
        integer(value['cloudRevision'], 1)
        if not timestamp(value['issuedAtUtc']) <= now < timestamp(value['expiresAtUtc']) or value['revokedAtUtc'] is not None:
            raise ResearchError('authority_denied')
        for key in ('guardianPermissionReceiptRef', 'learnerAssentReceiptRef'):
            if value[key] is not None:
                code(value[key])
            if value['participantClass'] == 'minor' and value[key] is None:
                raise ResearchError('authority_denied')
        encoded = json_bytes(payload)
        if digest(value['payloadSha256']) != hashlib.sha256(encoded).hexdigest():
            raise ResearchError('invalid_signature')
        signature = unbase64(value['signature'], 64)
        if len(signature) != 64:
            raise ResearchError('invalid_signature')
        try:
            self.participation_keys[value['issuerKeyId']].verify(
                encode_dss_signature(int.from_bytes(signature[:32], 'big'), int.from_bytes(signature[32:], 'big')),
                encoded, ec.ECDSA(hashes.SHA256()))
        except (InvalidSignature, KeyError, ValueError):
            raise ResearchError('invalid_signature') from None
        return value


class ResearchService:
    def __init__(self, *, store: ResearchStore, signatures: ResearchSignatures,
                 now_utc: Callable[[], datetime], maximum_age: timedelta = timedelta(minutes=5)):
        if not timedelta(0) < maximum_age <= timedelta(hours=1):
            raise ResearchError('invalid_configuration')
        self.store, self.signatures, self.now_utc, self.maximum_age = store, signatures, now_utc, maximum_age

    def context(self, uid: str):
        def read(enrollment, consents, archive):
            record, _ = self._authority(enrollment, uid, self._now())
            return None, None, {'schemaVersion': 1, 'enrollmentId': record['enrollmentId'],
                'ownerId': record['ownerId'], 'authSubjectId': uid, 'consentVersion': record['consentVersion'],
                'protocolVersion': record['protocolVersion'],
                'scopes': [{'role': scope['role'], 'requirements': scope['requirements']} for scope in record['scopes']]}
        return self.store.transact(uid, None, read)

    def decide(self, uid: str, request: ResearchConsentRequest):
        def update(enrollment, consents, archive):
            now = self._now()
            previous = None
            if consents is not None:
                state = self._consent_record(consents, {'firebaseUid': uid, 'ownerId': request.ownerId})
                previous = state['decisions'].get(self._decision_key(request.enrollmentId, request.consentVersion))
                if previous is not None and any(timestamp(previous[key]) > now for key in ('decidedAtUtc', 'withdrawnAtUtc') if previous[key] is not None):
                    raise ResearchError('invalid_time')
            if previous is not None and (previous['state'] == 'withdrawn' or request.decision == 'withdrawn'):
                if previous['state'] != 'withdrawn':
                    previous = {**previous, 'state': 'withdrawn', 'revision': integer(previous['revision'] + 1, 1),
                        'withdrawnAtUtc': wire_time(now)}
                state['decisions'][self._decision_key(request.enrollmentId, request.consentVersion)] = previous
                return state, None, {'schemaVersion': 1, 'ownerId': request.ownerId,
                    'requestId': request.requestId, **previous}
            record, _ = self._authority(enrollment, uid, now)
            if request.enrollmentId != record['enrollmentId'] or request.ownerId != record['ownerId'] or request.consentVersion != record['consentVersion']:
                raise ResearchError('owner_mismatch')
            state = self._consent_record(consents, record)
            key = self._decision_key(request.enrollmentId, request.consentVersion)
            previous = state['decisions'].get(key)
            if previous is None:
                if len(state['decisions']) >= 256:
                    raise ResearchError('authority_unavailable')
                previous = {'enrollmentId': record['enrollmentId'], 'consentVersion': request.consentVersion,
                    'receiptId': record['consentReceiptId'], 'state': request.decision, 'revision': 1,
                    'decidedAtUtc': wire_time(now) if request.decision == 'accepted' else None,
                    'withdrawnAtUtc': wire_time(now) if request.decision == 'withdrawn' else None}
            state['decisions'][key] = previous
            result = {'schemaVersion': 1, 'ownerId': record['ownerId'], 'requestId': request.requestId, **previous}
            return state, None, result
        return self.store.transact(uid, None, update)

    def refresh(self, uid: str, request: ResearchRefreshRequest):
        def read(enrollment, consents, archive):
            now = self._now()
            record, scopes = self._authority(enrollment, uid, now)
            self._require_scope(uid, request.scope, record)
            state = self._accepted(consents, record, now)
            selected = scopes[request.scope.requirements.instrumentId]
            receipts = self._receipts(selected, record, state, now)
            expiry = min([now + self.maximum_age, timestamp(record['expiresAtUtc']),
                *[timestamp(receipt['expiresAtUtc']) for receipt in receipts],
                *[timestamp(permit['expiresAtUtc']) for permit in selected['participants']]])
            result = {'schemaVersion': 1, 'scope': request.scope.model_dump(),
                'requestId': request.requestId, 'clockSessionId': request.clockSessionId,
                'monotonicEpoch': request.monotonicEpoch, 'snapshotRevision': integer(record['revision'] + state['revision'], 1),
                'anchorUtc': wire_time(now), 'validUntilUtc': wire_time(expiry),
                'maximumAgeMs': int(self.maximum_age.total_seconds() * 1000),
                'operationDocuments': selected['operationDocuments'], 'operationStates': selected['operationStates'],
                'participationDocuments': selected['participationDocuments'], 'receipts': receipts}
            if len(json_bytes(result)) > 1024 * 1024:
                raise ResearchError('authority_unavailable')
            return None, None, result
        return self.store.transact(uid, None, read)

    def upload(self, uid: str, request: StudyUploadRequest):
        raw = unbase64(request.payloadBase64, 512 * 1024)
        if hashlib.sha256(raw).hexdigest() != request.payloadSha256:
            raise ResearchError('digest_mismatch')
        payload = unique_json(raw, 512 * 1024)
        upload_id = self._upload_id(uid, request.scope.requirements.assignmentId, request.cycleKey, request.payloadSha256)
        def update(enrollment, consents, archive):
            now = self._now()
            record, scopes = self._authority(enrollment, uid, now)
            for scope in (request.scope, request.assessmentScope):
                self._require_scope(uid, scope, record)
            if request.scope.binding != request.assessmentScope.binding:
                raise ResearchError('owner_mismatch')
            state = self._accepted(consents, record, now)
            chosen = [scopes[scope.requirements.instrumentId] for scope in (request.scope, request.assessmentScope)]
            if [item['role'] for item in chosen] != ['motivation', 'assessment']:
                raise ResearchError('authority_denied')
            for item in chosen:
                self._receipts(item, record, state, now)
                permit = next((permit for permit in item['permits'] if permit['operation'] == 'upload'), None)
                if permit is None:
                    raise ResearchError('authority_denied')
                current = item['operationStates'][permit['permitId']]
                if current['revoked'] or current['currentRevision'] != permit['revision'] or not permit['issuedAtUtcMs'] <= int(now.timestamp() * 1000) < permit['expiresAtUtcMs']:
                    raise ResearchError('authority_denied')
            trusted_assignment = chosen[0]['requirements']['assignmentId']
            if chosen[1]['requirements']['assignmentId'] != trusted_assignment or upload_id != self._upload_id(uid, trusted_assignment, request.cycleKey, request.payloadSha256):
                raise ResearchError('owner_mismatch')
            validate_study_archive(payload, chosen[0], chosen[1], record, now,
                consent_decided_at=timestamp(state['decidedAtUtc']))
            if archive is not None:
                if archive.get('firebaseUid') != uid or archive.get('ownerId') != record['ownerId'] or archive.get('enrollmentId') != record['enrollmentId'] or archive.get('assignmentId') != trusted_assignment or archive.get('payloadSha256') != request.payloadSha256 or archive.get('payloadBase64') != request.payloadBase64 or archive.get('cycleKey') != request.cycleKey:
                    raise ResearchError('request_conflict')
                receipt = archive['receipt']
                object_keys(receipt, ('schemaVersion', 'uploadId', 'receiptId', 'payloadSha256', 'acceptedAtUtc'))
                if type(receipt['schemaVersion']) is not int or receipt['schemaVersion'] != 1 or receipt['uploadId'] != upload_id or receipt['receiptId'] != 'research-upload:' + upload_id or receipt['payloadSha256'] != request.payloadSha256 or timestamp(receipt['acceptedAtUtc']) > now:
                    raise ResearchError('request_conflict')
                return None, None, receipt
            receipt = {'schemaVersion': 1, 'uploadId': upload_id, 'receiptId': 'research-upload:' + upload_id,
                'payloadSha256': request.payloadSha256, 'acceptedAtUtc': wire_time(now)}
            saved = {'firebaseUid': uid, 'ownerId': record['ownerId'], 'enrollmentId': record['enrollmentId'],
                'assignmentId': trusted_assignment, 'cycleKey': request.cycleKey,
                'payloadSha256': request.payloadSha256, 'payloadBase64': request.payloadBase64, 'receipt': receipt}
            return None, saved, receipt
        return self.store.transact(uid, upload_id, update)

    def _now(self):
        value = self.now_utc()
        return utc(value.replace(microsecond=value.microsecond // 1000 * 1000))

    @staticmethod
    def _upload_id(uid, assignment, cycle, payload_digest):
        return hashlib.sha256(json_bytes(['lexiquest.study-upload.v1', uid, assignment, cycle, payload_digest])).hexdigest()

    def _authority(self, value, uid, now):
        if value is None:
            raise ResearchError('not_enrolled')
        record = object_keys(value, ('schemaVersion', 'firebaseUid', 'enrollmentId', 'ownerId', 'revision',
            'active', 'consentVersion', 'consentReceiptId', 'protocolVersion', 'issuedAtUtc', 'expiresAtUtc', 'scopes'))
        if record['schemaVersion'] != 1 or record['firebaseUid'] != uid or record['active'] is not True:
            raise ResearchError('authority_denied')
        integer(record['schemaVersion'], 1, 1)
        for key in ('enrollmentId', 'ownerId', 'consentReceiptId', 'protocolVersion'):
            code(record[key])
        integer(record['revision'], 1)
        integer(record['consentVersion'], 1)
        if not timestamp(record['issuedAtUtc']) <= now < timestamp(record['expiresAtUtc']):
            raise ResearchError('authority_denied')
        scopes = {}
        if not isinstance(record['scopes'], list) or len(record['scopes']) != 2:
            raise ResearchError('authority_unavailable')
        roles = set()
        for raw in record['scopes']:
            item = object_keys(raw, ('role', 'requirements', 'operationDocuments', 'operationStates', 'participationDocuments', 'receipts', 'archivePins'))
            pins = ResearchRequirements.model_validate(item['requirements'])
            if item['role'] not in {'motivation', 'assessment'} or item['role'] in roles or pins.instrumentId in scopes:
                raise ResearchError('authority_unavailable')
            validate_archive_pins(item['role'], item['archivePins'])
            roles.add(item['role'])
            if not isinstance(item['operationDocuments'], list) or not 1 <= len(item['operationDocuments']) <= 3:
                raise ResearchError('authority_unavailable')
            permits = [self.signatures.operation(document, pins, record['ownerId']) for document in item['operationDocuments']]
            if len({permit['operation'] for permit in permits}) != len(permits) or len({permit['permitId'] for permit in permits}) != len(permits):
                raise ResearchError('authority_denied')
            states = object_keys(item['operationStates'], [permit['permitId'] for permit in permits])
            for permit in permits:
                state = object_keys(states[permit['permitId']], ('currentRevision', 'revoked'))
                if type(state['revoked']) is not bool or integer(state['currentRevision'], 1) < permit['revision']:
                    raise ResearchError('authority_denied')
            documents = item['participationDocuments']
            if not isinstance(documents, list) or not 1 <= len(documents) <= 64:
                raise ResearchError('authority_unavailable')
            participants = [self.signatures.participation(document, record, now) for document in documents]
            if len({permit['id'] for permit in participants}) != len(participants) or any(permit['assignmentId'] != pins.assignmentId or permit['protocolId'] != pins.protocolId for permit in participants):
                raise ResearchError('authority_denied')
            if len({permit['assignedTreatment'] for permit in participants}) != 1:
                raise ResearchError('authority_denied')
            scopes[pins.instrumentId] = {**copy.deepcopy(item), 'permits': permits, 'participants': participants}
        entries = list(scopes.values())
        first, second = (entry['requirements'] for entry in entries)
        if any(first[key] != second[key] for key in ('assignmentId', 'assignmentRevision', 'protocolId', 'protocolRevision')):
            raise ResearchError('authority_denied')
        if entries[0]['participationDocuments'] != entries[1]['participationDocuments']:
            raise ResearchError('authority_denied')
        return record, scopes

    @staticmethod
    def _require_scope(uid, scope, record):
        if scope.binding.authSubjectId != uid or scope.binding.ownerId != record['ownerId']:
            raise ResearchError('owner_mismatch')
        if scope.protocolVersion != record['protocolVersion'] or scope.consentVersion != record['consentVersion'] or not any(scope.requirements.model_dump() == item['requirements'] for item in record['scopes']):
            raise ResearchError('authority_denied')

    @staticmethod
    def _decision_key(enrollment_id, version):
        return hashlib.sha256(json_bytes([enrollment_id, version])).hexdigest()

    @staticmethod
    def _consent_record(value, record):
        if value is None:
            return {'firebaseUid': record['firebaseUid'], 'ownerId': record['ownerId'],
                'decisions': {}}
        result = copy.deepcopy(object_keys(value, ('firebaseUid', 'ownerId', 'decisions')))
        if any(result[key] != record[key] for key in ('firebaseUid', 'ownerId')) or not isinstance(result['decisions'], dict) or len(result['decisions']) > 256:
            raise ResearchError('authority_unavailable')
        for key, decision in result['decisions'].items():
            object_keys(decision, ('enrollmentId', 'consentVersion', 'receiptId', 'state', 'revision', 'decidedAtUtc', 'withdrawnAtUtc'))
            code(decision['enrollmentId'])
            code(decision['receiptId'])
            integer(decision['consentVersion'], 1)
            if key != ResearchService._decision_key(decision['enrollmentId'], decision['consentVersion']):
                raise ResearchError('authority_unavailable')
            integer(decision['revision'], 1)
            if decision['state'] not in {'accepted', 'withdrawn'}:
                raise ResearchError('authority_unavailable')
            if decision['decidedAtUtc'] is not None:
                timestamp(decision['decidedAtUtc'])
            if decision['withdrawnAtUtc'] is not None:
                timestamp(decision['withdrawnAtUtc'])
            if decision['decidedAtUtc'] is not None and decision['withdrawnAtUtc'] is not None and timestamp(decision['withdrawnAtUtc']) < timestamp(decision['decidedAtUtc']):
                raise ResearchError('authority_unavailable')
            if decision['state'] == 'accepted' and (decision['decidedAtUtc'] is None or decision['withdrawnAtUtc'] is not None) or decision['state'] == 'withdrawn' and decision['withdrawnAtUtc'] is None:
                raise ResearchError('authority_unavailable')
        return result

    def _accepted(self, value, record, now):
        state = self._consent_record(value, record)['decisions'].get(self._decision_key(record['enrollmentId'], record['consentVersion']))
        if state is None or state['receiptId'] != record['consentReceiptId'] or state['state'] != 'accepted' or timestamp(state['decidedAtUtc']) > now:
            raise ResearchError('consent_required')
        return state

    @staticmethod
    def _receipts(scope, record, decision, now):
        values = scope['receipts']
        if not isinstance(values, list) or not 1 <= len(values) <= 192:
            raise ResearchError('authority_denied')
        receipts = {}
        for value in values:
            receipt = copy.deepcopy(object_keys(value, RECEIPT_KEYS))
            if receipt['ownerId'] != record['ownerId'] or receipt['kind'] not in {'consent', 'guardianPermission', 'learnerAssent'}:
                raise ResearchError('authority_denied')
            code(receipt['receiptId'])
            integer(receipt['revision'], 1)
            key = (receipt['receiptId'], receipt['kind'])
            if key in receipts or not timestamp(receipt['issuedAtUtc']) <= now < timestamp(receipt['expiresAtUtc']):
                raise ResearchError('authority_denied')
            if receipt['active'] is not True:
                raise ResearchError('authority_denied')
            if receipt['kind'] == 'consent':
                if receipt['receiptId'] != record['consentReceiptId'] or receipt['consentVersion'] != record['consentVersion']:
                    raise ResearchError('authority_denied')
                receipt.update(active=True, decidedAtUtc=decision['decidedAtUtc'], revision=integer(receipt['revision'] + decision['revision'], 1))
            elif receipt['active'] is not True or receipt['consentVersion'] is not None or receipt['decidedAtUtc'] is not None:
                raise ResearchError('authority_denied')
            receipts[key] = receipt
        for participant in scope['participants']:
            required = [(participant['consentReceiptId'], 'consent')]
            if participant['participantClass'] == 'minor':
                required.extend([(participant['guardianPermissionReceiptRef'], 'guardianPermission'), (participant['learnerAssentReceiptRef'], 'learnerAssent')])
            if any(key not in receipts for key in required):
                raise ResearchError('authority_denied')
        return list(receipts.values())


def validate_study_archive(payload, motivation_scope, assessment_scope, enrollment, now, *, consent_decided_at):
    root = object_keys(payload, ('schema', 'cycle', 'assignment', 'participationPermit', 'assignmentRevision',
        'protocolId', 'protocolVersion', 'protocolRevision', 'consentVersion', 'treatment', 'state',
        'startedAtUtc', 'closedAtUtc', 'appVersion', 'buildId', 'databaseSchemaVersion', 'contentRevision',
        'evidencePolicyVersion', 'catalogVersion', 'motivation', 'exposures', 'firstExposureEvent',
        'index', 'assessments', 'missingPhases'))
    pins = motivation_scope['requirements']
    if root['schema'] != 'lexiquest.controlled-study-archive.v1' or any(root[key] != pins[key] for key in ('assignmentRevision', 'protocolId', 'protocolRevision')) or root['consentVersion'] != enrollment['consentVersion'] or root['protocolVersion'] != enrollment['protocolVersion']:
        raise ResearchError('archive_denied')
    participant = motivation_scope['participants'][0]
    if root['treatment'] != participant['assignedTreatment'] or root['state'] not in {'started', 'completed', 'skipped', 'abandoned', 'withdrawn'}:
        raise ResearchError('archive_denied')
    for key in ('appVersion', 'buildId', 'contentRevision', 'evidencePolicyVersion', 'catalogVersion'):
        code(root[key])
    integer(root['databaseSchemaVersion'], 14, 9007199254740991)
    started = timestamp(root['startedAtUtc'])
    if not max(timestamp(enrollment['issuedAtUtc']), timestamp(participant['issuedAtUtc']), consent_decided_at) <= started <= now:
        raise ResearchError('archive_denied')
    closed = None if root['closedAtUtc'] is None else timestamp(root['closedAtUtc'])
    if root['state'] == 'started' and closed is not None or root['state'] != 'started' and closed is None or closed is not None and not started <= closed <= now:
        raise ResearchError('archive_denied')
    identities = set()
    def alias(value, *, introduce=False):
        if not isinstance(value, str) or re.fullmatch(r'r[1-9][0-9]{0,7}', value) is None:
            raise ResearchError('archive_denied')
        if introduce:
            if value in identities:
                raise ResearchError('archive_denied')
            identities.add(value)
        return value
    for key in ('cycle', 'assignment', 'participationPermit'):
        alias(root[key], introduce=True)
    def moment(value, lower=started, upper=now):
        result = timestamp(value)
        if not lower <= result <= upper:
            raise ResearchError('archive_denied')
        return result
    def sequence(value, maximum):
        if not isinstance(value, list) or len(value) > maximum:
            raise ResearchError('archive_denied')
        return value
    def boolean(value):
        if type(value) is not bool:
            raise ResearchError('archive_denied')
        return value
    exposures = sequence(root['exposures'], 1)
    exposure = None
    first_exposure = None
    if exposures:
        exposure = object_keys(exposures[0], ('opportunity', 'openedAtUtc', 'presentedEvent', 'presentedAtUtc',
            'effectivePresentation', 'switchCount', 'isIndex', 'session'))
        alias(exposure['opportunity'], introduce=True)
        opened = moment(exposure['openedAtUtc'])
        if exposure['effectivePresentation'] not in {'standard', 'adventure'}:
            raise ResearchError('archive_denied')
        integer(exposure['switchCount'], 0, 2147483647)
        boolean(exposure['isIndex'])
        if (exposure['presentedEvent'] is None) != (exposure['presentedAtUtc'] is None):
            raise ResearchError('archive_denied')
        if exposure['presentedEvent'] is not None:
            alias(exposure['presentedEvent'], introduce=True)
            first_exposure = moment(exposure['presentedAtUtc'], opened)
        if exposure['session'] is not None:
            alias(exposure['session'], introduce=True)
    if root['firstExposureEvent'] != (None if first_exposure is None else exposure['presentedEvent']):
        raise ResearchError('archive_denied')
    index = root['index']
    completion = None
    if index is not None:
        object_keys(index, ('session', 'state', 'completionRecorded', 'startedAtUtc', 'completedAtUtc', 'endedAtUtc', 'answers'))
        if exposure is None or first_exposure is None or exposure['isIndex'] is not True or index['session'] != exposure['session'] or index['state'] not in {'active', 'completed', 'abandoned'}:
            raise ResearchError('archive_denied')
        index_start = moment(index['startedAtUtc'], first_exposure)
        boolean(index['completionRecorded'])
        if index['state'] == 'completed':
            completion = moment(index['completedAtUtc'], index_start)
            if index['endedAtUtc'] != index['completedAtUtc']:
                raise ResearchError('archive_denied')
        elif index['completedAtUtc'] is not None or index['completionRecorded']:
            raise ResearchError('archive_denied')
        if index['endedAtUtc'] is not None:
            moment(index['endedAtUtc'], completion or index_start)
        answers = sequence(index['answers'], 50)
        for answer in answers:
            object_keys(answer, ('evidence', 'correct', 'occurredAtUtc', 'responseTimeMs', 'evidenceClass'))
            alias(answer['evidence'], introduce=True)
            boolean(answer['correct'])
            moment(answer['occurredAtUtc'], index_start, completion or now)
            if answer['responseTimeMs'] is not None:
                integer(answer['responseTimeMs'], 0, 2147483647)
            if answer['evidenceClass'] not in {'independentRecall', 'recognition', 'guidedPractice', 'pronunciation', 'exposure', 'recreational'}:
                raise ResearchError('archive_denied')
        if index['completionRecorded'] and (completion is None or index['endedAtUtc'] is None or not answers):
            raise ResearchError('archive_denied')
    motivation = object_keys(root['motivation'], ('instrumentId', 'instrumentVersion', 'instrumentRevision',
        'instrumentChecksumSha256', 'formId', 'formVersion', 'itemCatalogVersion', 'scoringRuleVersion',
        'primaryAnalysisEligible', 'responses'))
    authored = motivation_scope['archivePins']
    object_keys(authored, ('instrumentVersion', 'instrumentChecksumSha256', 'formId', 'formVersion',
        'itemCatalogVersion', 'scoringRuleVersion', 'items'))
    if motivation['instrumentId'] != pins['instrumentId'] or motivation['instrumentRevision'] != pins['instrumentRevision'] or any(motivation[key] != authored[key] for key in authored if key != 'items'):
        raise ResearchError('archive_denied')
    items = authored['items']
    if not isinstance(items, dict) or not 2 <= len(items) <= 64:
        raise ResearchError('authority_unavailable')
    seen = set()
    for response in sequence(motivation['responses'], len(items)):
        object_keys(response, ('response', 'itemId', 'timepoint', 'responseCode', 'ordinalValue', 'answeredAtUtc'))
        alias(response['response'], introduce=True)
        item_id = code(response['itemId'])
        item = object_keys(items.get(item_id), ('timepoint', 'responseCodes'))
        if item_id in seen or response['timepoint'] != item['timepoint'] or item['timepoint'] not in {'baseline', 'post'} or not isinstance(item['responseCodes'], dict):
            raise ResearchError('archive_denied')
        seen.add(item_id)
        response_code = code(response['responseCode'])
        if response_code not in item['responseCodes'] or integer(response['ordinalValue'], 0, 100) != item['responseCodes'][response_code]:
            raise ResearchError('archive_denied')
        answered = moment(response['answeredAtUtc'])
        if item['timepoint'] == 'baseline' and first_exposure is not None and answered > first_exposure:
            raise ResearchError('archive_denied')
        if item['timepoint'] == 'post' and (completion is None or not completion <= answered <= completion + timedelta(minutes=30)):
            raise ResearchError('archive_denied')
    completed_points = {point for point in ('baseline', 'post')
        if any(item.get('timepoint') == point for item in items.values()) and
        all(key in seen for key, item in items.items() if item.get('timepoint') == point)}
    if root['state'] == 'completed' and (completed_points != {'baseline', 'post'} or index is None or not index['completionRecorded']):
        raise ResearchError('archive_denied')
    if boolean(motivation['primaryAnalysisEligible']) and root['state'] != 'completed':
        raise ResearchError('archive_denied')
    assessment_pins = assessment_scope['archivePins']
    object_keys(assessment_pins, ('instrumentVersion', 'instrumentChecksumSha256', 'featureContractRevision', 'featureContractHash', 'forms'))
    phases = {}
    for section in sequence(root['assessments'], 2):
        object_keys(section, ('run', 'session', 'phase', 'state', 'startedAtUtc', 'completedAtUtc', 'abandonedAtUtc',
            'instrumentId', 'instrumentVersion', 'instrumentRevision', 'instrumentChecksumSha256', 'formId', 'formVersion',
            'formContentRevision', 'formChecksumSha256', 'featureContractRevision', 'featureContractHash', 'outcomes'))
        phase = section['phase']
        if phase not in {'pre', 'post'} or phase in phases or section['state'] not in {'active', 'completed', 'abandoned'}:
            raise ResearchError('archive_denied')
        phases[phase] = section
        alias(section['run'], introduce=True)
        alias(section['session'], introduce=True)
        started_section = moment(section['startedAtUtc'])
        if phase == 'post' and (completion is None or index['completionRecorded'] is not True or started_section < completion):
            raise ResearchError('archive_denied')
        form = object_keys(assessment_pins['forms'].get(phase), ('formId', 'formVersion', 'formContentRevision', 'formChecksumSha256', 'items'))
        if section['instrumentId'] != assessment_scope['requirements']['instrumentId'] or section['instrumentRevision'] != assessment_scope['requirements']['instrumentRevision'] or any(section[key] != assessment_pins[key] for key in assessment_pins if key != 'forms') or any(section[key] != form[key] for key in form if key != 'items'):
            raise ResearchError('archive_denied')
        end = None
        if section['state'] == 'completed':
            end = moment(section['completedAtUtc'], started_section)
            if section['abandonedAtUtc'] is not None:
                raise ResearchError('archive_denied')
        elif section['state'] == 'abandoned':
            end = moment(section['abandonedAtUtc'], started_section)
            if section['completedAtUtc'] is not None:
                raise ResearchError('archive_denied')
        elif section['completedAtUtc'] is not None or section['abandonedAtUtc'] is not None:
            raise ResearchError('archive_denied')
        if phase == 'pre' and end is not None and first_exposure is not None and end > first_exposure:
            raise ResearchError('archive_denied')
        outcome_items = set()
        for outcome in sequence(section['outcomes'], len(form['items'])):
            object_keys(outcome, ('evidence', 'itemId', 'responseCode', 'correct', 'responseTimeMs', 'occurredAtUtc'))
            alias(outcome['evidence'], introduce=True)
            item_id = authored_identifier(outcome['itemId'])
            correct = object_keys(form['items'].get(item_id), ('responseCodes',))
            response_code = outcome['responseCode']
            if item_id in outcome_items or response_code not in correct['responseCodes'] or boolean(outcome['correct']) != correct['responseCodes'][response_code]:
                raise ResearchError('archive_denied')
            outcome_items.add(item_id)
            integer(outcome['responseTimeMs'], 0, 2147483647)
            moment(outcome['occurredAtUtc'], started_section, end or now)
        if section['state'] == 'completed' and outcome_items != set(form['items']):
            raise ResearchError('archive_denied')
    if ('post' in phases or first_exposure is not None) and ('pre' not in phases or phases['pre']['state'] != 'completed'):
        raise ResearchError('archive_denied')
    if first_exposure is not None and 'baseline' not in completed_points:
        raise ResearchError('archive_denied')
    missing = [f'motivation-{point}' for point in ('baseline', 'post') if point not in completed_points]
    if first_exposure is None:
        missing.append('first-exposure')
    if index is None:
        missing.append('index-session')
    if index is None or not index['completionRecorded']:
        missing.append('index-completion')
    missing.extend(f'assessment-{phase}' for phase in ('pre', 'post') if phase not in phases or phases[phase]['state'] != 'completed')
    if root['missingPhases'] != missing:
        raise ResearchError('archive_denied')
