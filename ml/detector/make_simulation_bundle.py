"""v1.2 / 26: Validation-only functional RTL fixture, explicitly not a release.
A permissive detector threshold exercises data flow, not application accuracy.
"""
import os
os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL','2')
import argparse,json,sys,hashlib
from pathlib import Path
import numpy as np
import tensorflow as tf
from export import ROOT,infer,select,iou
from train import data
from evaluate_pipeline import crop_pixels,classification
from export_v1_1 import integer_infer
LABELS=['fist','peace','palm','ok','like','no_gesture']
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--quantized',type=Path,required=True);ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
 tf.config.threading.set_intra_op_parallelism_threads(4);tf.config.threading.set_inter_op_parallelism_threads(2)
 if not a.out.resolve().is_relative_to(ROOT):raise ValueError('Experiment must stay in detector directory')
 layers=json.loads(a.quantized.read_text())['layers'];assert len(layers)==5
 rom=a.out/'src/cnn/rom_v1_2';vd=a.out/'ml/detector/artifacts/vectors';rom.mkdir(parents=True,exist_ok=True);vd.mkdir(parents=True,exist_ok=True)
 weights=[];bias=[];shifts=[]
 for l in layers:
  w=np.array(l['weights'],np.int8).reshape(l['shape']);weights.extend(w.transpose(3,0,1,2).ravel());bias.extend(l['bias']);shifts.extend(l['shift'] if isinstance(l['shift'],list) else [l['shift']])
 previous=ROOT.parents[1]/'src/cnn/rom'
 for name,values,mask,digits in [('weights',weights,255,2),('biases',bias,0xffffffff,8),('shifts',shifts,255,2)]:
  (rom/f'{name}.hex').write_text((previous/f'{name}.hex').read_text()+''.join(f'{int(v)&mask:0{digits}x}\n' for v in values))
 threshold=-256;(rom/'hand_threshold.hex').write_text(f'{threshold&65535:04x}\n')
 val=data('val');images=[r[0][...,None] for r in val[:4]]+[np.zeros((144,256,1),np.uint8),np.full((144,256,1),255,np.uint8)]
 for n,im in enumerate(images):
  q,trace=infer(im[None],layers,keep=True)
  (vd/f'input_{n}.hex').write_text(''.join(f'{int(v):02x}\n' for v in im.ravel()))
  (vd/f'head_{n}.hex').write_text(''.join(f'{int(v)&65535:04x}\n' for v in q.ravel()))
  for j,arr in enumerate(trace[:-1]):(vd/f'layer_{n}_{j}.hex').write_text(''.join(f'{int(v)&255:02x}\n' for v in arr.ravel()))
 cl=json.loads((ROOT.parent/'gesture/artifacts/model_int8.json').read_text())['layers'];fixture=None
 for im,boxes,uid in val:
  if not boxes:continue
  dh=infer(im[None,...,None],layers);p=select(dh[0])
  if not p['valid'] or p['score']<threshold:continue
  match=max(boxes,key=lambda b:iou(p['box'],b))
  if iou(p['box'],match)<.5:continue
  full=np.repeat(np.repeat(im,5,axis=0),5,axis=1)
  q=integer_infer(crop_pixels(full,p['roi'])[None],cl)[0];cid=classification(q,768)
  if cid==255 or LABELS[cid]!=match[4]:continue
  for name,values,digits,mask in [('auto_frame',im.ravel(),2,255),('auto_head',dh.ravel(),4,65535),('auto_scores',q.ravel(),4,65535),('auto_info',[*p['roi'],cid],4,65535)]:
   (vd/f'{name}.hex').write_text(''.join(f'{int(v)&mask:0{digits}x}\n' for v in values))
  fixture=dict(source_id=uid,split='val',roi=p['roi'],class_id=cid,synthetic_upsampling='256x144 replicated5x5; functional fixture only');break
 if fixture is None:raise RuntimeError('No correctly localized/classified fixture')
 report=dict(version='v1.2',experimental=True,deployment_approved=False,hardware_tested=False,threshold_note='Permissive -256 for functional verification, not a selected deployment threshold',quantized_sha256=hashlib.sha256(a.quantized.read_bytes()).hexdigest(),fixture=fixture)
 (a.out/'manifest.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
if __name__=='__main__':main()
