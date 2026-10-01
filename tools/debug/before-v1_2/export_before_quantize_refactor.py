"""v1.2 / 13: Detector BN folding, INT8 ROM export, localization and pipeline audit.
Test split is evaluated only after validation chooses the object threshold.
"""
import os
os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL','2')
import sys,json,hashlib
from pathlib import Path
import numpy as np
from PIL import Image
import tensorflow as tf
from train import ROOT,data,detector_loss

def infer(images,layers,keep=False):
    x=images.astype(np.int32)-128;trace=[]
    for i,l in enumerate(layers):
        w=np.array(l['weights'],np.int32).reshape(l['shape']);b=np.array(l['bias'],np.int64)
        if np.max(128*np.abs(w).sum(axis=(0,1,2))+np.abs(b))>=2**24:raise ValueError('Exact float integer bound exceeded')
        stride=2 if i<3 else 1;dilation=2 if i==3 else 1
        a=tf.nn.conv2d(tf.cast(x,tf.float32),tf.cast(w,tf.float32),strides=[1,stride,stride,1],padding='SAME',dilations=[1,dilation,dilation,1]).numpy().astype(np.int64)+b
        shift=np.array(l['shift'],np.int64)
        x=(a+np.where(shift>0,1<<np.maximum(shift-1,0),0))>>shift
        x=np.clip(x,0,127) if i<4 else np.clip(x,-32768,32767)
        x=x.astype(np.int32)
        if keep:trace.append(x.copy())
    return (x,trace) if keep else x

