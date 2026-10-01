"""v1.2 / 23: Isolated depth experiment; does not modify production ROM or RTL.
Adds a trainable identity-initialized 3x3 block before the detection head.
"""
import argparse
from pathlib import Path
import numpy as np
import tensorflow as tf
import train
ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,required=True);ap.add_argument('--out',type=Path,required=True)
a=ap.parse_args()
m=tf.keras.models.load_model(a.source,compile=False)
x=tf.keras.layers.Conv2D(32,3,padding='same',use_bias=False,name='conv4')(m.get_layer('relu3').output)
x=tf.keras.layers.BatchNormalization(name='bn4')(x)
x=tf.keras.layers.ReLU(name='relu4')(x)
x=tf.keras.layers.Conv2D(5,1,name='head_deep')(x)
n=tf.keras.Model(m.input,x,name='hand_detector_depth_experiment')
w=np.zeros((3,3,32,32),np.float32)
for i in range(32):w[1,1,i,i]=1
n.get_layer('conv4').set_weights([w])
n.get_layer('bn4').set_weights([np.full(32,np.sqrt(1.001),np.float32),np.zeros(32,np.float32),np.zeros(32,np.float32),np.ones(32,np.float32)])
n.get_layer('head_deep').set_weights(m.get_layer('head').get_weights())
a.out.parent.mkdir(parents=True,exist_ok=True);n.save(a.out)
print(n.count_params())
