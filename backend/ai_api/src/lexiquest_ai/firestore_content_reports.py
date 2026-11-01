from __future__ import annotations

from firebase_admin import firestore as firebase_firestore
from google.cloud import firestore as google_firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from lexiquest_ai.content_reports import ContentReportError, digest, require_case_key, require_uid


class FirestoreContentReportDocuments:
    def __init__(self, client):
        self.client = client

    def transact(self, paths, update):
        refs = {path: self.client.document(path) for path in paths}
        transaction = self.client.transaction()

        @google_firestore.transactional
        def run(current_transaction):
            current = {}
            for path, ref in refs.items():
                snapshot = ref.get(transaction=current_transaction)
                current[path] = snapshot.to_dict() if snapshot.exists else None
            writes, result = update(current)
            if not writes.keys() <= refs.keys():
                raise ContentReportError('unavailable')
            for path, value in writes.items():
                current_transaction.set(refs[path], value)
            return result

        return run(transaction)

    def list_cases(self, *, uid, after, limit):
        query = self.client.collection('content_reports')
        if uid is not None:
            query = query.where(filter=FieldFilter('firebaseUid', '==', uid))
        else:
            query = query.where(filter=FieldFilter('status', '==', 'received'))
        query = query.order_by('__name__')
        if after is not None:
            query = query.start_after({'__name__': self.client.document('content_reports/' + after)})
        return [(snapshot.id, snapshot.to_dict()) for snapshot in query.limit(limit).stream()]


class FirestoreContentReportStore:
    def __init__(self, documents):
        self.documents = documents

    @classmethod
    def production(cls):
        return cls(FirestoreContentReportDocuments(firebase_firestore.client()))

    def transact(self, uid, key, update, *, budget=False, actor_uid=None):
        require_uid(uid)
        require_case_key(key)
        case = 'content_reports/' + key
        fences = ('account_deletion_operations/' + uid,)
        if actor_uid is not None:
            require_uid(actor_uid)
            if actor_uid != uid:
                fences += ('account_deletion_operations/' + actor_uid,)
        counter = 'content_report_limits/' + digest(uid)
        paths = (case,) + fences + ((counter,) if budget else ())

        def apply(current):
            if any(current[fence] is not None for fence in fences):
                raise ContentReportError('deletion_pending')
            stored = current[case]
            if stored is not None and stored.get('firebaseUid') != uid:
                raise ContentReportError('unavailable')
            report_write, budget_write, result = update(stored, current[counter] if budget else None)
            writes = {}
            if report_write is not None:
                if report_write.get('firebaseUid') != uid:
                    raise ContentReportError('unavailable')
                writes[case] = report_write
            if budget_write is not None:
                if not budget or budget_write.get('firebaseUid') != uid:
                    raise ContentReportError('unavailable')
                writes[counter] = budget_write
            return writes, result

        return self.documents.transact(paths, apply)

    def get_case(self, key):
        require_case_key(key)
        path = 'content_reports/' + key
        return self.documents.transact((path,), lambda current: ({}, current[path]))

    def require_active(self, uid):
        require_uid(uid)
        fence = 'account_deletion_operations/' + uid

        def check(current):
            if current[fence] is not None:
                raise ContentReportError('deletion_pending')
            return {}, None

        self.documents.transact((fence,), check)

    def list_cases(self, *, uid, after, limit):
        if uid is not None:
            self.require_active(uid)
            result = self.documents.list_cases(uid=uid, after=after, limit=limit)
            self.require_active(uid)
            return result
        return self.documents.list_cases(uid=None, after=after, limit=limit)
