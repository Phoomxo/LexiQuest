from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Callable, Protocol


class ContentReportError(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def _invalid():
    raise ContentReportError('invalid_request')


def closed_json(data: bytes, maximum_bytes: int = 100_000):
    if len(data) > maximum_bytes:
        _invalid()

    def pairs(values):
        result = {}
        for key, value in values:
            if key in result:
                _invalid()
            result[key] = value
        return result

    try:
        value = json.loads(data.decode('utf-8'), object_pairs_hook=pairs,
                           parse_constant=lambda _: _invalid())
        stack = [(value, 0)]
        nodes = 0
        while stack:
            item, depth = stack.pop()
            nodes += 1
            if depth > 16 or nodes > 2048:
                _invalid()
            if isinstance(item, dict):
                stack.extend((child, depth + 1) for child in item.values())
            elif isinstance(item, list):
                stack.extend((child, depth + 1) for child in item)
        return value
    except (UnicodeError, ValueError, RecursionError):
        _invalid()


def _keys(value, keys):
    if not isinstance(value, dict) or set(value) != set(keys):
        _invalid()
    return value


def _integer(value, low=0, high=8_640_000_000_000_000):
    if type(value) is not int or not low <= value <= high:
        _invalid()
    return value


def _text(value, maximum=256, *, trimmed=False, maximum_bytes=None):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        _invalid()
    if trimmed and value != value.strip():
        _invalid()
    try:
        raw = value.encode('utf-8')
    except UnicodeError:
        _invalid()
    if maximum_bytes is not None and len(raw) > maximum_bytes:
        _invalid()
    return value


def _digest(value):
    if not isinstance(value, str) or re.fullmatch('[a-f0-9]{64}', value) is None:
        _invalid()
    return value


def digest(value: str):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def require_uid(value):
    _text(value, 128, trimmed=True)
    if '/' in value or any(ord(char) < 32 for char in value):
        _invalid()
    return value


def case_key(uid: str, report_id: str):
    require_uid(uid)
    return digest(json.dumps([uid, report_id], ensure_ascii=False, separators=(',', ':')))


def require_case_key(value):
    return _digest(value)


def _report_id(value):
    _text(value, 256, maximum_bytes=256)
    prefix = next((prefix for prefix in ('word-report:', 'content-report:')
                   if value.startswith(prefix)), None)
    if prefix is None or not value[len(prefix):].strip():
        _invalid()
    return value


def _utf8(value):
    if not isinstance(value, str):
        _invalid()
    try:
        return value.encode('utf-8')
    except UnicodeError:
        _invalid()


def _target(snapshot_json, expected_digest):
    raw = _utf8(snapshot_json)
    _digest(expected_digest)
    if digest(snapshot_json) != expected_digest:
        raise ContentReportError('digest_mismatch')
    value = closed_json(raw, 16384)
    if not isinstance(value, dict):
        _invalid()
    if value.get('version') == 'owned-word-report-v1':
        fields = ('version', 'wordId', 'categoryId', 'wordRevision', 'spelling',
                  'meaning', 'partOfSpeech', 'source', 'cefrLevel')
        _keys(value, fields)
        if len(raw) > 8192:
            _invalid()
        for field in ('wordId', 'categoryId'):
            _text(value[field])
        _integer(value['wordRevision'], 1, 0x7fffffffffffffff)
        for field, maximum in (('spelling', 120), ('meaning', 500),
                               ('partOfSpeech', 60), ('source', 60), ('cefrLevel', 12)):
            if field == 'cefrLevel' and value[field] is None:
                continue
            _text(value[field], maximum)
            if len(value[field].encode('utf-16-le')) // 2 > maximum:
                _invalid()
        canonical = json.dumps({field: value[field] for field in fields},
                               ensure_ascii=False, separators=(',', ':'))
        if canonical != snapshot_json:
            _invalid()
        return
    _keys(value, ('version', 'kind', 'text', 'textSha256', 'isExcerpt', 'source'))
    if value['version'] != 'content-report-target-v2' or type(value['isExcerpt']) is not bool:
        _invalid()
    _text(value['text'], 4096, maximum_bytes=16384)
    if _digest(value['textSha256']) != digest(value['text']):
        raise ContentReportError('digest_mismatch')
    source = value['source']
    if value['kind'] == 'packEntry':
        _keys(source, ('packId', 'packVersion', 'packageSha256', 'entryCode', 'entrySha256'))
        for field in ('packId', 'packVersion', 'entryCode'):
            _text(source[field])
        for field in ('packageSha256', 'entrySha256'):
            _digest(source[field])
    elif value['kind'] == 'aiOutput':
        _keys(source, ('sessionId', 'acceptedPlanId', 'contentKind', 'modelVersion', 'cached', 'origin'))
        for field in ('sessionId', 'acceptedPlanId', 'contentKind'):
            _text(source[field])
        _text(source['modelVersion'], 512)
        if type(source['cached']) is not bool or source['origin'] not in ('generated', 'fallback', 'unrecorded'):
            _invalid()
    elif value['kind'] == 'tutorReply':
        _keys(source, ('replyId', 'modelVersion', 'generatedAtUtcMs'))
        _text(source['replyId'])
        _text(source['modelVersion'], 512)
        _integer(source['generatedAtUtcMs'])
    elif value['kind'] == 'readingDocument':
        _keys(source, ('documentId', 'documentRevision', 'documentSha256', 'identityKind'))
        _text(source['documentId'])
        _integer(source['documentRevision'], 1, 0x7fffffffffffffff)
        _digest(source['documentSha256'])
        if source['identityKind'] not in ('supplied', 'contentDigest'):
            _invalid()
    else:
        _invalid()


@dataclass(frozen=True)
class ReportSubmission:
    report_id: str
    report_json: str
    report_sha256: str

    @classmethod
    def parse(cls, value):
        _keys(value, ('schemaVersion', 'reportJson', 'reportSha256'))
        _integer(value['schemaVersion'], 1, 1)
        raw = _utf8(value['reportJson'])
        expected = _digest(value['reportSha256'])
        if digest(value['reportJson']) != expected:
            raise ContentReportError('digest_mismatch')
        report = _keys(closed_json(raw, 32768), ('schemaVersion', 'reportId', 'snapshotJson',
                       'snapshotSha256', 'reason', 'comment', 'queuedAtUtcMs'))
        _integer(report['schemaVersion'], 1, 1)
        report_id = _report_id(report['reportId'])
        _integer(report['queuedAtUtcMs'])
        if report['reason'] not in ('incorrectMeaning', 'spelling', 'partOfSpeech', 'inappropriate', 'other'):
            _invalid()
        if report['comment'] is not None:
            _text(report['comment'], 500, trimmed=True, maximum_bytes=2048)
        elif report['reason'] == 'other':
            _invalid()
        _target(report['snapshotJson'], report['snapshotSha256'])
        return cls(report_id, value['reportJson'], expected)


class ContentReportStore(Protocol):
    def transact(self, uid: str, key: str, update: Callable, *, budget: bool = False,
                 actor_uid: str | None = None): ...
    def require_active(self, uid: str): ...
    def get_case(self, key: str): ...
    def list_cases(self, *, uid: str | None, after: str | None, limit: int): ...


class ContentReportService:
    def __init__(self, *, store: ContentReportStore, now_utc: Callable[[], datetime],
                 moderator_uids=frozenset(), submissions_per_minute=10):
        if type(submissions_per_minute) is not int or not 1 <= submissions_per_minute <= 60:
            raise ValueError('Report budget must be between 1 and 60')
        self.store = store
        self.now_utc = now_utc
        self.moderator_uids = frozenset(require_uid(uid) for uid in moderator_uids)
        self.submissions_per_minute = submissions_per_minute

    def _now(self):
        now = self.now_utc()
        if not isinstance(now, datetime) or now.tzinfo is None or now.utcoffset() != UTC.utcoffset(now):
            raise ContentReportError('unavailable')
        return _integer(int(now.timestamp() * 1000))

    def require_moderator(self, uid):
        require_uid(uid)
        if uid not in self.moderator_uids:
            raise ContentReportError('moderator_required')
        self.store.require_active(uid)

    def submit(self, uid: str, value):
        require_uid(uid)
        submission = ReportSubmission.parse(value)
        key = case_key(uid, submission.report_id)
        now = self._now()

        def update(stored, budget):
            if stored is not None:
                original = self._stored(stored, key, now)
                if (original.report_id != submission.report_id or
                        original.report_sha256 != submission.report_sha256 or
                        original.report_json != submission.report_json):
                    raise ContentReportError('conflict')
                return None, None, self._view(stored, key)
            minute = now // 60000 * 60000
            used = 0
            if budget is not None:
                try:
                    _keys(budget, ('schemaVersion', 'firebaseUid', 'windowStartedAtUtcMs', 'submissions'))
                    _integer(budget['schemaVersion'], 1, 1)
                    start = _integer(budget['windowStartedAtUtcMs'])
                    count = _integer(budget['submissions'], 1, 60)
                except ContentReportError:
                    raise ContentReportError('unavailable') from None
                if budget['firebaseUid'] != uid:
                    raise ContentReportError('unavailable')
                if start > minute or start % 60000:
                    raise ContentReportError('unavailable')
                if start == minute:
                    used = count
            if used >= self.submissions_per_minute:
                raise ContentReportError('rate_limited')
            record = {'schemaVersion': 1, 'firebaseUid': uid, 'reportId': submission.report_id,
                      'reportJson': submission.report_json, 'reportSha256': submission.report_sha256,
                      'receivedAtUtcMs': now, 'revision': 1, 'status': 'received', 'decision': None}
            counter = {'schemaVersion': 1, 'firebaseUid': uid,
                       'windowStartedAtUtcMs': minute, 'submissions': used + 1}
            return record, counter, self._view(record, key)

        return self.store.transact(uid, key, update, budget=True)

    def receipt(self, uid: str, report_id: str):
        require_uid(uid)
        _report_id(report_id)
        key = case_key(uid, report_id)

        def read(stored, _):
            if stored is None:
                raise ContentReportError('not_found')
            self._stored(stored, key, self._now())
            return None, None, self._view(stored, key)

        return self.store.transact(uid, key, read)

    def page(self, uid: str, *, after=None, limit=20, moderation=False):
        require_uid(uid)
        _integer(limit, 1, 25 if moderation else 50)
        if after is not None:
            require_case_key(after)
        if moderation:
            self.require_moderator(uid)
        rows = self.store.list_cases(uid=None if moderation else uid, after=after, limit=limit + 1)
        if moderation:
            self.require_moderator(uid)
        items = []
        size = 256
        cursor = None
        for key, stored in rows[:limit]:
            owner = require_uid(stored.get('firebaseUid'))
            self._stored(stored, key, self._now())
            if not moderation and owner != uid:
                raise ContentReportError('unavailable')

            def read(current, _):
                if current is None:
                    return None, None, None
                self._stored(current, key, self._now())
                if moderation and current['status'] != 'received':
                    return None, None, None
                item = self._view(current, key)
                item.pop('schemaVersion')
                item['caseKey'] = key
                if moderation:
                    item['reportJson'] = current['reportJson']
                return None, None, item

            try:
                item = self.store.transact(owner, key, read, actor_uid=uid if moderation else None)
            except ContentReportError as error:
                if moderation and error.code == 'deletion_pending':
                    self.require_moderator(uid)
                    cursor = key
                    continue
                raise
            if item is not None:
                item_size = len(json.dumps(item, ensure_ascii=False).encode('utf-8'))
                if size + item_size > 512 * 1024:
                    if moderation:
                        self.require_moderator(uid)
                    return {'schemaVersion': 1, 'items': items, 'nextCursor': cursor}
                items.append(item)
                size += item_size
            cursor = key
        if moderation:
            self.require_moderator(uid)
        return {'schemaVersion': 1, 'items': items,
                'nextCursor': cursor if len(rows) > limit else None}

    def decide(self, uid: str, key: str, value):
        self.require_moderator(uid)
        require_case_key(key)
        _keys(value, ('schemaVersion', 'decisionId', 'reportSha256', 'expectedRevision', 'status', 'publicNote'))
        _integer(value['schemaVersion'], 1, 1)
        _integer(value['expectedRevision'], 1, 1)
        _text(value['decisionId'], 256, trimmed=True, maximum_bytes=256)
        _digest(value['reportSha256'])
        _text(value['publicNote'], 500, trimmed=True, maximum_bytes=2048)
        if value['status'] not in ('resolved', 'dismissed'):
            _invalid()
        discovered = self.store.get_case(key)
        self.require_moderator(uid)
        if discovered is None:
            raise ContentReportError('not_found')
        owner = require_uid(discovered.get('firebaseUid'))
        now = self._now()
        decision = {**value, 'moderatorBinding': digest(uid)}

        def update(stored, _):
            if stored is None:
                raise ContentReportError('not_found')
            self._stored(stored, key, now)
            if stored['reportSha256'] != value['reportSha256']:
                raise ContentReportError('conflict')
            previous = stored['decision']
            if previous is not None:
                if {field: previous[field] for field in decision} != decision:
                    raise ContentReportError('conflict')
                return None, None, self._view(stored, key)
            if stored['revision'] != value['expectedRevision']:
                raise ContentReportError('conflict')
            updated = {**stored, 'revision': 2, 'status': value['status'],
                       'decision': {**decision, 'decidedAtUtcMs': now}}
            return updated, None, self._view(updated, key)

        return self.store.transact(owner, key, update, actor_uid=uid)

    def _stored(self, value, key, now):
        try:
            return self._stored_facts(value, key, now)
        except ContentReportError:
            raise ContentReportError('unavailable') from None

    def _stored_facts(self, value, key, now):
        _keys(value, ('schemaVersion', 'firebaseUid', 'reportId', 'reportJson', 'reportSha256',
                      'receivedAtUtcMs', 'revision', 'status', 'decision'))
        _integer(value['schemaVersion'], 1, 1)
        _integer(value['revision'], 1, 2)
        owner = require_uid(value['firebaseUid'])
        submission = ReportSubmission.parse({'schemaVersion': 1, 'reportJson': value['reportJson'],
                                             'reportSha256': value['reportSha256']})
        if (value['schemaVersion'] != 1 or submission.report_id != value['reportId'] or
                case_key(owner, submission.report_id) != key or
                _integer(value['receivedAtUtcMs']) > now):
            raise ContentReportError('unavailable')
        if value['status'] == 'received':
            if value['revision'] != 1 or value['decision'] is not None:
                raise ContentReportError('unavailable')
        elif value['status'] in ('resolved', 'dismissed'):
            decision = _keys(value['decision'], ('schemaVersion', 'decisionId', 'reportSha256',
                             'expectedRevision', 'status', 'publicNote', 'moderatorBinding', 'decidedAtUtcMs'))
            _integer(decision['schemaVersion'], 1, 1)
            _integer(decision['expectedRevision'], 1, 1)
            if (value['revision'] != 2 or decision['schemaVersion'] != 1 or
                    decision['expectedRevision'] != 1 or decision['status'] != value['status'] or
                    decision['reportSha256'] != value['reportSha256'] or
                    not value['receivedAtUtcMs'] <= _integer(decision['decidedAtUtcMs']) <= now):
                raise ContentReportError('unavailable')
            _text(decision['decisionId'], 256, trimmed=True, maximum_bytes=256)
            _text(decision['publicNote'], 500, trimmed=True, maximum_bytes=2048)
            _digest(decision['moderatorBinding'])
        else:
            raise ContentReportError('unavailable')
        return submission

    @staticmethod
    def _view(value, key):
        decision = value['decision']
        return {'schemaVersion': 1,
                'receipt': {'reportId': value['reportId'], 'reportSha256': value['reportSha256'],
                            'receiptId': 'content-report-receipt:' + key,
                            'receivedAtUtc': _wire_time(value['receivedAtUtcMs'])},
                'moderation': {'revision': value['revision'], 'status': value['status'],
                               'decisionId': None if decision is None else decision['decisionId'],
                               'publicNote': None if decision is None else decision['publicNote'],
                               'decidedAtUtc': None if decision is None else _wire_time(decision['decidedAtUtcMs'])}}


def _wire_time(milliseconds):
    return datetime.fromtimestamp(milliseconds / 1000, UTC).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
