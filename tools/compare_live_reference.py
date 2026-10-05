"""Compare a coherent board capture with TensorFlow BUILTIN_REF (Quant env)."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
import tensorflow as tf

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('work',type=Path)
parser.add_argument('name')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
model=root.parent/'CNN-Tutorial/artifacts/v0.3-int8/gesture_int8.tflite'
raw=(args.work/(args.name+'-input.bin')).read_bytes()
status=json.loads((args.work/(args.name+'.json')).read_text())
if len(raw)!=4096 or status['stage']!=8 or status['error']!=0:
    raise RuntimeError('No coherent completed camera sample')
checksum=2166136261
for byte in raw:
    checksum=((checksum^(byte^128))*16777619)&0xffffffff
if checksum!=status['input_checksum']:
    raise RuntimeError('Captured input differs from firmware pre-Invoke checksum')
interpreter=tf.lite.Interpreter(model_path=str(model),experimental_op_resolver_type=tf.lite.experimental.OpResolverType.BUILTIN_REF)
interpreter.allocate_tensors()
interpreter.set_tensor(interpreter.get_input_details()[0]['index'],np.frombuffer(raw,dtype=np.int8).reshape(1,64,64,1))
interpreter.invoke()
expected=interpreter.get_tensor(interpreter.get_output_details()[0]['index']).reshape(-1).tolist()
report={'tensorflow':tf.__version__,'backend':'BUILTIN_REF','input_sha256':hashlib.sha256(raw).hexdigest(),
        'model_sha256':hashlib.sha256(model.read_bytes()).hexdigest(),'checksum_verified':True,
        'board':status['output'],'reference':expected,'exact_match':status['output']==expected,
        'frame':status['frame'],'completed':status['completed']}
(args.work/(args.name+'-reference.json')).write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
if not report['exact_match']: raise SystemExit(1)
