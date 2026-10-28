"""LexiQuest-LM: domain-specific vocabulary teaching small LM.

Package marker. Submodules under ``lexiquest_lm.dataset`` implement the data
collection pipeline; ``lexiquest_lm.train`` implements fine-tuning; and the
``deploy/`` directory contains the HuggingFace Spaces serving app.
"""

__all__ = ["__version__"]

__version__ = "0.1.0"
