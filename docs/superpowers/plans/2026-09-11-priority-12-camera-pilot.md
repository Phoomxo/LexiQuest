# Priority 12 bounded camera fine-tuning pilot

User authorizes internet-sourced data. Work locally without cloud compute,
shipping new model assets, collecting research data or changing production gates.

Use Open Images metadata with per-image CC BY 2.0 attribution, strict object
box filtering and one crop per source image. Pilot scope: book, coffee cup,
bottle and chair; initially 30 training, 10 validation and 10 held-out samples
per class. Before any training or evaluation, the strict validation selection
yielded only 15 eligible book images. Revised book allocation: 10 train, 5
validation, 10 test; other classes retain 30/10/10. Annotation filters unchanged.
Official validation supplies pilot train/validation; official test stays held
out. These choices are fixed before running model evaluation.

Compare the app's pinned quantized MobileNet baseline with a MobileNet transfer
candidate. Train its classifier head, then fine-tune only the last convolutional
layers with batch normalization frozen. Choose by validation loss, never test
accuracy. Preserve model hashes, manifest hash, dependencies and per-image paired
predictions. This is an object-crop four-class pilot; no claim of broad full-frame
or vivo accuracy follows from it. Candidate stays outside shipped assets pending
open-set, actual-device, latency, label-contract and rollout checks.

Implementation: `tools/prepare_openimages_pilot.py`, `tools/camera_accuracy.py`,
`tools/test_camera_accuracy.py`, then `tools/train_camera_pilot.py`.
Evaluation validation tests reject duplicate samples, missing predictions and
scene leakage; four synthetic unit tests pass. Preserve raw attribution and
model license references in the local evidence directory.

Pilot trained and exported locally. App-runtime compatibility testing exposed
three real assumptions: topK fixed at ten, background always class zero, and
float32 probabilities decoded as quantized bytes. Corrected topK to class-count
bound, added nullable backgroundClassIndex (default zero preserves baseline),
and decode float32 per tensor element with non-finite rejection. Added a 1,612
byte synthetic native fixture with its reproducible generator and permanent
regression test; no real images or learned weights are shipped by that fixture.

All 62 selected model/runtime/scanner checks passed, followed by the synthetic
float regression. Real host CPU/XNNPACK loads of the candidate pass. Conversion
parity: 35/35 validation top-1 predictions match. Actual Dart preprocessing on
the 40 held-out full frames yields 36 correct candidate labels. Dataset is only
four known classes; default app model remains unchanged and release disabled.
