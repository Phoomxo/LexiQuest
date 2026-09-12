"""Local four-class transfer/fine-tuning experiment, never a rollout command."""
import hashlib
import json
import os
from pathlib import Path
import sys
import urllib.request
import zipfile

from camera_accuracy import compare, audit_dataset

LABELS = ['book', 'bottle', 'chair', 'cup']
BASELINE_URL = ('https://storage.googleapis.com/download.tensorflow.org/models/tflite/'
                'task_library/image_classification/android/mobilenet_v1_1.0_224_quantized_1_metadata_1.tflite')
BASELINE_SHA = 'd3949e8a3556c79739cb675e0be7476503bcce76938031c6a1048e13e0cb7d8b'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(label):
    label = label.lower().strip()
    if label in ('book jacket', 'comic book'):
        return 'book'
    if label in ('water bottle', 'wine bottle', 'beer bottle', 'pop bottle', 'pill bottle'):
        return 'bottle'
    if label in ('folding chair', 'rocking chair', 'barber chair', 'throne'):
        return 'chair'
    if label in ('coffee mug', 'cup'):
        return 'cup'
    return '__other__'


def main():
    data, output = map(lambda value: Path(value).resolve(), sys.argv[1:3])
    manifest = json.loads((data / 'manifest.json').read_text(encoding='utf-8'))
    rows = manifest['samples']
    audit = audit_dataset(rows)
    if audit['status'] != 'coverage-ready':
        raise ValueError('insufficient-coverage: retain-baseline; do not train the legacy pilot')
    if any(row['truth'] not in LABELS for row in rows):
        raise ValueError('Retain baseline: legacy crop trainer cannot train/evaluate the R15 natural unknown protocol')
    # Keep legacy training code as historical evidence. R15 coverage requires
    # unknown scenes, so this crop-only trainer cannot pass the preflight.
    # A future training adapter needs a separately reviewed protocol revision.
    os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL', '2')
    os.environ.setdefault('KERAS_HOME', str(output / 'keras-cache'))
    import numpy as np
    from PIL import Image
    import tensorflow as tf

    output.mkdir(parents=True, exist_ok=True)
    if (output / 'report.json').exists() or (output / 'candidate.keras').exists():
        raise ValueError('Preserve previous training evidence')
    tf.config.threading.set_inter_op_parallelism_threads(2)
    tf.config.threading.set_intra_op_parallelism_threads(4)
    tf.keras.utils.set_random_seed(20260911)
    pixels, targets = [], []
    for row in rows:
        path = data / row['path']
        if digest(path) != row['sha256']:
            raise ValueError('Image checksum changed')
        with Image.open(path) as image:
            image = image.convert('RGB')
            width, height = image.size
            x0, y0, x1, y1 = row['box']
            crop = image.crop((int(x0 * width), int(y0 * height), int(x1 * width), int(y1 * height)))
            pixels.append(np.asarray(crop.resize((224, 224), Image.Resampling.BILINEAR)))
        targets.append(LABELS.index(row['truth']))
    pixels, targets = np.asarray(pixels), np.asarray(targets)
    indexes = {split: np.asarray([i for i, row in enumerate(rows) if row['split'] == split])
               for split in ('train', 'validation', 'test')}
    x = pixels.astype(np.float32) / 127.5 - 1.0
    backbone = tf.keras.applications.MobileNet(input_shape=(224, 224, 3),
        include_top=False, weights='imagenet', pooling='avg')
    backbone.trainable = False
    inputs = tf.keras.Input(shape=(224, 224, 3))
    outputs = tf.keras.layers.Dense(len(LABELS), activation='softmax')(
        backbone(inputs, training=False))
    model = tf.keras.Model(inputs, outputs)
    checkpoint = output / 'best.weights.h5'
    callbacks = [tf.keras.callbacks.ModelCheckpoint(str(checkpoint), monitor='val_loss',
                   save_best_only=True, save_weights_only=True)]
    history = []
    for phase, epochs, rate in [('head', 8, 0.001), ('fine-tune', 3, 0.00001)]:
        if phase == 'fine-tune':
            model.load_weights(checkpoint)
            backbone.trainable = True
            for layer in backbone.layers:
                layer.trainable = False
            for layer in backbone.layers[-12:]:
                layer.trainable = not isinstance(layer, tf.keras.layers.BatchNormalization)
        model.compile(optimizer=tf.keras.optimizers.Adam(rate),
                      loss='sparse_categorical_crossentropy', metrics=['accuracy'])
        print('phase', phase, flush=True)
        fitted = model.fit(x[indexes['train']], targets[indexes['train']],
            validation_data=(x[indexes['validation']], targets[indexes['validation']]),
            epochs=epochs, batch_size=8, callbacks=callbacks, verbose=2)
        history.append(dict(phase=phase, metrics=fitted.history))
    model.load_weights(checkpoint)
    model.save(output / 'candidate.keras')
    (output / 'training.json').write_text(json.dumps(history, indent=2), encoding='utf-8')
    baseline_path = output / 'baseline.tflite'
    if not baseline_path.exists():
        with urllib.request.urlopen(BASELINE_URL, timeout=45) as response:
            raw = response.read(5_000_000)
        baseline_path.write_bytes(raw)
    if digest(baseline_path) != BASELINE_SHA:
        raise ValueError('Pinned production baseline checksum mismatch')
    with zipfile.ZipFile(baseline_path) as archive:
        baseline_labels = archive.read('labels.txt').decode().splitlines()
    interpreter = tf.lite.Interpreter(model_path=str(baseline_path), num_threads=2)
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    predictions = np.argmax(model.predict(x[indexes['test']], batch_size=8, verbose=0), axis=1)
    prediction_rows = []
    for i, row in enumerate(rows):
        if row['split'] != 'test':
            prediction_rows.append({key: row[key] for key in ('id', 'group', 'split', 'truth')})
    for offset, i in enumerate(indexes['test']):
        interpreter.set_tensor(input_detail['index'], pixels[i:i+1])
        interpreter.invoke()
        baseline_index = int(np.argmax(interpreter.get_tensor(output_detail['index'])))
        label = baseline_labels[baseline_index]
        prediction_rows.append({key: rows[i][key] for key in ('id', 'group', 'split', 'truth')} |
            dict(baseline=canonical(label), baseline_raw_label=label,
                 candidate=LABELS[int(predictions[offset])]))
    report = compare(prediction_rows)
    report.update(dict(baseline_model=BASELINE_SHA,
        candidate_model=digest(output / 'candidate.keras'),
        manifest_sha256=digest(data / 'manifest.json'), tensorflow=tf.__version__,
        limitation='Object crops, four known classes, 40 test images; no open-set or vivo improvement claim.',
        selection='Fixed epochs, best validation loss; test used only after selection.'))
    (output / 'predictions.json').write_text(json.dumps(prediction_rows, indent=2), encoding='utf-8')
    (output / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
