"""v1.1 / 3: Fold BN, quantize for RTL, emit ROMs, and validate held-out data.

RTL uses symmetric int8 weights/activations and power-of-two layer scales.
It is a documented custom integer format, NOT a claim of TFLite bit equivalence.
"""
import os
os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL','2')
import hashlib
import json
from pathlib import Path
import numpy as np
import tensorflow as tf
from train_v1_1 import ROOT,LABELS,load_split,metrics


def rounded_shift(x,shift):
    # Matches signed RTL: add positive half then arithmetic shift (ties +infinity).
    return (x+(1<<(shift-1)))>>shift if shift>0 else x<<(-shift)


def integer_infer(images,layers,keep=False):
    x=images.astype(np.int32)-128
    intermediates=[]
    for layer in layers:
        w=np.array(layer['weights'],np.int32).reshape(layer['shape'])
        b=np.array(layer['bias'],np.int32)
        # Integer-valued float32 conv is exact here; validate the absolute bound.
        axes=(0,1,2) if len(w.shape)==4 else (0,)
        bound=128*np.abs(w).sum(axis=axes)+np.abs(b)
        if np.max(bound)>=2**24:raise ValueError('Float32 integer reference bound exceeded')
        if len(w.shape)==4:
            a=tf.nn.conv2d(tf.cast(x,tf.float32),tf.cast(w,tf.float32),strides=[1,2,2,1],padding='SAME').numpy().astype(np.int64)+b
        else:
            a=x.reshape(len(x),-1).astype(np.int64)@w.astype(np.int64)+b
        x=rounded_shift(a,layer['shift'])
        x=np.clip(x,0,127) if len(w.shape)==4 else np.clip(x,-32768,32767)
        x=x.astype(np.int32)
        if keep:intermediates.append(x.copy())
    return (x,intermediates) if keep else x


