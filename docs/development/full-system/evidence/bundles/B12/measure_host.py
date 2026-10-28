"""Bounded candidate CPU diagnostic, not app pipeline/device acceptance."""
import ctypes
from ctypes import wintypes
import gc
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import time

os.environ['CUDA_VISIBLE_DEVICES'] = '-1'
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
import numpy as np
import tensorflow as tf

ROOT = Path(__file__).resolve().parents[6]
sys.path.insert(0, str(ROOT / 'tools'))
from camera_development_evaluation import load_inputs, read_pin

class Memory(ctypes.Structure):
    _fields_ = [('cb', wintypes.DWORD), ('faults', wintypes.DWORD)] + [
        (name, ctypes.c_size_t) for name in ['peakWorking', 'working', 'peakPaged', 'paged',
                                           'peakNonPaged', 'nonPaged', 'pagefile', 'peakPagefile']]

def rss():
    counters = Memory(); counters.cb = ctypes.sizeof(counters)
    if not ctypes.windll.psapi.GetProcessMemoryInfo(wintypes.HANDLE(-1), ctypes.byref(counters), counters.cb):
        raise ctypes.WinError()
    return counters.working

config = json.loads((Path(__file__).parent / 'G5.4-config.json').read_text())
load_inputs(config)
export = json.loads(read_pin(config['artifacts']['export']))
images = []
for probe in export['probe']:
    raw = read_pin(dict(path=probe['path'], sha256=probe['sha256']))
    images.append(np.frombuffer(raw, dtype=np.uint8).reshape(1,224,224,3))

def load():
    interpreter = tf.lite.Interpreter(model_path=config['artifacts']['model']['path'], num_threads=4,
        experimental_op_resolver_type=tf.lite.experimental.OpResolverType.BUILTIN_WITHOUT_DEFAULT_DELEGATES)
    interpreter.allocate_tensors()
    return interpreter

def invoke(interpreter, pixels):
    input_info = interpreter.get_input_details()[0]
    output_info = interpreter.get_output_details()[0]
    assert input_info['shape'].tolist() == [1,224,224,3] and input_info['dtype'] == np.uint8
    assert output_info['shape'].tolist() == [1,16] and output_info['dtype'] == np.float32
    interpreter.set_tensor(input_info['index'], pixels)
    interpreter.invoke()
    scores = interpreter.get_tensor(output_info['index'])
    assert np.isfinite(scores).all() and abs(float(scores.sum())-1) < 1e-5
    return scores

before = rss(); start = time.perf_counter()
interpreter = load(); scores = invoke(interpreter, images[0])
cold_ms = (time.perf_counter()-start)*1000
after_load = rss()
for i in range(5):
    invoke(interpreter, images[i % len(images)])
times, memory = [], []
for i in range(50):
    start = time.perf_counter(); invoke(interpreter, images[i % len(images)])
    times.append((time.perf_counter()-start)*1000); memory.append(rss())
del interpreter; gc.collect()
after_close = rss()
cycles = []
if sys.argv[2] == 'cycles':
    for i in range(30):
        interpreter = load(); invoke(interpreter, images[i % len(images)])
        del interpreter; gc.collect(); cycles.append(rss())
report = dict(scope='Windows host Python CPU invoke only; no camera/app pipeline or physical acceptance',
    pid=os.getpid(), python=platform.python_version(), tensorflow=tf.__version__, platform=platform.platform(),
    delegate='builtin CPU without default delegates', threads=4, modelSha256=config['candidate_model'],
    modelBytes=Path(config['artifacts']['model']['path']).stat().st_size, warmup=5, measured=50,
    coldLoadAllocateFirstInvokeMs=cold_ms, invokeMs=times, invokeP50Ms=float(np.percentile(times,50)),
    invokeP90Ms=float(np.percentile(times,90)), rssBeforeLoad=before, rssAfterLoad=after_load,
    rssSamples=memory, rssAfterClose=after_close, cycleRssAfterClose=cycles,
    nativeHandleCount='NOT MEASURED; Python del/gc does not prove absence of native leaks',
    baselineComparison='NOT RUN', physicalResourceGate='NOT RUN')
with Path(sys.argv[1]).open('x', encoding='utf-8', newline='\n') as output:
    json.dump(report, output, indent=2, allow_nan=False); output.write('\n')
print(json.dumps({k: report[k] for k in ['pid','invokeP50Ms','invokeP90Ms','physicalResourceGate']}))
