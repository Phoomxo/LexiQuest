"""Generate a tiny synthetic float-output classifier for native regression.

Requires TensorFlow only when regenerating. No images, learned weights or
external models are used. Deliberately preserve any existing fixture.
"""
import hashlib
from pathlib import Path
import zipfile
import tensorflow as tf


class SyntheticClassifier(tf.Module):
    @tf.function(input_signature=[tf.TensorSpec([1, 1, 1, 3], tf.uint8)])
    def classify(self, pixels):
        offset = tf.reduce_sum(tf.cast(pixels, tf.float32)) * 0.00001
        return tf.constant([[0.6, 0.2, 0.1, 0.1]], dtype=tf.float32) + offset


model = SyntheticClassifier()
converter = tf.lite.TFLiteConverter.from_concrete_functions(
    [model.classify.get_concrete_function()], model)
target = Path('test/features/device_model/fixtures/synthetic_float_classifier.tflite')
target.parent.mkdir(parents=True, exist_ok=True)
with target.open('xb') as output:
    output.write(converter.convert())
with zipfile.ZipFile(target, 'a') as archive:
    info = zipfile.ZipInfo('labels.txt', date_time=(2026, 9, 11, 0, 0, 0))
    archive.writestr(info, 'book\nbottle\nchair\ncup\n')
print(hashlib.sha256(target.read_bytes()).hexdigest(), target.stat().st_size)