def main():
    tf.config.threading.set_intra_op_parallelism_threads(8)
    tf.config.threading.set_inter_op_parallelism_threads(2)
    out=ROOT/'artifacts'
    model=tf.keras.models.load_model(out/'best.keras')
    train_x,train_y=load_split('train');val_x,val_y=load_split('val')
    rng=np.random.default_rng(1101)
    picks=np.concatenate([rng.choice(np.where(train_y==i)[0],min(80,np.sum(train_y==i)),replace=False) for i in range(6)])
    calibration=(train_x[picks].astype(np.float32)-128)/128
    folded=[]
    for i in range(4):
        w=model.get_layer(f'conv{i}').get_weights()[0]
        bn=model.get_layer(f'bn{i}');gamma,beta,mean,var=bn.get_weights()
        factor=gamma/np.sqrt(var+bn.epsilon)
        folded.append((w*factor,beta-mean*factor))
    folded.append(tuple(model.get_layer('logits').get_weights()))
    relu_model=tf.keras.Model(model.input,[model.get_layer(f'relu{i}').output for i in range(4)])
    activations=relu_model.predict(calibration,batch_size=64,verbose=0)
    layers=[];input_frac=7
    for i,(w,b) in enumerate(folded):
        wfrac=int(np.floor(np.log2(127/max(float(np.max(np.abs(w))),1e-8))))
        ofrac=int(np.floor(np.log2(127/max(float(np.percentile(activations[i],99.99)),1e-6)))) if i<4 else 8
        shift=input_frac+wfrac-ofrac
        if not 0<=shift<=24:raise ValueError(f'Unsupported RTL shift {shift}')
        qw=np.clip(np.floor(w*2.**wfrac+0.5),-127,127).astype(np.int8)
        qb=np.floor(b*2.**(input_frac+wfrac)+0.5).astype(np.int64)
        if np.max(np.abs(qb))>=2**31:raise ValueError('bias overflow')
        layers.append(dict(shape=list(w.shape),weights=qw.ravel().tolist(),bias=qb.tolist(),
                           input_frac=input_frac,weight_frac=wfrac,output_frac=ofrac,shift=shift))
        input_frac=ofrac
    quant=dict(version='v1.1',labels=LABELS,input='(gray_uint8-128), NHWC, 64x64',
               padding='SAME: even input, 3x3 stride2 => top/left=0, bottom/right=1',
               rounding='floor((acc + 2**(shift-1))/2**shift)',layers=layers)
    (out/'model_int8.json').write_text(json.dumps(quant))
    romdir=ROOT.parents[1]/'src/cnn/rom';romdir.mkdir(exist_ok=True,parents=True)
    weights=[];biases=[];wbase=[];bbase=[]
    for layer in layers:
        wbase.append(len(weights));bbase.append(len(biases))
        w=np.array(layer['weights'],np.int8).reshape(layer['shape'])
        weights.extend((w.transpose(3,0,1,2) if w.ndim==4 else w.T).ravel().tolist())
        biases.extend(layer['bias'])
    (romdir/'weights.hex').write_text(''.join(f'{v&255:02x}\n' for v in weights))
    (romdir/'biases.hex').write_text(''.join(f'{v&0xffffffff:08x}\n' for v in biases))
    (romdir/'shifts.hex').write_text(''.join(f'{l["shift"]:02x}\n' for l in layers))
    # Threshold selection uses validation only; test is evaluated once afterwards.
    vpred=integer_infer(val_x,layers)
    top=np.argmax(vpred,axis=1);sorted_logits=np.sort(vpred,axis=1)
    margins=sorted_logits[:,-1]-sorted_logits[:,-2]
    choices=[]
    for threshold in (64,128,192,256,384,512,768,1024):
        accepted=(top<5)&(margins>=threshold)
        wrong=int(np.sum(accepted&(top!=val_y)))
        right=int(np.sum(accepted&(top==val_y)))
        choices.append(dict(threshold=threshold,accepted=int(accepted.sum()),correct=right,wrong=wrong))
    # Prefer >=95% accepted precision; among them maximize coverage. No hidden test tuning.
    eligible=[c for c in choices if c['accepted'] and c['correct']/c['accepted']>=.95]
    choice=max(eligible,key=lambda c:c['correct']) if eligible else min(choices,key=lambda c:c['wrong'])
    threshold=choice['threshold']
    (romdir/'threshold.hex').write_text(f'{threshold:04x}\n')
    test_x,test_y=load_split('test')
    fp=model.predict((test_x.astype(np.float32)-128)/128,batch_size=64,verbose=0)
    qpred=integer_infer(test_x,layers)
    predictions=np.argmax(qpred,1);m=np.sort(qpred,axis=1);accept=(predictions<5)&((m[:,-1]-m[:,-2])>=threshold)
    report=dict(version='v1.1',float_test=metrics(test_y,fp),int8_test=metrics(test_y,qpred),
                float_int8_agreement=float(np.mean(np.argmax(fp,1)==predictions)),
                test_samples=len(test_y),threshold_q8=threshold,threshold_selection=choices,
                accepted_test_count=int(accept.sum()),accepted_test_correct=int(np.sum(accept&(predictions==test_y))),
                test_unknown_false_accept=int(np.sum(accept&(test_y==5))),
                weight_bytes=len(weights),bias_bytes=4*len(biases),weight_offsets=wbase,bias_offsets=bbase,
                model_sha256=hashlib.sha256((out/'model_int8.json').read_bytes()).hexdigest())
    # One independent held-out vector for every class plus all-zero/all-255 borders.
    vectors=[]
    for label in range(6):
        index=int(np.where(test_y==label)[0][0]);vectors.append(test_x[index])
    vectors.extend([np.zeros((64,64,1),np.uint8),np.full((64,64,1),255,np.uint8)])
    vector_dir=out/'vectors';vector_dir.mkdir(exist_ok=True)
    for i,im in enumerate(vectors):
        scores,intermediate=integer_infer(im[None],layers,keep=True)
        (vector_dir/f'input_{i}.hex').write_text(''.join(f'{int(v):02x}\n' for v in im.ravel()))
        (vector_dir/f'scores_{i}.hex').write_text(''.join(f'{int(v)&65535:04x}\n' for v in scores.ravel()))
        for j,values in enumerate(intermediate[:-1]):
            (vector_dir/f'layer_{i}_{j}.hex').write_text(''.join(f'{int(v)&255:02x}\n' for v in values.ravel()))
    (out/'validation_report.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2),flush=True)


if __name__=='__main__':main()
