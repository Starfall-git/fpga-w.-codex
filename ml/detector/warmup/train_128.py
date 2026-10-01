"""v1.2 / 2: Small full-frame center/box detector, 128x72 gray -> 16x9x5.
Inspired by center-point detection; not the original CenterNet architecture.
All hand annotations (including no_gesture) are detection positives.
"""
import os
os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL','2')
import json,argparse,hashlib
from pathlib import Path
import numpy as np
from PIL import Image
import tensorflow as tf
ROOT=Path(__file__).resolve().parent
MANIFEST=ROOT/'data/manifest.json'

def encode(boxes):
    y=np.zeros((9,16,6),np.float32)
    yy,xx=np.mgrid[:9,:16]
    for x,z,w,h,*_ in boxes:
        cx=(x+w/2)*16;cy=(z+h/2)*9
        ix=int(np.clip(cx,0,15));iy=int(np.clip(cy,0,8))
        heat=np.exp(-((xx-ix)**2+(yy-iy)**2)/2.)
        y[...,0]=np.maximum(y[...,0],heat)
        # If two centers occupy one cell, prioritize the larger hand.
        if w*h>=y[iy,ix,3]*y[iy,ix,4]:y[iy,ix,1:]=[cx-ix,cy-iy,w,h,1]
    return y

def data(split):
    items=json.loads(MANIFEST.read_text())
    for key in ('user_id','id','source_sha256'):
        groups={}
        for r in items:groups.setdefault(r[key],set()).add(r['split'])
        if any(len(s)>1 for s in groups.values()):raise ValueError('Cross-split '+key)
    selected=[r for r in items if r['split']==split]
    examples=[(np.array(Image.open(ROOT/'data'/r['path']).resize((128,72),Image.Resampling.BOX)),r['boxes'],r['id']) for r in selected]
    # Only background crops explicitly identified as not overlapping any hand.
    original=json.loads((ROOT.parent/'gesture/data/manifest.json').read_text())
    for r in original:
        if r['split']==split and '_bg' in r['path']:
            im=np.array(Image.open(ROOT.parent/'gesture/data/crops'/r['path']).resize((128,72),Image.Resampling.BOX))
            examples.append((im,[],r['path']))
    return examples

def build():
    x=inputs=tf.keras.Input((72,128,1),name='gray')
    for i,c in enumerate((8,16,24,32)):
        x=tf.keras.layers.Conv2D(c,3,strides=2 if i<3 else 1,dilation_rate=1 if i<3 else 2,padding='same',use_bias=False,name=f'conv{i}')(x)
        x=tf.keras.layers.BatchNormalization(name=f'bn{i}')(x)
        x=tf.keras.layers.ReLU(name=f'relu{i}')(x)
    outputs=tf.keras.layers.Conv2D(5,1,name='head',bias_initializer=tf.keras.initializers.Constant([-2.19,.5,.5,.15,.25]))(x)
    return tf.keras.Model(inputs,outputs,name='hand_detector_v1_2')

@tf.keras.utils.register_keras_serializable(package='gesture')
def detector_loss(y,p):
    target=y[...,0];prob=tf.clip_by_value(tf.sigmoid(p[...,0]),1e-5,1-1e-5)
    pos=tf.cast(target>=.999,tf.float32);neg=1-pos
    denom=tf.maximum(tf.reduce_sum(pos,axis=(1,2)),1.)
    focal=-pos*(1-prob)**2*tf.math.log(prob)-neg*(1-target)**4*prob**2*tf.math.log(1-prob)
    d=tf.abs(p[...,1:5]-y[...,1:5]);smooth=tf.where(d<.1,5*d*d,d-.05)
    regression=tf.reduce_sum(smooth*tf.constant([1.,1.,4.,4.]),axis=-1)*y[...,5]
    return tf.reduce_mean(tf.reduce_sum(focal+2*regression,axis=(1,2))/denom)

