# LexiQuest-LM: Domain-Specific Vocabulary Teaching LLM

A small, fine-tuned language model specialized for LexiQuest's vocabulary
teaching tasks (example sentences, micro-stories, word explanations). This is
the research contribution of the thesis: instead of depending on a third-party
LLM API, LexiQuest ships its own compact model trained on a curated
vocabulary-teaching dataset.

## Why a custom model?

- **Cost ceiling**: free forever, no per-request billing, no quota walls.
- **Resilience**: no third-party outage can break the thesis demonstration.
- **Research contribution**: a domain-specific small LM is a genuine
  contribution, not "just calling an API".
- **Privacy**: no user text ever leaves a server we control.

## Pipeline

```
dataset/                      # Phase A: data collection
  collect_cefr_words.py       #   seed words from the app's CEFR bank
  expand_wordlist.py          #   expand with public CEFR/Oxford lists
  enrich_dictionary.py        #   enrich via Datamuse + dictionaryapi.dev
  generate_synthetic.py       #   Gemini-generated teaching examples
  fetch_huggingface.py        #   public datasets (CEFR-J, Tatoeba)
  merge_and_format.py         #   -> instruction-tuning JSONL

train/                        # Phase B: fine-tuning
  tokenize.py                 #   tokenizer setup for Qwen2.5
  lora_finetune.py            #   LoRA fine-tune on RTX 3050 (8GB VRAM)
  evaluate.py                 #   perplexity + sample generation

deploy/                       # Phase C: serving
  hf_space/                   #   HuggingFace Spaces FastAPI app
  convert_gguf.py             #   (optional) quantize for cheaper hosting
```

## Target model

- **Base**: `Qwen/Qwen2.5-0.5B` (fits RTX 3050 VRAM with LoRA, supports Thai/English)
- **Method**: LoRA (rank 8-16), 2-4 hours on a single RTX 3050
- **Tasks**: sentence / story / explanation generation, keyed by CEFR level

## Running

Each script is self-contained and idempotent. From the repository root:

```powershell
uv sync --project backend/lexiquest_lm --all-groups
uv run --project backend/lexiquest_lm python backend/lexiquest_lm/dataset/collect_cefr_words.py
```

See `pyproject.toml` for the (small) Python dependency set. Heavy ML
dependencies (`torch`, `transformers`, `peft`, `datasets`) live in the `train`
extra so dataset collection runs without them.
