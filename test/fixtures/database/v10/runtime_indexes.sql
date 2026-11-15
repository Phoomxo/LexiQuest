-- Exact v10 AppDatabase.beforeOpen indexes, source e432fa05.
CREATE INDEX IF NOT EXISTS idx_learning_sessions_owner_started ON learning_sessions(owner_id, started_at_utc_ms);
CREATE INDEX IF NOT EXISTS idx_learning_attempts_owner_word_time ON answer_attempts(owner_id, word_id, occurred_at_utc_ms);
CREATE INDEX IF NOT EXISTS idx_learning_srs_owner_due ON srs_states(owner_id, due_at_utc_ms);
CREATE INDEX IF NOT EXISTS idx_learning_reading_owner_document ON reading_progress_entries(owner_id, document_id, document_revision);
CREATE INDEX IF NOT EXISTS idx_events_v2_owner_occurred ON events_v2(owner_id, occurred_at_utc);
