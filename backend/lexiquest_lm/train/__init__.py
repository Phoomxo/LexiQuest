"""Phase B: fine-tuning pipeline for LexiQuest-LM.

Modules:
- tokenize.py: build a tokenised, attention-masked dataset from the
  instruction JSONL produced by Phase A. Runs in dry-run mode without GPU.
- lora_finetune.py: LoRA fine-tune Qwen2.5-0.5B on the tokenised dataset.
  ``--dry-run`` validates the full training loop on 8 examples without
  loading the real model; ``--train`` runs the real training on the GPU.
- evaluate.py: compute perplexity on the test split + generate sample
  completions for qualitative review.

All three honour ``--dry-run`` so the pipeline can be smoke-tested on a
machine without torch/CUDA installed (the heavy imports are deferred to the
moment they are actually needed).
"""
