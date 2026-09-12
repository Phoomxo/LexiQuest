"""Export the unshipped pilot to a raw-RGB uint8-input TFLite artifact.

Validate conversion parity using validation images only. Does not modify the
production model manifest, publish a download URL, or claim device acceptance.
"""
import hashlib
import json
import os
from pathlib import Path
import sys
import zipfile

os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL', '2')
import numpy as np
from PIL import Image
import tensorflow as tf


def main():
    data, experiment = map(lambda value: Path(value).resolve(), sys.argv[1:3])
    destination = experiment / 'candidate.tflite'
    if destination.exists():
        raise ValueError('Preserve prior exported model')
    model = tf.keras.models.load_model(experiment / 'candidate.keras', compile=False)
    raw = tf.keras.Input(batch_shape=(1, 224, 224, 3), dtype='uint8')
    normalized = tf.keras.layers.Rescaling(1 / 127.5, offset=-1)(raw)
    wrapped = tf.keras.Model(raw, model(normalized, training=False))
    converter = tf.lite.TFLiteConverter.from_keras_model(wrapped)
    binary = converter.convert()
    with destination.open('xb') as output:
        output.write(binary)
    with zipfile.ZipFile(destination, 'a') as archive:
        archive.writestr('labels.txt', 'book\nbottle\nchair\ncup\n')
    interpreter = tf.lite.Interpreter(model_path=str(destination), num_threads=2)
    interpreter.allocate_tensors()
    inp = interpreter.get_input_details()[0]
    out = interpreter.get_output_details()[0]
    assert inp['dtype'] == np.uint8 and list(inp['shape']) == [1, 224, 224, 3]
    assert out['dtype'] == np.float32 and list(out['shape']) == [1, 4]
    manifest = json.loads((data / 'manifest.json').read_text(encoding='utf-8'))
    maximum_error, agrees, total = 0.0, 0, 0
    for row in manifest['samples']:
        if row['split'] != 'validation':
            continue
        path = data / row['path']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == row['sha256']
        with Image.open(path) as image:
            image = image.convert('RGB')
            width, height = image.size
            x0, y0, x1, y1 = row['box']
            crop = image.crop((int(x0 * width), int(y0 * height), int(x1 * width), int(y1 * height)))
            pixels = np.asarray(crop.resize((224, 224), Image.Resampling.BILINEAR))[None]
        reference = model(pixels.astype(np.float32) / 127.5 - 1.0, training=False).numpy()
        interpreter.set_tensor(inp['index'], pixels)
        interpreter.invoke()
        actual = interpreter.get_tensor(out['index'])
        maximum_error = max(maximum_error, float(np.max(np.abs(reference - actual))))
        agrees += int(np.argmax(reference) == np.argmax(actual))
        total += 1
    report = dict(sha256=hashlib.sha256(destination.read_bytes()).hexdigest(),
        bytes=destination.stat().st_size, validation_samples=total,
        matching_top1=agrees, maximum_probability_error=maximum_error,
        input_shape=[1, 224, 224, 3], input_type='uint8',
        output_shape=[1, 4], output_type='float32',
        release_enabled=False,
        limitations=['Four-class pilot without unknown class.',
                     'Existing scanner requests topK=10 and excludes class zero; not a drop-in replacement.',
                     'Native vivo interpreter/latency and full-frame accuracy not verified.'])
    (experiment / 'export.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    if total == 0 or agrees != total or maximum_error > 0.001:
        raise ValueError('Conversion parity failed; inspect preserved evidence')
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
