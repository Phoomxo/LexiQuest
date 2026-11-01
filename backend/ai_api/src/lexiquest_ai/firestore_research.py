from __future__ import annotations

from collections.abc import Callable

from firebase_admin import firestore as firebase_firestore
from google.cloud import firestore as google_firestore

from lexiquest_ai.research import ResearchError, code, digest


class FirestoreResearchStore:
    def __init__(self, documents: object):
        self.documents = documents

    @classmethod
    def production(cls):
        return cls(FirestoreResearchDocuments(firebase_firestore.client()))

    def transact(self, firebase_uid: str, upload_id: str | None, update: Callable):
        code(firebase_uid)
        enrollment = 'research_enrollments/' + firebase_uid
        consent = 'research_consents/' + firebase_uid
        fence = 'account_deletion_operations/' + firebase_uid
        archive = None if upload_id is None else 'research_study_archives/' + digest(upload_id)
        paths = (enrollment, consent, fence) + (() if archive is None else (archive,))
        def apply(current):
            if current[fence] is not None:
                raise ResearchError('deletion_pending')
            consent_write, archive_write, result = update(current[enrollment], current[consent], None if archive is None else current[archive])
            writes = {}
            if consent_write is not None:
                if consent_write.get('firebaseUid') != firebase_uid:
                    raise ResearchError('owner_mismatch')
                writes[consent] = consent_write
            if archive_write is not None:
                if archive is None or archive_write.get('firebaseUid') != firebase_uid:
                    raise ResearchError('owner_mismatch')
                writes[archive] = archive_write
            return writes, result
        return self.documents.transact(paths, apply)


class FirestoreResearchDocuments:
    def __init__(self, client):
        self.client = client

    def transact(self, paths: tuple[str, ...], update: Callable):
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
                raise ResearchError('authority_unavailable')
            for path, value in writes.items():
                current_transaction.set(refs[path], value)
            return result
        return run(transaction)
