"""v1.3 / 1: Manual-aligned TFLite export and reproducible local validation.

No custom HEX quantization: TensorFlow's converter owns scales/zero points.
Desktop Interpreter and vendor analyzer are not substitutes for target Invoke.
"""
import os
os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL', '2')
import json, hashlib, subprocess
from pathlib import Path
import numpy as np
import tensorflow as tf
from tensorflow.python.framework.convert_to_constants import convert_variables_to_constants_v2

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'ml/tinyml/artifacts'

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def export_int8(model, calibration, folder, name):
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    assert 100 <= len(calibration) <= 500
    # Fixed batch and frozen inference variables avoid Keras3 resource-variable
    # conversion incompatibility. Only converter-supported INT8 builtins allowed.
    spec=tf.TensorSpec([1,*model.input_shape[1:]],tf.float32,name='gray')
    concrete=tf.function(lambda x:model(x,training=False)).get_concrete_function(spec)
    frozen=convert_variables_to_constants_v2(concrete)
    converter=tf.lite.TFLiteConverter.from_concrete_functions([frozen])
    converter.optimizations=[tf.lite.Optimize.DEFAULT]
    converter.representative_dataset=lambda:([x[None].astype(np.float32)] for x in calibration)
    converter.target_spec.supported_ops=[tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type=tf.int8
    converter.inference_output_type=tf.int8
    content=converter.convert();path=folder/(name+'.tflite');path.write_bytes(content)
    interpreter=tf.lite.Interpreter(model_content=content,num_threads=4)
    interpreter.allocate_tensors()
    def tensor(t):
        return dict(name=t['name'],shape=t['shape'].tolist(),dtype=np.dtype(t['dtype']).name,
                    scale=float(t['quantization'][0]),zero_point=int(t['quantization'][1]))
    inputs=interpreter.get_input_details();outputs=interpreter.get_output_details()
    assert all(t['dtype']==np.int8 and t['quantization'][0]>0 for t in inputs+outputs)
    tensors=interpreter.get_tensor_details()
    assert not any(t['dtype'] in (np.float16,np.float32,np.float64) for t in tensors)
    ops=[op['op_name'] for op in interpreter._get_ops_details() if op['op_name']!='DELEGATE']
    allowed={'CONV_2D','DEPTHWISE_CONV_2D','RESHAPE','FULLY_CONNECTED','PAD','RELU','RELU6'}
    assert set(ops)<=allowed, f'Unreviewed operators: {set(ops)-allowed}'
    report=dict(version='v1.3',sha256=digest(path),bytes=len(content),inputs=list(map(tensor,inputs)),
                outputs=list(map(tensor,outputs)),ops=ops,calibration_count=len(calibration),
                calibration_split='train',full_int8=True,target_micro_invoke_verified=False,
                hardware_verified=False)
    (folder/'tflite_contract.json').write_text(json.dumps(report,indent=2))
    analyzer=ROOT/'tinyml-main/tools/tinyml_generator/bin/tflite.exe'
    r=subprocess.run([str(analyzer),str(path.resolve()),'4','4'],cwd=folder,
                     capture_output=True,text=True,errors='replace')
    (folder/'vendor_analyzer.log').write_text(r.stdout+r.stderr,encoding='utf-8')
    report['vendor_analyzer_returncode']=r.returncode
    (folder/'tflite_contract.json').write_text(json.dumps(report,indent=2))
    if r.returncode:raise RuntimeError('Vendor analyzer failed; inspect log')
    return path,report

def predict_tflite(path, images):
    interpreter=tf.lite.Interpreter(model_path=str(path),num_threads=4)
    interpreter.allocate_tensors();inp=interpreter.get_input_details()[0]
    outputs=interpreter.get_output_details();results=[[] for _ in outputs]
    scale,zero=inp['quantization']
    for x in images:
        quant=np.clip(np.rint(x/scale+zero),-128,127).astype(np.int8)
        interpreter.set_tensor(inp['index'],quant[None]);interpreter.invoke()
        for rows,t in zip(results,outputs):
            q=interpreter.get_tensor(t['index']);s,z=t['quantization'];rows.append((q[0].astype(np.float32)-z)*s)
    return [np.stack(r) for r in results]

def split_detection_heads(model):
    # v1.3 / 2: Object logits and coordinates require separate INT8 scales.
    last=model.layers[-1];weights,bias=last.get_weights();x=last.input
    score=tf.keras.layers.Conv2D(1,1,name='object_score')(x)
    boxes=tf.keras.layers.Conv2D(4,1,name='box_coordinates')(x)
    result=tf.keras.Model(model.input,[score,boxes],name='hand_detection_tflite')
    result.get_layer('object_score').set_weights([weights[...,:1],bias[:1]])
    result.get_layer('box_coordinates').set_weights([weights[...,1:],bias[1:]])
    return result
