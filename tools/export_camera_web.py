"""Export the pinned trained model; validate raw RGB and labels with real bytes.

No production URL or rollout is created. Conversion checks use development
validation only, and native probe inputs come from that same partition.
"""
import argparse
import json
import os
from pathlib import Path
import zipfile

from camera_web_dataset import digest, write_json
from train_camera_web import read_pinned, training_rows, pixels_for


def label_contract(labels):
    if not labels or len(labels) != len(set(labels)) or any(
            not isinstance(x, str) or not x.strip() or x != x.strip() or '\n' in x for x in labels):
        raise ValueError('Unique nonempty single-line labels required')
    return dict(inputShape=[1, 224, 224, 3], inputType='uint8',
                outputShape=[1, len(labels)], outputType='float32',
                backgroundClassIndex=None, inputEncoding='rawUint8Rgb', labelAssetName='labels.txt')


def export(run):
    destination = run / 'candidate.tflite'
    if destination.exists() or (run / 'export.json').exists():
        raise ValueError('Preserve previous candidate export')
    report = json.loads((run / 'training.json').read_text(encoding='utf-8'))
    config = json.loads((run / 'config.json').read_text(encoding='utf-8'))
    manifest_path = Path(config['manifestPath'])
    manifest = read_pinned(manifest_path, report['manifestSha256'])
    if report['status'] != 'training-completed' or digest(run / 'candidate.keras') != report['candidateSha256']:
        raise ValueError('Completed pinned checkpoint required')
    partitions = training_rows(manifest)
    labels = manifest['labels']
    contract = label_contract(labels)
    os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0'
    os.environ['CUDA_VISIBLE_DEVICES'] = '-1'
    os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
    import numpy as np
    import tensorflow as tf
    tf.config.threading.set_inter_op_parallelism_threads(2)
    tf.config.threading.set_intra_op_parallelism_threads(4)
    model = tf.keras.models.load_model(run / 'candidate.keras', compile=False)
    raw = tf.keras.Input(batch_shape=(1, 224, 224, 3), dtype='uint8')
    normalized = tf.keras.layers.Rescaling(1 / 127.5, offset=-1)(raw)
    wrapped = tf.keras.Model(raw, model(normalized, training=False))
    converter = tf.lite.TFLiteConverter.from_keras_model(wrapped)
    binary = converter.convert()
    with destination.open('xb') as output:
        output.write(binary)
    with zipfile.ZipFile(destination, 'a') as archive:
        archive.writestr('labels.txt', '\n'.join(labels) + '\n')
    interpreter = tf.lite.Interpreter(model_path=str(destination), num_threads=2)
    interpreter.allocate_tensors()
    inputs, outputs = interpreter.get_input_details(), interpreter.get_output_details()
    if (len(inputs) != 1 or len(outputs) != 1 or inputs[0]['dtype'] != np.uint8
            or outputs[0]['dtype'] != np.float32
            or inputs[0]['shape'].tolist() != contract['inputShape']
            or outputs[0]['shape'].tolist() != contract['outputShape']):
        raise ValueError('Exported tensor contract mismatch')
    with zipfile.ZipFile(destination) as archive:
        if archive.read('labels.txt').decode('utf-8').splitlines() != labels:
            raise ValueError('Embedded label order mismatch')
    differences, matches, probe, predicted = [], 0, [], []
    for index in partitions['validation']:
        row = manifest['samples'][index]
        pixels = pixels_for(row, manifest_path.parent)[None]
        reference = model(pixels.astype(np.float32) / 127.5 - 1, training=False).numpy()[0]
        interpreter.set_tensor(inputs[0]['index'], pixels)
        interpreter.invoke()
        actual = interpreter.get_tensor(outputs[0]['index'])[0]
        if not np.all(np.isfinite(actual)) or not np.all((actual >= 0) & (actual <= 1)):
            raise ValueError('Invalid classifier output')
        differences.append(float(np.max(np.abs(reference - actual))))
        matches += int(np.argmax(reference) == np.argmax(actual))
        predicted.append(dict(id=row['id'], truth=row['label'], prediction=labels[int(np.argmax(actual))],
                              probabilities=[float(v) for v in actual]))
        if len(probe) < 4:
            path = run / f'probe-{len(probe)}.rgb'
            with path.open('xb') as file:
                file.write(pixels.tobytes())
            probe.append(dict(id=row['id'], split='validation', path=str(path.resolve()),
                              sha256=digest(path), scores=[float(v) for v in actual]))
    maximum = max(differences) if differences else None
    passed = bool(differences) and matches == len(differences) and maximum <= .001
    manifest_out = dict(schema='lexiquest-local-camera-candidate-v1', id='lexiquest-web-mobilenet16',
                        version='2026-09-14.1', minimumAppVersion='1.0.0',
                        localArtifactPath=str(destination.resolve()), distributionUri=None,
                        expectedSha256=digest(destination), expectedBytes=destination.stat().st_size,
                        **contract, labels=labels, supportedDelegates=['cpu'],
                        trainingManifestSha256=report['manifestSha256'],
                        kerasCheckpointSha256=report['candidateSha256'],
                        validationSamples=len(differences), matchingTop1=matches,
                        maximumProbabilityError=maximum, parityPassed=passed,
                        probe=probe, releaseEnabled=False,
                        modelRights='Local development candidate; pretrained and image attribution retained in B11A evidence; not published',
                        rollback=dict(id='mobilenet-v1-imagenet',
                                      sha256='d3949e8a3556c79739cb675e0be7476503bcce76938031c6a1048e13e0cb7d8b',
                                      action='Production manifest remains unchanged; remove local candidate selection to use pinned baseline'),
                        limitations=['16 object categories; cannot silently replace broad1001-output baseline',
                                     'Object-crop web development metrics only; camera/unknown/device/resources pending'])
    write_json(run / 'export.json', manifest_out)
    write_json(run / 'tflite-validation-predictions.json', predicted)
    if not passed:
        raise ValueError('TFLite conversion parity failed; preserve output and diagnose')
    print(json.dumps(dict(status='export-verified', sha256=manifest_out['expectedSha256'],
                         bytes=manifest_out['expectedBytes'], validationSamples=len(differences),
                         matchingTop1=matches, maximumProbabilityError=maximum)), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    export(parser.parse_args().run)
