"""v1.2 / 22: Validation-only localization diagnostics, never selects on test."""
import argparse,json
from pathlib import Path
import numpy as np
import tensorflow as tf
from PIL import Image,ImageDraw
import train
from export import stats,select,iou,quantize,infer

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--model',type=Path,required=True)
    ap.add_argument('--manifest',type=Path,required=True);ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--quantized',action='store_true')
    args=ap.parse_args();train.MANIFEST=args.manifest
    tf.config.threading.set_intra_op_parallelism_threads(4)
    tf.config.threading.set_inter_op_parallelism_threads(2)
    examples=train.data('val');model=tf.keras.models.load_model(args.model,compile=False)
    x=np.stack([r[0] for r in examples])[...,None].astype(np.float32)
    h=np.floor(model.predict((x-128)/128,batch_size=48,verbose=0)*256+.5).astype(np.int32)
    candidates=[stats(h,examples,t) for t in [-768,-512,-384,-256,-128,0,128,256,384,512,768,1024]]
    report=dict(version='v1.2',split='val',model=str(args.model),manifest=str(args.manifest),candidates=candidates)
    args.out.mkdir(parents=True,exist_ok=True)
    if args.quantized:
        training=train.data('train');rng=np.random.default_rng(1202)
        idx=rng.choice(len(training),min(480,len(training)),replace=False)
        calibration=np.stack([training[i][0] for i in idx])[...,None].astype(np.float32)
        layers=quantize(model,calibration)
        q=np.concatenate([infer(x[i:i+32].astype(np.uint8),layers) for i in range(0,len(x),32)])
        report['int8_candidates']=[stats(q,examples,t) for t in [-768,-512,-384,-256,-128,0,128,256,384,512,768,1024]]
        report['quantized_weight_bytes']=sum(len(l['weights']) for l in layers)
        (args.out/'experimental_int8.json').write_text(json.dumps(dict(version='v1.2',experimental=True,deployment_approved=False,layers=layers)))
    (args.out/'validation_localization.json').write_text(json.dumps(report,indent=2))
    canvas=Image.new('RGB',(1280,900));n=0
    for (im,boxes,uid),head in zip(examples,h):
        if not boxes:continue
        pic=Image.fromarray(im).convert('RGB').resize((320,180));d=ImageDraw.Draw(pic)
        for x,y,w,hh,*_ in boxes:d.rectangle((x*320,y*180,(x+w)*320,(y+hh)*180),outline='lime',width=2)
        p=select(head);x,y,w,hh=p['box'];d.rectangle((x*320,y*180,(x+w)*320,(y+hh)*180),outline='red',width=2)
        d.text((2,2),f"{n} score {p['score']}",fill='yellow');canvas.paste(pic,((n%4)*320,(n//4)*180));n+=1
        if n==20:break
    canvas.save(args.out/'diagnostic.jpg')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
