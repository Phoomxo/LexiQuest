# R15.7 / CAM-03 — retained baseline

## Source and decision
Local accepted: **insufficient-coverage / retain-baseline**.
Worktree `C:/Users/Phet/.codex/worktrees/1296/LexiQuest`, branch
`feature/r15-model-continuation`, base `48c330e71be73965f9bb2504fbb87e699a76ebc4`.
Resolve the commit accompanying this report for the accepted R15.7 SHA.
No fresh training/export, device operation, upload or rollout.
Manifest/classifier source unchanged; baseline artifact SHA256:
`d3949e8a3556c79739cb675e0be7476503bcce76938031c6a1048e13e0cb7d8b`.
Manifest file SHA256:
`4f2c764194e99426aa91f3eaf7b06bb8a404caa6f7243a84d1c32297cbc6d89d`.
No learning/reward, owner storage, research or8/44 changes.

## Inventory
Read-only source:
`C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/priority-12-openimages-20260911/manifest.json`.
SHA256 `7f451af57c765663dd6a25fcbead663b01a616c4a063350348fd752b35ab6be0`.
All175 image bytes match metadata hashes. Audit found no cross-split group/content
hashes or missing per-image source/license URL. This verifies recorded provenance,
not independent legal validity or perceptual near-duplicates. No images imported.

Derived inventory: train100 / legacy validation35 / regression40 / fresh test0.
Previously analyzed test40 become regression; all historical rows `fresh=false`.
Fresh natural-frame qualifying counts are zero in both validation/test for all
known classes and unknown. Minimum remains30/known class and200/unknown per split.
No new dataset fetched or minimum relaxed. Untracked evidence under
`build/verification/r15-model/`: inventory.log, legacy-inventory.json, decision.json.
Derived dataset fingerprint:
`8143c81d26c54b5e3e3a2ccd3b7e62960113c3d3d7ae87161e545857f6a14579`.

Reproduce: load pinned source JSON; check each image resolves beneath dataset
root and bytes match sha256; change test split to regression and set every row
fresh=false; add original_manifest_sha256 and verified_image_hashes=175; write
new JSON. Run audit below with a new output filename. Original data stays untouched.

## Acceptance coverage and limitations
- A-MODEL-01: audit rejects missing source/license/hash, duplicate IDs and
  group/content leakage across all splits including regression. Trainer preflight
  runs before output creation, TensorFlow imports or weight downloads.
- A-MODEL-02: fixed coverage counts only explicitly fresh/natural full frames,
  independent groups/content. Crops/UI/legacy rows cannot inflate counts.
- A-MODEL-03: softmax4 threshold<=0.25 reports invalid-unknown-gate;0.15 cannot
  reject unknowns mathematically.
- A-MODEL-04: validation-only supplied predictions/config freeze model, dataset,
  preprocessing and environment pins. Test rejects changed pins and reports
  numerators/denominators, Wilson95%, per-class correct acceptance, known rejection
  and unknown false acceptance. CLI outputs are exclusive; persistent .test-opened
  receipt precedes test input read. Failed openings remain consumed. This is local
  workflow enforcement, not tamper-proof attestation.
- A-MODEL-05: exact paired image IDs/preprocessing required; duplicate independent
  observations, missing labels and nonfinite confidence rejected. Baseline labels
  must already represent canonical mapping. Evaluator consumes supplied predictions;
  it does not independently run the models.
- A-MODEL-06: always retain baseline without physical resource evidence and because
  four classes cannot replace broad vocabulary. Descriptive quality pass is not ship
  approval. Real fresh scores/resource acceptance were not available this package.

Legacy compare() remains descriptive. CLI defaults to strict audit. Legacy crop
trainer is deliberately fail-closed: required unknown scenes are unsupported.
A future training adapter needs protocol revision; do not silently drop unknowns.
Preparation/export scripts and shipped assets unchanged.

Input: samples/config plus validation_predictions or test_predictions. Samples:
id/group/split/truth/sha256/source_url/attribution.License, fresh/natural booleans,
view=full-frame; labels book/bottle/chair/cup/unknown. Config: baseline_model and
candidate_model SHA256, preprocess, environment, threshold, output_classes=4,
score_type=softmax. Predictions: id, baseline mapped label, candidate known label,
maximum confidence, preprocess. Select configuration from validation only; freeze
input rejects test_predictions. Curator declarations do not prove freshness,
naturalness or label/model authenticity. Synthetic fixtures are not accuracy data.

## Verification
Python3.12.14: `C:/Users/Phet/.cache/lq12-20260911/Scripts/python.exe`.

```powershell
& C:/Users/Phet/.cache/lq12-20260911/Scripts/python.exe -m unittest discover -s tools -p test_camera_accuracy.py
& C:/Users/Phet/.cache/lq12-20260911/Scripts/python.exe tools/camera_accuracy.py build/verification/r15-model/legacy-inventory.json build/verification/r15-model/decision.json
# Future fresh-data workflow; exercised here only with synthetic CLI fixtures:
# python tools/camera_accuracy.py validation.json freeze.json --mode freeze
# python tools/camera_accuracy.py test.json report.json --mode evaluate --freeze freeze.json
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Runtime -TestTargets @('test/features/device_model/model_manifest_test.dart','test/features/device_model/litert_image_classifier_test.dart')
& ./tool/cli/prepare-field-model.ps1
& ./tool/cli/verify-scope.ps1 -Level Targeted -Area Runtime -TestTargets @('test/features/device_model/litert_image_classifier_test.dart')
git diff --check
```

Python logs in r15-model: red.log11cases/7missing-API errors; green1.log11/11;
red2.log13cases/2expected failures (CLI audit/duplicate observations);
green2.log13/13; green3.log14/14 (adds CLI single-opening coverage);
red3.log15cases/1expected training output-side-effect failure;
final-python.log15/15 exit0, test0.720s / command0.923s. Intermediate runs required
by changed source/new regressions. Final fingerprint (SHA256 of sorted JSON
path-to-file-SHA256 mapping, source-pins.json):
`46d2e897b370574bbcccabdcc18d874212c5c5a90f33d4403ae0b8bd193f0cbb`.

Flutter initial command17.115s: manifest2/2 pass, classifier2 fail due to missing
fixture. Inspected repository preparer then downloaded size/hash-pinned baseline
(fixture.log,2.52s). Reran only failed classifier target:2/2 exit0,5.671s.
All4 distinct compatibility tests passed across two runs; manifest not rerun.
Runtime fingerprint `887478d9a6bd1006f1ceaa157f95bde1e56d32c2817a2b3c2aab4bccaf59c692`.
JSON/logs under build/verification/48c330e71be73965f9bb2504fbb87e699a76ebc4/:
2080a52ad4a0-887478d9a6bd/ first; a584f6fafe9e-887478d9a6bd/ recovery.

Final diff self-reviewed against A-MODEL; no subagents. git diff --check clean.
Generated registrants EOL-only/no content diff excluded. No test/build remains.
Token/credit usage unavailable; no cost-saving claim. No physical unknown scenes,
30-cycle resources, three-process device timing, TalkBack/human or release
acceptance claimed. R15.7 closure is the approved retained-baseline outcome.
Next: create R15.8 in a separate task from this accepted commit.