def augment(im,boxes,rng):
    scale=rng.uniform(.7,1.3);dx=rng.uniform(-.30,.30)*128;dy=rng.uniform(-.25,.25)*72
    tx=(128-128*scale)/2+dx;ty=(72-72*scale)/2+dy
    im=np.asarray(Image.fromarray(im).transform((128,72),Image.Transform.AFFINE,(1/scale,0,-tx/scale,0,1/scale,-ty/scale),resample=Image.Resampling.BILINEAR,fillcolor=128)).copy()
    transformed=[]
    for x,y,w,h,*rest in boxes:
        x1=np.clip(x*scale+tx/128,0,1);x2=np.clip((x+w)*scale+tx/128,0,1)
        y1=np.clip(y*scale+ty/72,0,1);y2=np.clip((y+h)*scale+ty/72,0,1)
        if (x2-x1)*128>=3 and (y2-y1)*72>=3:transformed.append([x1,y1,x2-x1,y2-y1,*rest])
    if rng.random()<.5:
        im=im[:,::-1].copy()
        transformed=[[1-x-w,y,w,h,*rest] for x,y,w,h,*rest in transformed]
    im=np.clip(im.astype(np.float32)*rng.uniform(.75,1.25)+rng.uniform(-20,20),0,255)
    return im,transformed

def main():
    global MANIFEST
    parser=argparse.ArgumentParser();parser.add_argument('--epochs',type=int,default=100)
    parser.add_argument('--manifest',type=Path,default=MANIFEST);parser.add_argument('--out',type=Path,default=ROOT/'artifacts')
    parser.add_argument('--init',type=Path);args=parser.parse_args();MANIFEST=args.manifest
    tf.keras.utils.set_random_seed(1202)
    tf.config.threading.set_intra_op_parallelism_threads(8);tf.config.threading.set_inter_op_parallelism_threads(2)
    train=data('train');val=data('val');print('train',len(train),'val',len(val),flush=True)
    rng=np.random.default_rng(1202)
    def generator():
        while True:
            for i in rng.permutation(len(train)):
                im,b,_=train[i];im,b=augment(im,b,rng)
                yield ((im.astype(np.float32)-128)/128)[...,None],encode(b)
    opts=tf.data.Options();opts.threading.private_threadpool_size=4
    ds=tf.data.Dataset.from_generator(generator,output_signature=(tf.TensorSpec((72,128,1),tf.float32),tf.TensorSpec((9,16,6),tf.float32))).batch(48).prefetch(2).with_options(opts)
    vx=np.stack([i for i,b,_ in val])[...,None].astype(np.float32);vy=np.stack([encode(b) for i,b,_ in val])
    vd=tf.data.Dataset.from_tensor_slices(((vx-128)/128,vy)).batch(48).with_options(opts)
    model=tf.keras.models.load_model(args.init,compile=False) if args.init else build();model.summary();model.compile(optimizer=tf.keras.optimizers.Adam(.002),loss=detector_loss)
    out=args.out;out.mkdir(parents=True,exist_ok=True)
    cb=[tf.keras.callbacks.ModelCheckpoint(str(out/'best.keras'),monitor='val_loss',save_best_only=True),tf.keras.callbacks.ReduceLROnPlateau(monitor='val_loss',factor=.5,patience=8,min_lr=5e-5),tf.keras.callbacks.EarlyStopping(monitor='val_loss',patience=24),tf.keras.callbacks.CSVLogger(str(out/'training.csv'))]
    history=model.fit(ds,steps_per_epoch=(len(train)+47)//48,validation_data=vd,epochs=args.epochs,callbacks=cb,verbose=2)
    (out/'training_report.json').write_text(json.dumps(dict(version='v1.2',dataset_sha256=hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),initial_model=str(args.init) if args.init else None,seed=1202,epochs=len(history.history['loss']),train=len(train),validation=len(val),best_val_loss=min(history.history['val_loss']),tensorflow=tf.__version__,model_sha256=hashlib.sha256((out/'best.keras').read_bytes()).hexdigest()),indent=2))
if __name__=='__main__':main()
