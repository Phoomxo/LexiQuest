import copy
from datetime import UTC, datetime
import json
from threading import RLock

from fastapi import HTTPException
from fastapi.testclient import TestClient

from lexiquest_ai.app import create_app
from lexiquest_ai.auth import AuthenticatedUser
from lexiquest_ai.config import Settings
from lexiquest_ai.content_reports import ContentReportService, digest
from lexiquest_ai.firestore_content_reports import FirestoreContentReportStore

from conftest import FakeContentService

UID = 'synthetic-reporter'
OTHER = 'synthetic-other'
MODERATOR = 'synthetic-moderator'


def wire_json(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


def word_snapshot():
    return {'version': 'owned-word-report-v1', 'wordId': 'synthetic-word',
            'categoryId': 'synthetic-category', 'wordRevision': 7, 'spelling': 'harbor',
            'meaning': 'ท่าเรือ', 'partOfSpeech': 'noun', 'source': 'manual', 'cefrLevel': 'B1'}


def target_v2(kind):
    sources = {
        'packEntry': {'packId': 'synthetic-pack', 'packVersion': '1.0.0',
                      'packageSha256': 'a' * 64, 'entryCode': 'harbor', 'entrySha256': 'b' * 64},
        'aiOutput': {'sessionId': 'synthetic-native-session', 'acceptedPlanId': 'native-plan-v1:' + 'c' * 64,
                     'contentKind': 'sentence', 'modelVersion': 'synthetic-model/revision7',
                     'cached': True, 'origin': 'fallback'},
        'tutorReply': {'replyId': 'synthetic-reply', 'modelVersion': 'synthetic-tutor/7',
                       'generatedAtUtcMs': 1793520000000},
        'readingDocument': {'documentId': 'synthetic-document', 'documentRevision': 3,
                            'documentSha256': 'd' * 64, 'identityKind': 'supplied'},
    }
    text = 'Synthetic selected content only.'
    return {'version': 'content-report-target-v2', 'kind': kind, 'text': text,
            'textSha256': digest(text), 'isExcerpt': False, 'source': sources[kind]}


def submission(*, report_id='word-report:synthetic-1', target=None, **changes):
    snapshot = wire_json(word_snapshot() if target is None else target)
    report = {'schemaVersion': 1, 'reportId': report_id, 'snapshotJson': snapshot,
              'snapshotSha256': digest(snapshot), 'reason': 'incorrectMeaning', 'comment': None,
              'queuedAtUtcMs': 1793520000000}
    report.update(changes)
    return envelope(report)


def envelope(report):
    raw = wire_json(report)
    return {'schemaVersion': 1, 'reportJson': raw, 'reportSha256': digest(raw)}


class Documents:
    def __init__(self):
        self.values = {}
        self.lock = RLock()
        self.before_retry = None
        self.lose_next_ack = False
        self.reads = []

    def transact(self, paths, update):
        with self.lock:
            self.reads.extend(paths)
            writes, result = update({path: copy.deepcopy(self.values.get(path)) for path in paths})
            if self.before_retry is not None:
                change = self.before_retry
                self.before_retry = None
                change(self.values)
                writes, result = update({path: copy.deepcopy(self.values.get(path)) for path in paths})
            assert writes.keys() <= set(paths)
            self.values.update(copy.deepcopy(writes))
            if self.lose_next_ack and writes:
                self.lose_next_ack = False
                raise RuntimeError('synthetic lost commit acknowledgement')
            return copy.deepcopy(result)

    def list_cases(self, *, uid, after, limit):
        rows = []
        for path, value in sorted(self.values.items()):
            if not path.startswith('content_reports/'):
                continue
            key = path.split('/')[1]
            if after is not None and key <= after:
                continue
            if uid is not None and value['firebaseUid'] != uid:
                continue
            if uid is None and value['status'] != 'received':
                continue
            rows.append((key, copy.deepcopy(value)))
        return rows[:limit]


class Tokens:
    def verify(self, token):
        if token not in {'reporter', 'other', 'moderator', 'anonymous', 'uncertain'}:
            raise HTTPException(401, detail={'code': 'UNAUTHENTICATED'})
        uid = {'other': OTHER, 'moderator': MODERATOR}.get(token, UID)
        return AuthenticatedUser(uid=uid, is_anonymous=None if token == 'uncertain' else token == 'anonymous')


class Harness:
    def __init__(self, *, enabled=True, moderators=frozenset({MODERATOR}), budget=10):
        self.now = datetime(2026, 11, 1, 12, 0, 0, 123000, tzinfo=UTC)
        self.documents = Documents()
        self.service = ContentReportService(
            store=FirestoreContentReportStore(self.documents), now_utc=lambda: self.now,
            moderator_uids=moderators, submissions_per_minute=budget,
        )
        self.client = TestClient(create_app(
            content_service=FakeContentService(), token_verifier=Tokens(),
            settings=Settings(_env_file=None, content_reports_enabled=enabled),
            content_report_service=self.service,
        ))

    @staticmethod
    def headers(token='reporter'):
        return {'Authorization': 'Bearer ' + token}

    def post(self, value=None, token='reporter'):
        return self.client.post('/v1/content-reports', json=value or submission(), headers=self.headers(token))

    def decision(self, key, value=None, token='moderator'):
        request = {'schemaVersion': 1, 'decisionId': 'synthetic-decision-1',
                   'reportSha256': submission()['reportSha256'], 'expectedRevision': 1,
                   'status': 'resolved', 'publicNote': 'Synthetic case disposition; no content publication.'}
        request.update(value or {})
        return self.client.post('/v1/content-report-moderation/' + key + '/decision',
                                json=request, headers=self.headers(token))
