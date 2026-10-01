"""v1.3 / 8: Package real TFLite bytes, vendor settings, and exact golden logits."""
import json,hashlib,shutil
from pathlib import Path
import numpy as np
import tensorflow as tf
ROOT=Path(__file__).resolve().parents[1]
artifact=ROOT/'ml/tinyml/artifacts/classifier'
dest=ROOT/'firmware/tinyml_gesture_v1_3'
models=dest/'src/model';models.mkdir(parents=True,exist_ok=True)
profile=artifact/'generator/lite_p2'
for name in ['define.h','define.cc','gesture_classifier_int8_model_data.h','gesture_classifier_int8_model_data.cc']:
    shutil.copy2(profile/name,models/name)
p=models/'gesture_classifier_int8_model_data.cc'
p.write_text('// v1.3: align FlatBuffer storage for the target CPU.\n'+p.read_text().replace('const unsigned char ', 'alignas(16) const unsigned char '))
shutil.copy2(profile/'defines.v',dest/'defines.v')
reference=np.load(artifact/'micro_golden.npz')['input_float']
interpreter=tf.lite.Interpreter(model_path=str(artifact/'gesture_classifier_int8.tflite'),num_threads=4)
interpreter.allocate_tensors();inp=interpreter.get_input_details()[0];out=interpreter.get_output_details()[0]
inputs=[];outputs=[]
for sample in reference:
    s,z=inp['quantization'];q=np.clip(np.rint(sample/s+z),-128,127).astype(np.int8)
    interpreter.set_tensor(inp['index'],q[None]);interpreter.invoke()
    inputs.append(q.ravel());outputs.append(interpreter.get_tensor(out['index']).ravel())
def array(name,rows):
    return f'static const int8_t {name}[{len(rows)}][{len(rows[0])}] = {{\n'+',\n'.join('{'+','.join(map(str,row.tolist()))+'}' for row in rows)+'\n};\n'
(models/'gesture_golden.h').write_text('// v1.3: fixed real held-out images; PC TFLite integer reference.\n#pragma once\n#include <stdint.h>\n'+f'constexpr int kGestureGoldenCount={len(inputs)};\n'+array('gesture_golden_input',inputs)+array('gesture_golden_output',outputs))
manifest=dict(version='v1.3',purpose='fixed-input target validation, not live firmware',profile='LITE P2, FC LITE, cache disabled',
              target_compiled=False,target_executed=False,model_sha256=hashlib.sha256((artifact/'gesture_classifier_int8.tflite').read_bytes()).hexdigest(),
              golden_cases=len(inputs),input_quantization=list(inp['quantization']),output_quantization=list(out['quantization']),
              files_sha256={p.relative_to(dest).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(dest.rglob('*')) if p.is_file() and p.name!='manifest.json'})
(dest/'manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps({k:v for k,v in manifest.items() if k!='files_sha256'},indent=2))
