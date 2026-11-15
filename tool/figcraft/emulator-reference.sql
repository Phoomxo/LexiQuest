-- Synthetic screenshot state for the fresh, task-installed emulator app only.
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;
CREATE TEMP TABLE reference_guard (ok INTEGER NOT NULL CHECK (ok = 1));
INSERT INTO reference_guard
SELECT CASE WHEN
  (SELECT COUNT(*) FROM local_owners WHERE is_active = 1) = 1
  AND NOT EXISTS (SELECT 1 FROM vocabulary_categories WHERE id NOT IN ('synthetic:figcraft:travel', 'synthetic:figcraft:kitchen'))
  AND NOT EXISTS (SELECT 1 FROM vocabulary_words WHERE source != 'synthetic:figcraft-reference')
THEN 1 ELSE 0 END;

INSERT OR IGNORE INTO vocabulary_categories
  (id, owner_id, name, normalized_name, sort_order, created_at_utc_ms, updated_at_utc_ms)
SELECT 'synthetic:figcraft:travel', id, 'การเดินทาง', 'การเดินทาง', 0, 1, 1 FROM local_owners WHERE is_active = 1;
INSERT OR IGNORE INTO vocabulary_categories
  (id, owner_id, name, normalized_name, sort_order, created_at_utc_ms, updated_at_utc_ms)
SELECT 'synthetic:figcraft:kitchen', id, 'ของใช้ในครัว', 'ของใช้ในครัว', 1, 1, 1 FROM local_owners WHERE is_active = 1;

INSERT OR IGNORE INTO vocabulary_words
  (id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, part_of_speech, source, created_at_utc_ms, updated_at_utc_ms)
SELECT 'synthetic:figcraft:station', id, 'synthetic:figcraft:travel', 'station', 'station', 'สถานี', 'สถานี', 'noun', 'synthetic:figcraft-reference', 1, 1 FROM local_owners WHERE is_active = 1;
INSERT OR IGNORE INTO vocabulary_words
  (id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, part_of_speech, source, created_at_utc_ms, updated_at_utc_ms)
SELECT 'synthetic:figcraft:platform', id, 'synthetic:figcraft:travel', 'platform', 'platform', 'ชานชาลา', 'ชานชาลา', 'noun', 'synthetic:figcraft-reference', 1, 1 FROM local_owners WHERE is_active = 1;
INSERT OR IGNORE INTO vocabulary_words
  (id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, part_of_speech, source, created_at_utc_ms, updated_at_utc_ms)
SELECT 'synthetic:figcraft:ticket', id, 'synthetic:figcraft:travel', 'ticket', 'ticket', 'ตั๋ว', 'ตั๋ว', 'noun', 'synthetic:figcraft-reference', 1, 1 FROM local_owners WHERE is_active = 1;
INSERT OR IGNORE INTO srs_states (id, owner_id, word_id, due_at_utc_ms, algorithm_version)
SELECT 'srs:' || id || ':synthetic:figcraft:platform', id, 'synthetic:figcraft:platform', 1, 1 FROM local_owners WHERE is_active = 1;

INSERT INTO reference_guard SELECT CASE WHEN
  (SELECT COUNT(*) FROM vocabulary_categories) = 2
  AND (SELECT COUNT(*) FROM vocabulary_words) = 3
  AND (SELECT COUNT(*) FROM srs_states WHERE due_at_utc_ms <= 1) = 1
THEN 1 ELSE 0 END;
COMMIT;
SELECT 'FIGCRAFT_REFERENCE_READY';
SELECT c.name, COUNT(w.id) FROM vocabulary_categories c LEFT JOIN vocabulary_words w ON w.category_id = c.id GROUP BY c.id ORDER BY c.sort_order;
SELECT w.spelling FROM srs_states s INNER JOIN vocabulary_words w ON w.id = s.word_id WHERE s.due_at_utc_ms = 1;
.quit