def select(head):
    head=np.asarray(head);scores=head[...,0].copy()
    good=(head[...,3]>=7)&(head[...,3]<=256)&(head[...,4]>=12)&(head[...,4]<=256)
    scores=np.where(good,scores,-32768)
    gy,gx=np.unravel_index(np.argmax(scores),scores.shape)
    q=head[gy,gx];dx,dy,bw,bh=np.clip(q[1:],0,256).astype(np.int64)
    width=int(bw*5);height=int((bh*45+8)>>4)
    cx=int(gx*40+((dx*40+128)>>8));cy=int(gy*40+((dy*40+128)>>8))
    block=int(np.clip((max(width,height)*93+4095)>>12,1,11));side=block*64
    x=int(np.clip(cx-side//2,0,1280-side));y=int(np.clip(cy-side//2,0,720-side))
    box=[(cx-width/2)/1280,(cy-height/2)/720,width/1280,height/720]
    valid=bool(good[gy,gx] and width>=32 and height>=32)
    return dict(score=int(scores[gy,gx]),valid=valid,box=box,roi=[x,y,side],grid=[int(gx),int(gy)])

def iou(a,b):
    x,y,w,h=a[:4];u,v,s,t=b[:4]
    inter=max(0,min(x+w,u+s)-max(x,u))*max(0,min(y+h,v+t)-max(y,v))
    return inter/max(w*h+s*t-inter,1e-9)

def stats(heads,examples,threshold):
    accepted=correct=positive=negative=false_background=0;overlaps=[]
    for h,(_,boxes,_) in zip(heads,examples):
        p=select(h);positive+=bool(boxes);negative+=not bool(boxes)
        overlap=max([iou(p['box'],b) for b in boxes] or [0]);overlaps.append(overlap)
        if p['valid'] and p['score']>=threshold:
            accepted+=1;correct+=overlap>=.5;false_background+=not bool(boxes)
    precision=correct/max(accepted,1);recall=correct/max(positive,1)
    return dict(threshold_q8=threshold,images=len(examples),positive_images=positive,background_images=negative,accepted=accepted,localized_iou50=correct,precision_iou50=precision,scene_recall_iou50=recall,f1=2*precision*recall/max(precision+recall,1e-9),background_false_accept=false_background,mean_best_iou=float(np.mean(overlaps)))

def main():
    tf.config.threading.set_intra_op_parallelism_threads(8);tf.config.threading.set_inter_op_parallelism_threads(2)
    out=ROOT/'artifacts';model=tf.keras.models.load_model(out/'best.keras',compile=False)
    train=data('train');val=data('val');rng=np.random.default_rng(1202)
    idx=rng.choice(len(train),min(480,len(train)),replace=False)
    calibration=np.stack([train[i][0] for i in idx])[...,None].astype(np.float32)
    hidden=tf.keras.Model(model.input,[model.get_layer(f'relu{i}').output for i in range(4)]).predict((calibration-128)/128,batch_size=48,verbose=0)
    folded=[]
    for i in range(4):
        w=model.get_layer(f'conv{i}').get_weights()[0];bn=model.get_layer(f'bn{i}');gamma,beta,mean,var=bn.get_weights();factor=gamma/np.sqrt(var+bn.epsilon)
        folded.append((w*factor,beta-mean*factor))
    folded.append(tuple(model.get_layer('head').get_weights()))
    layers=[];fi=7
    for i,(w,b) in enumerate(folded):
        maxw=np.max(np.abs(w),axis=(0,1,2)) if i==4 else np.max(np.abs(w))
        fw=np.floor(np.log2(127/np.maximum(maxw,1e-8))).astype(np.int32)
        fo=int(np.floor(np.log2(127/max(float(np.percentile(hidden[i],99.99)),1e-6)))) if i<4 else 8
        shift=fi+fw-fo
        if np.any(shift<0) or np.any(shift>24):raise ValueError('Unsupported shift')
        qw=np.clip(np.floor(w*np.exp2(fw)+.5),-127,127).astype(np.int8);qb=np.floor(b*np.exp2(fi+fw)+.5).astype(np.int64)
        if np.max(np.abs(qb))>=2**31:raise ValueError('bias overflow')
        layers.append(dict(shape=list(w.shape),weights=qw.ravel().tolist(),bias=qb.tolist(),shift=shift.tolist(),input_frac=fi,weight_frac=fw.tolist(),output_frac=fo));fi=fo
    quant=dict(version='v1.2',input='256x144 gray - 128, NHWC',head=['object_logit','cell_dx','cell_dy','width_normalized','height_normalized'],layers=layers)
    (out/'model_int8.json').write_text(json.dumps(quant))
    vx=np.stack([i for i,b,_ in val])[...,None];vq=infer(vx,layers)
    candidates=[stats(vq,val,t) for t in (-768,-512,-256,0,128,256,384,512,768,1024)]
    # v1.2 / 24: Fail closed before modifying deployment ROMs or reading test.
    # These are minimum engineering gates, not a guarantee for real camera scenes.
    eligible=[c for c in candidates if c['precision_iou50']>=.85 and c['scene_recall_iou50']>=.50]
    if not eligible:
        (out/'validation_gate_failed.json').write_text(json.dumps(dict(version='v1.2',minimum_precision=.85,minimum_scene_recall=.50,candidates=candidates),indent=2))
        raise SystemExit('Validation gate failed: no ROM export and no test-set evaluation. See validation_gate_failed.json')
    chosen=max(eligible,key=lambda c:c['scene_recall_iou50'])
    threshold=chosen['threshold_q8']
    rom=ROOT.parents[1]/'src/cnn/rom_v1_2';rom.mkdir(parents=True,exist_ok=True)
    previous=ROOT.parents[1]/'src/cnn/rom'
    weights=[];bias=[];shifts=[]
    for l in layers:
        w=np.array(l['weights'],np.int8).reshape(l['shape']);weights.extend(w.transpose(3,0,1,2).ravel());bias.extend(l['bias']);shifts.extend(l['shift'] if isinstance(l['shift'],list) else [l['shift']])
    for name,values,mask,digits in [('weights',weights,255,2),('biases',bias,0xffffffff,8),('shifts',shifts,255,2)]:
        (rom/f'{name}.hex').write_text((previous/f'{name}.hex').read_text()+''.join(f'{int(v)&mask:0{digits}x}\n' for v in values))
    (rom/'hand_threshold.hex').write_text(f'{threshold&65535:04x}\n')
    test=data('test');tx=np.stack([i for i,b,_ in test])[...,None];tq=infer(tx,layers)
    fp=model.predict((tx.astype(np.float32)-128)/128,batch_size=48,verbose=0)
    fq=np.clip(np.floor(fp*256+.5),-32768,32767).astype(np.int32)
    report=dict(version='v1.2',validation_candidates=candidates,selected=chosen,int8_test=stats(tq,test,threshold),float_test=stats(fq,test,threshold),weight_bytes=len(weights),bias_bytes=4*len(bias),model_sha256=hashlib.sha256((out/'model_int8.json').read_bytes()).hexdigest())
    vd=out/'vectors';vd.mkdir(exist_ok=True)
    # Deterministic test examples plus uniform border inputs; no cherry-picking.
    images=[tx[i] for i in range(min(4,len(tx)))]+[np.zeros((144,256,1),np.uint8),np.full((144,256,1),255,np.uint8)]
    for n,im in enumerate(images):
        scores,trace=infer(im[None],layers,keep=True)
        (vd/f'input_{n}.hex').write_text(''.join(f'{int(v):02x}\n' for v in im.ravel()))
        (vd/f'head_{n}.hex').write_text(''.join(f'{int(v)&65535:04x}\n' for v in scores.ravel()))
        for j,arr in enumerate(trace[:-1]):(vd/f'layer_{n}_{j}.hex').write_text(''.join(f'{int(v)&255:02x}\n' for v in arr.ravel()))
    (out/'test_predictions.json').write_text(json.dumps([dict(id=r[2],prediction=select(h),truth=r[1]) for r,h in zip(test,tq)]))
    (out/'validation_report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2),flush=True)
if __name__=='__main__':main()
