"""Train a real MobileNet transfer head on pinned, curated web development data.

No fresh test data, thresholds, production activation or remote writes. CPU
feature extraction is cached within this exclusive run; all epochs are logged.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import time

from camera_web_dataset import SCHEMA, digest, safe_path, write_json


def read_pinned(path, expected):
    if digest(path) != expected:
        raise ValueError('Pinned artifact checksum changed: ' + str(path))
    return json.loads(Path(path).read_text(encoding='utf-8'))


def training_rows(manifest):
    if manifest.get('schema') != SCHEMA:
        raise ValueError('Only accepted web development data can train this candidate')
    labels, rows = manifest['labels'], manifest['samples']
    if not rows or not labels or len(labels) != len(set(labels)):
        raise ValueError('Nonempty unique labels and data required')
    partitions = {s: [] for s in ['train', 'validation']}
    for i, row in enumerate(rows):
        if row['split'] not in partitions or row['label'] not in labels:
            raise ValueError('Fresh test/unknown/camera data cannot enter this training run')
        partitions[row['split']].append(i)
    if any(not p for p in partitions.values()):
        raise ValueError('Both development partitions are required')
    return partitions


def create_run(path):
    Path(path).mkdir(parents=True, exist_ok=False)


def pixels_for(row, root):
    import numpy as np
    from PIL import Image, ImageOps
    path = safe_path(root, row['path'])
    if digest(path) != row['sha256']:
        raise ValueError('Training image checksum changed')
    with Image.open(path) as image:
        image = ImageOps.exif_transpose(image).convert('RGB')
        w, h = image.size
        b = row['box']
        crop = image.crop((int(b[0]*w), int(b[1]*h), int(b[2]*w), int(b[3]*h)))
        return np.asarray(crop.resize((224, 224), Image.Resampling.BILINEAR))


def train(config_path, output):
    config = json.loads(config_path.read_text(encoding='utf-8'))
    acceptance = read_pinned(config['acceptancePath'], config['acceptanceSha256'])
    manifest_path = Path(config['manifestPath'])
    manifest = read_pinned(manifest_path, config['manifestSha256'])
    if acceptance['status'] != 'accepted' or acceptance['manifestSha256'] != config['manifestSha256']:
        raise ValueError('Accepted dataset receipt required')
    # Reuse the passed G5.3b curation gate; verify immutable artifacts on use.
    partitions = training_rows(manifest)
    if digest(config['backboneWeights']) != config['backboneSha256']:
        raise ValueError('Pretrained backbone checksum changed')
    if (type(config['seed']) is not int or config['seed'] < 0
            or type(config['epochs']) is not int or not 1 <= config['epochs'] <= 100
            or type(config['batchSize']) is not int or not 1 <= config['batchSize'] <= 64
            or not 0 < config['learningRate'] <= .1):
        raise ValueError('Invalid bounded training configuration')
    create_run(output)
    write_json(output / 'config.json', config)
    os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0'
    os.environ['TF_DETERMINISTIC_OPS'] = '1'
    os.environ['CUDA_VISIBLE_DEVICES'] = '-1'
    os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
    import numpy as np
    import tensorflow as tf
    import PIL
    tf.config.threading.set_inter_op_parallelism_threads(2)
    tf.config.threading.set_intra_op_parallelism_threads(4)
    tf.keras.utils.set_random_seed(config['seed'])
    tf.config.experimental.enable_op_determinism()
    write_json(output / 'environment.json', dict(python=platform.python_version(),
        tensorflow=tf.__version__, keras=tf.keras.__version__, numpy=np.__version__, pillow=PIL.__version__,
        platform=platform.platform(), devices=[str(x) for x in tf.config.list_physical_devices()],
        seed=config['seed'], deterministicOps=True, oneDnn=False, intraThreads=4, interThreads=2,
        sources={str(p): digest(p) for p in [Path(__file__), Path(__file__).with_name('camera_web_dataset.py')]}))
    started = time.monotonic()
    rows, labels = manifest['samples'], manifest['labels']
    pixels = np.stack([pixels_for(row, manifest_path.parent) for row in rows])
    targets = np.asarray([labels.index(r['label']) for r in rows])
    backbone = tf.keras.applications.MobileNet(input_shape=(224, 224, 3),
                    include_top=False, weights=None, pooling='avg')
    backbone.load_weights(config['backboneWeights'])
    backbone.trainable = False
    features = []
    batch = config['batchSize']
    for start in range(0, len(rows), batch):
        x = pixels[start:start+batch].astype(np.float32) / 127.5 - 1
        features.append(backbone(x, training=False).numpy())
        print(json.dumps(dict(stage='features', completed=min(start+batch, len(rows)), total=len(rows))), flush=True)
    features = np.concatenate(features)
    np.save(output / 'features.npy', features)
    head = tf.keras.Sequential([tf.keras.Input(shape=(1024,)),
                               tf.keras.layers.Dense(len(labels), activation='softmax')])
    np.savez(output / 'initial-head.npz', *head.get_weights())
    head.compile(optimizer=tf.keras.optimizers.Adam(config['learningRate']),
                 loss='sparse_categorical_crossentropy', metrics=['accuracy'])
    training, validation = np.asarray(partitions['train']), np.asarray(partitions['validation'])
    rng = np.random.default_rng(config['seed'])
    best_loss, best_epoch, history = float('inf'), None, []
    checkpoint = output / 'best-head.weights.h5'
    for epoch in range(config['epochs']):
        order = rng.permutation(training)
        head.reset_metrics()
        for start in range(0, len(order), batch):
            ix = order[start:start+batch]
            measured_train = head.train_on_batch(features[ix], targets[ix], return_dict=True)
        head.reset_metrics()
        measured_val = head.test_on_batch(features[validation], targets[validation], return_dict=True)
        record = dict(epoch=epoch+1, train={k: float(v) for k, v in measured_train.items()},
                      validation={k: float(v) for k, v in measured_val.items()})
        if record['validation']['loss'] < best_loss:
            best_loss, best_epoch = record['validation']['loss'], epoch+1
            head.save_weights(checkpoint)
        history.append(record)
        with (output / 'epochs.jsonl').open('a', encoding='utf-8', newline='\n') as log:
            log.write(json.dumps(record, allow_nan=False) + '\n')
        print(json.dumps(record, allow_nan=False), flush=True)
    head.load_weights(checkpoint)
    inputs = tf.keras.Input(shape=(224, 224, 3), dtype='float32')
    model = tf.keras.Model(inputs, head(backbone(inputs, training=False)))
    model.save(output / 'candidate.keras')
    predictions = head(features, training=False).numpy()
    measured = {}
    for split, indexes in partitions.items():
        actual = np.argmax(predictions[indexes], axis=1)
        truth = targets[indexes]
        measured[split] = dict(samples=len(indexes), correct=int(np.sum(actual == truth)),
                              accuracy=float(np.mean(actual == truth)),
                              loss=float(np.mean(-np.log(np.maximum(predictions[indexes, truth], 1e-12)))),
                              perClass={label: dict(n=int(np.sum(truth == i)),
                                  correct=int(np.sum((truth == i) & (actual == i)))) for i, label in enumerate(labels)})
    prediction_rows = [dict(id=row['id'], split=row['split'], truth=row['label'],
                           prediction=labels[int(np.argmax(predictions[i]))],
                           probabilities=[float(x) for x in predictions[i]]) for i, row in enumerate(rows)]
    write_json(output / 'predictions.json', prediction_rows)
    initial = np.load(output / 'initial-head.npz')
    delta = float(np.linalg.norm(initial['arr_0'] - head.get_weights()[0]))
    if not np.isfinite(delta) or delta <= 0:
        raise ValueError('Training did not change head weights')
    report = dict(status='training-completed', modelVersion='lexiquest-web-mobilenet16-2026-09-14.1',
                  datasetVersion=manifest['version'], manifestSha256=config['manifestSha256'],
                  configSha256=digest(config_path), selectedEpoch=best_epoch, epochs=config['epochs'],
                  selection='minimum development validation loss; fixed epochs, no threshold tuning',
                  method='frozen pretrained MobileNet backbone; newly trained 16-way softmax head',
                  trainableParameters=head.count_params(), backboneParameters=backbone.count_params(),
                  initialToSelectedHeadWeightL2=delta, metrics=measured, seconds=time.monotonic()-started,
                  candidateSha256=digest(output / 'candidate.keras'), checkpointSha256=digest(checkpoint),
                  rawEpochLogSha256=digest(output / 'epochs.jsonl'),
                  physicalCamera='NOT RUN', unknownEvaluation='NOT RUN', rolloutEnabled=False)
    write_json(output / 'training.json', report)
    print(json.dumps(report, allow_nan=False), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    train(args.config, args.output)
