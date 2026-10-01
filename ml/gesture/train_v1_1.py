"""v1.1 / 2: Train an ordinary-convolution grayscale CNN for the shared RTL MAC.

Uses HaGRID's original subject-disjoint train/val/test. The test split is not
used for model selection. Export/quantization are separate, reproducible steps.
"""
import os
os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL','2')
os.environ.setdefault('TF_ENABLE_ONEDNN_OPTS','1')
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
import tensorflow as tf

ROOT=Path(__file__).resolve().parent
LABELS=['fist','peace','palm','ok','like','no_gesture']


def load_split(split):
    manifest=json.loads((ROOT/'data/manifest.json').read_text())
    # v1.1 / 25: Refuse source-byte or subject leakage even when called directly.
    for key in ('user_id','source_id','source_sha256'):
        groups={}
        for r in manifest:groups.setdefault(r[key],set()).add(r['split'])
        if any(len(v)>1 for v in groups.values()):raise ValueError('Cross-split leakage: '+key)
    records=[r for r in manifest if r['split']==split]
    images=np.stack([np.asarray(Image.open(ROOT/'data/crops'/r['path']).resize((64,64),Image.Resampling.BOX)) for r in records])
    labels=np.array([LABELS.index(r['label']) for r in records],np.int32)
    return images[...,None],labels


def build():
    inputs=tf.keras.Input((64,64,1),name='gray')
    x=inputs
    for index,channels in enumerate((8,16,24,32)):
        x=tf.keras.layers.Conv2D(channels,3,strides=2,padding='same',use_bias=False,name=f'conv{index}')(x)
        x=tf.keras.layers.BatchNormalization(name=f'bn{index}')(x)
        x=tf.keras.layers.ReLU(name=f'relu{index}')(x)
    x=tf.keras.layers.Flatten(name='flatten')(x)
    x=tf.keras.layers.Dropout(0.25)(x)
    outputs=tf.keras.layers.Dense(6,name='logits')(x)
    return tf.keras.Model(inputs,outputs,name='gesture_v1_1')


def metrics(y,logits):
    predictions=np.argmax(logits,axis=1)
    confusion=np.zeros((6,6),np.int64)
    np.add.at(confusion,(y,predictions),1)
    precision=np.diag(confusion)/np.maximum(confusion.sum(0),1)
    recall=np.diag(confusion)/np.maximum(confusion.sum(1),1)
    f1=2*precision*recall/np.maximum(precision+recall,1e-9)
    return dict(accuracy=float(np.mean(y==predictions)),macro_f1=float(f1.mean()),
                recall=dict(zip(LABELS,map(float,recall))),confusion=confusion.tolist())


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--epochs',type=int,default=60)
    args=parser.parse_args()
    tf.keras.utils.set_random_seed(1101)
    tf.config.threading.set_intra_op_parallelism_threads(8)
    tf.config.threading.set_inter_op_parallelism_threads(2)
    train_x,train_y=load_split('train');val_x,val_y=load_split('val')
    print('train',train_x.shape,'val',val_x.shape,flush=True)
    augment=tf.keras.Sequential([
        tf.keras.layers.RandomFlip('horizontal'),
        tf.keras.layers.RandomRotation(0.045,fill_mode='constant',fill_value=0),
        tf.keras.layers.RandomTranslation(0.10,0.10,fill_mode='constant',fill_value=0),
        tf.keras.layers.RandomZoom((-0.12,0.12),fill_mode='constant',fill_value=0),
        tf.keras.layers.RandomContrast(0.25),
    ])
    def normalize(x,y):return (tf.cast(x,tf.float32)-128.)/128.,y
    def transform(x,y):
        x=augment(tf.cast(x,tf.float32),training=True)
        x=x+tf.random.uniform((tf.shape(x)[0],1,1,1),-24.,24.)
        return (tf.clip_by_value(x,0.,255.)-128.)/128.,y
    opts=tf.data.Options();opts.threading.private_threadpool_size=4
    training=tf.data.Dataset.from_tensor_slices((train_x,train_y)).shuffle(len(train_y),seed=1101).batch(64).map(transform,num_parallel_calls=2).prefetch(2).with_options(opts)
    validation=tf.data.Dataset.from_tensor_slices((val_x,val_y)).batch(64).map(normalize).with_options(opts)
    model=build();model.summary()
    model.compile(tf.keras.optimizers.Adam(0.002),loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),metrics=['accuracy'])
    out=ROOT/'artifacts';out.mkdir(exist_ok=True)
    counts=np.bincount(train_y,minlength=6)
    weights={i:float(len(train_y)/(6*n)) for i,n in enumerate(counts)}
    callbacks=[tf.keras.callbacks.ModelCheckpoint(str(out/'best.keras'),monitor='val_accuracy',save_best_only=True),
               tf.keras.callbacks.ReduceLROnPlateau(monitor='val_loss',factor=0.5,patience=6,min_lr=0.00005),
               tf.keras.callbacks.EarlyStopping(monitor='val_accuracy',patience=18,restore_best_weights=True),
               tf.keras.callbacks.CSVLogger(str(out/'training.csv'))]
    history=model.fit(training,validation_data=validation,epochs=args.epochs,class_weight=weights,callbacks=callbacks,verbose=2)
    model=tf.keras.models.load_model(out/'best.keras')
    report=dict(version='v1.1',labels=LABELS,seed=1101,tensorflow=tf.__version__,keras=tf.keras.__version__,
                train_count=len(train_y),val_count=len(val_y),
                model_sha256=hashlib.sha256((out/'best.keras').read_bytes()).hexdigest(),
                validation=metrics(val_y,model.predict((val_x.astype(np.float32)-128)/128,batch_size=64,verbose=0)),
                epochs=len(history.history['loss']))
    (out/'training_report.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2),flush=True)


if __name__=='__main__':main()
