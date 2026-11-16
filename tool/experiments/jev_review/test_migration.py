import json, sqlite3, tempfile, unittest
from pathlib import Path
from contextlib import closing
from guard import Guard, Halt

class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'old.sqlite'
        with closing(sqlite3.connect(self.path)) as db, db:
            db.executescript('CREATE TABLE policy (tranche TEXT, expires REAL, paused TEXT); CREATE TABLE calls (hash TEXT PRIMARY KEY,reservation TEXT,cost TEXT,state TEXT,receipt TEXT,result TEXT);')
            db.execute('INSERT INTO policy VALUES (?,?,?)', ('original',2000,None))
            for key,state,cost in [('synthetic','settled','0'),('review','settled','0'),('unresolved','pending',None)]:
                db.execute('INSERT INTO calls VALUES (?,?,?,?,?,?)',(key,'0.14',cost,state,'receipt-'+key,'result-'+key))
        self.guard = Guard(self.path)
        self.mapping = {'synthetic':'synthetic','review':'review','unresolved':'routing'}

    def original(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            return (db.execute('SELECT * FROM policy').fetchall(), db.execute('SELECT hash,reservation,cost,state,receipt,result FROM calls ORDER BY hash').fetchall())

    def test_migration_preserves_every_original_field_and_is_idempotent(self):
        before=self.original()
        self.assertTrue(callable(getattr(self.guard,'migrate',None)), 'explicit migration required')
        self.guard.migrate(self.mapping)
        self.assertEqual(self.original(),before)
        self.guard.migrate(self.mapping)
        self.assertEqual(self.original(),before)
        with closing(sqlite3.connect(self.path)) as db, db:
            self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],2)
            self.assertEqual(db.execute('SELECT purpose,count(*) FROM call_context GROUP BY purpose ORDER BY purpose').fetchall(), [('review',1),('routing',1),('synthetic',1)])
        self.assertEqual(self.guard.status()['pending'],1)

    def test_incomplete_or_unknown_classification_rolls_back(self):
        self.assertTrue(callable(getattr(self.guard,'migrate',None)), 'explicit migration required')
        for mapping in [{},self.mapping|{'review':'arbitrary'}]:
            with self.assertRaises(Halt): self.guard.migrate(mapping)
            with closing(sqlite3.connect(self.path)) as db, db:
                self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],0)

if __name__ == '__main__': unittest.main()
