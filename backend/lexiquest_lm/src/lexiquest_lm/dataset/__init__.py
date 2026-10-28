"""Dataset collection pipeline for LexiQuest-LM.

Each collector is a small, idempotent script that writes a JSONL file to
``backend/lexiquest_lm/data/raw/``. ``merge_and_format.py`` later combines
all raw files into a single instruction-tuning JSONL.

The split into many small collectors (rather than one big script) is deliberate:

* Each can be re-run independently when a source changes (e.g. the app's CEFR
  bank gains new words).
* Failures are isolated: a Datamuse outage does not block synthetic generation.
* The dataset provenance is auditable: each row in the final JSONL can be
  traced back to the script that produced it.
"""
