import copy
from types import SimpleNamespace

import pytest

import lexiquest_ai.firestore_research as adapter
from lexiquest_ai.firestore_research import FirestoreResearchDocuments, FirestoreResearchStore
from lexiquest_ai.research import ResearchError

from research_support import Harness, UID


def test_real_sdk_adapter_reads_all_authority_and_fence_before_writes_and_replays_commit(monkeypatch):
    h = Harness()
    values = copy.deepcopy(h.documents.values)
    all_reads = []
    fail_ack = [False]
    class Ref:
        def __init__(self, path):
            self.path = path
        def get(self, *, transaction):
            assert not transaction.writes
            all_reads.append(self.path)
            value = copy.deepcopy(values.get(self.path))
            return SimpleNamespace(exists=value is not None, to_dict=lambda: value)
    class Transaction:
        def __init__(self):
            self.writes = {}
        def set(self, ref, value):
            self.writes[ref.path] = value
    def transactional(function):
        def run(transaction):
            result = function(transaction)
            values.update(copy.deepcopy(transaction.writes))
            if fail_ack[0]:
                fail_ack[0] = False
                raise RuntimeError('synthetic lost commit acknowledgement')
            return result
        return run
    monkeypatch.setattr(adapter.google_firestore, 'transactional', transactional)
    documents = FirestoreResearchDocuments(SimpleNamespace(document=Ref, transaction=Transaction))
    h.service.store = FirestoreResearchStore(documents)
    h.accept()
    request = h.upload(h.archive(complete=True))
    fail_ack[0] = True
    with pytest.raises(RuntimeError, match='lost commit'):
        h.service.upload(UID, request)
    after_lost_ack = copy.deepcopy(values)
    receipt = h.service.upload(UID, request)
    assert values == after_lost_ack
    assert receipt['uploadId'] in next(path for path in values if path.startswith('research_study_archives/'))
    assert 'account_deletion_operations/' + UID in all_reads
    assert len([path for path in values if path.startswith('research_study_archives/')]) == 1
    before = copy.deepcopy(values)
    with pytest.raises(ResearchError):
        documents.transact(('research_enrollments/' + UID,), lambda _: ({'outside/forbidden': {}}, None))
    assert values == before


def test_store_transaction_cannot_write_another_uid_or_turn_enrollment_into_client_authority():
    h = Harness()
    before = copy.deepcopy(h.documents.values)
    with pytest.raises(ResearchError, match='owner_mismatch'):
        h.service.store.transact(UID, None, lambda *_: ({'firebaseUid': 'foreign'}, None, None))
    assert h.documents.values == before
    h.service.context(UID)
    assert h.documents.values == before


@pytest.mark.parametrize('change', ['revocation', 'withdrawal', 'deletion'])
def test_firestore_retries_reauthorize_consent_and_revocation_before_upload_commit(monkeypatch, change):
    h = Harness()
    h.accept()
    values = copy.deepcopy(h.documents.values)
    class Ref:
        def __init__(self, path):
            self.path = path
        def get(self, *, transaction):
            assert not transaction.writes
            value = copy.deepcopy(values.get(self.path))
            return SimpleNamespace(exists=value is not None, to_dict=lambda: value)
    class Transaction:
        def __init__(self):
            self.writes = {}
        def set(self, ref, value):
            self.writes[ref.path] = value
    def transactional(function):
        def run(transaction):
            function(transaction)
            if change == 'revocation':
                values['research_enrollments/' + UID]['active'] = False
            elif change == 'deletion':
                values['account_deletion_operations/' + UID] = {'synthetic': True}
            else:
                for decision in values['research_consents/' + UID]['decisions'].values():
                    decision.update(state='withdrawn', withdrawnAtUtc='2026-11-01T12:00:00.000Z', revision=2)
            return function(Transaction())
        return run
    monkeypatch.setattr(adapter.google_firestore, 'transactional', transactional)
    h.service.store = FirestoreResearchStore(FirestoreResearchDocuments(SimpleNamespace(document=Ref, transaction=Transaction)))
    with pytest.raises(ResearchError):
        h.service.upload(UID, h.upload())
    assert not any(path.startswith('research_study_archives/') for path in values)
