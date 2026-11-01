import copy
from types import SimpleNamespace

import pytest

import lexiquest_ai.firestore_content_reports as adapter
from lexiquest_ai.content_reports import ContentReportError, case_key, digest
from lexiquest_ai.firestore_content_reports import FirestoreContentReportDocuments, FirestoreContentReportStore

from content_report_support import Harness, MODERATOR, UID, submission


def sdk_documents(monkeypatch, values, *, retry=None, lost_ack=None):
    reads = []

    class Ref:
        def __init__(self, path):
            self.path = path

        def get(self, *, transaction):
            assert not transaction.writes
            reads.append(self.path)
            value = copy.deepcopy(values.get(self.path))
            return SimpleNamespace(exists=value is not None, to_dict=lambda: value)

    class Transaction:
        def __init__(self):
            self.writes = {}

        def set(self, ref, value):
            self.writes[ref.path] = copy.deepcopy(value)

    def transactional(function):
        def run(transaction):
            result = function(transaction)
            if retry and retry[0] is not None:
                change, retry[0] = retry[0], None
                change(values)
                transaction = Transaction()
                result = function(transaction)
            values.update(copy.deepcopy(transaction.writes))
            if lost_ack and lost_ack[0] and transaction.writes:
                lost_ack[0] = False
                raise RuntimeError('synthetic SDK lost acknowledgement')
            return result
        return run

    monkeypatch.setattr(adapter.google_firestore, 'transactional', transactional)
    return FirestoreContentReportDocuments(SimpleNamespace(document=Ref, transaction=Transaction)), reads


def test_real_sdk_adapter_reads_case_budget_and_deletion_fence_before_writes_and_reconciles_lost_ack(monkeypatch):
    h = Harness()
    values = {}
    lost = [True]
    documents, reads = sdk_documents(monkeypatch, values, lost_ack=lost)
    h.service.store = FirestoreContentReportStore(documents)
    with pytest.raises(RuntimeError, match='lost acknowledgement'):
        h.service.submit(UID, submission())
    committed = copy.deepcopy(values)
    result = h.service.submit(UID, submission())
    assert result['receipt']['reportSha256'] == submission()['reportSha256']
    assert values == committed
    assert set(reads) == {'content_reports/' + case_key(UID, 'word-report:synthetic-1'),
                          'content_report_limits/' + digest(UID), 'account_deletion_operations/' + UID}
    assert len(values) == 2


def test_real_sdk_transaction_retry_rechecks_deletion_and_does_not_recreate_after_purge(monkeypatch):
    h = Harness()
    values = {}
    retry = [lambda state: state.update({'account_deletion_operations/' + UID: {'synthetic': True}})]
    documents, _ = sdk_documents(monkeypatch, values, retry=retry)
    h.service.store = FirestoreContentReportStore(documents)
    with pytest.raises(ContentReportError, match='deletion_pending'):
        h.service.submit(UID, submission())
    assert set(values) == {'account_deletion_operations/' + UID}


@pytest.mark.parametrize('deleting_uid', [UID, MODERATOR])
def test_sdk_moderation_retry_reads_both_uid_fences_in_same_transaction(monkeypatch, deleting_uid):
    h = Harness()
    assert h.post().status_code == 200
    key = case_key(UID, 'word-report:synthetic-1')
    case_path = 'content_reports/' + key
    subject_fence = 'account_deletion_operations/' + UID
    actor_fence = 'account_deletion_operations/' + MODERATOR
    values = copy.deepcopy(h.documents.values)
    before = copy.deepcopy(values[case_path])
    retry = [None]
    documents, reads = sdk_documents(monkeypatch, values, retry=retry)
    original = documents.transact
    armed = False

    def retry_the_decision(paths, update):
        nonlocal armed
        if not armed and {case_path, subject_fence} <= set(paths):
            armed = True
            retry[0] = lambda state: state.update({
                'account_deletion_operations/' + deleting_uid: {'synthetic': True},
            })
        return original(paths, update)

    documents.transact = retry_the_decision
    h.service.store = FirestoreContentReportStore(documents)
    response = h.decision(key)
    assert armed
    assert response.status_code == 409
    assert values[case_path] == before
    assert reads.count(case_path) == 3
    assert reads.count(subject_fence) == 2
    assert reads.count(actor_fence) >= 2


def test_sdk_adapter_and_store_reject_cross_uid_or_outside_transaction_writes(monkeypatch):
    values = {}
    documents, _ = sdk_documents(monkeypatch, values)
    key = case_key(UID, 'word-report:synthetic-1')
    with pytest.raises(ContentReportError):
        documents.transact(('content_reports/' + key,), lambda _: ({'outside/forbidden': {}}, None))
    assert values == {}
    store = FirestoreContentReportStore(documents)
    with pytest.raises(ContentReportError):
        store.transact(UID, key, lambda *_: ({'firebaseUid': 'synthetic-foreign'}, None, None))
    assert values == {}
    with pytest.raises(ContentReportError):
        store.transact(UID, key, lambda *_: (None, {'firebaseUid': UID}, None))
    assert values == {}


@pytest.mark.parametrize('uid,expected_filter', [(UID, ('firebaseUid', UID)), (None, ('status', 'received'))])
def test_real_document_query_is_uid_or_pending_filtered_ordered_cursor_bounded(uid, expected_filter):
    calls = []
    key = 'a' * 64
    class Query:
        def where(self, *, filter):
            calls.append(('where', filter.field_path, filter.op_string, filter.value))
            return self

        def order_by(self, field):
            calls.append(('order', field))
            return self

        def start_after(self, value):
            calls.append(('after', value['__name__'].path))
            return self

        def limit(self, count):
            calls.append(('limit', count))
            return self

        def stream(self):
            calls.append(('stream',))
            return [SimpleNamespace(id='b' * 64, to_dict=lambda: {'synthetic': True})]

    def collection(name):
        assert name == 'content_reports'
        return Query()
    client = SimpleNamespace(collection=collection, document=lambda path: SimpleNamespace(path=path))
    rows = FirestoreContentReportDocuments(client).list_cases(uid=uid, after=key, limit=11)
    assert rows == [('b' * 64, {'synthetic': True})]
    assert calls == [('where', expected_filter[0], '==', expected_filter[1]),
                     ('order', '__name__'), ('after', 'content_reports/' + key),
                     ('limit', 11), ('stream',)]


def test_owner_listing_rechecks_deletion_after_query_before_returning_rows():
    h = Harness()
    h.service.submit(UID, submission())
    original = h.documents.list_cases
    def concurrent_deletion(**arguments):
        rows = original(**arguments)
        h.documents.values['account_deletion_operations/' + UID] = {'synthetic': True}
        return rows
    h.documents.list_cases = concurrent_deletion
    with pytest.raises(ContentReportError, match='deletion_pending'):
        h.service.page(UID)
