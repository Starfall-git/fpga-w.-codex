"""v1.2 / 19: Evaluate actual detector-selected crops and generate a math fixture.
The end-to-end report uses held-out full frames; the HDL fixture uses an explicitly
upsampled validation image so every camera pixel is independently reproducible.
"""
import os,sys,json
from pathlib import Path
import numpy as np
from PIL import Image
from export import ROOT,infer,select,iou
sys.path.insert(0,str(ROOT.parent/'gesture'))
from export_v1_1 import integer_infer
LABELS=['fist','peace','palm','ok','like','no_gesture']

def crop_pixels(im,roi):
    x,y,side=roi;s=side//64
    patch=im[y:y+side,x:x+side].astype(np.uint32)
    return ((patch.reshape(64,s,64,s).sum(axis=(1,3))+(s*s)//2)//(s*s)).astype(np.uint8)[...,None]

def classification(scores,threshold):
    cid=int(np.argmax(scores));ordered=np.sort(scores)
    return cid if cid<5 and ordered[-1]-ordered[-2]>=threshold else 255

def main():
    out=ROOT/'artifacts';layers=json.loads((out/'model_int8.json').read_text())['layers']
    cl=json.loads((ROOT.parent/'gesture/artifacts/model_int8.json').read_text())['layers']
    det_threshold=json.loads((out/'validation_report.json').read_text())['selected']['threshold_q8']
    class_threshold=json.loads((ROOT.parent/'gesture/artifacts/validation_report.json').read_text())['threshold_q8']
    rows=json.loads((ROOT/'data/manifest.json').read_text())
    predictions={r['id']:r['prediction'] for r in json.loads((out/'test_predictions.json').read_text())}
    records=[];crops=[];indices=[]
    for r in rows:
        if r['split']!='test':continue
        p=predictions[r['id']];target=any(b[4] in LABELS[:5] for b in r['boxes'])
        record=dict(id=r['id'],has_target=target,detected=p['valid'] and p['score']>=det_threshold,roi=p['roi'],class_id=255,matched_label=None,iou=0,correct=False)
        if record['detected']:
            if r['boxes']:
                match=max(r['boxes'],key=lambda b:iou(p['box'],b));record['matched_label']=match[4];record['iou']=iou(p['box'],match)
            im=np.array(Image.open(ROOT/'data'/r['path']))
            crops.append(crop_pixels(im,p['roi']));indices.append(len(records))
        records.append(record)
    if crops:
        scores=integer_infer(np.stack(crops),cl)
        for i,q in zip(indices,scores):
            r=records[i];r['class_id']=classification(q,class_threshold)
            r['correct']=r['class_id']<5 and LABELS[r['class_id']]==r['matched_label'] and r['iou']>=.5
    accepted=sum(r['class_id']<5 for r in records);correct=sum(r['correct'] for r in records);targets=sum(r['has_target'] for r in records)
    report=dict(version='v1.2',full_test_frames=len(records),target_gesture_frames=targets,detected_frames=sum(r['detected'] for r in records),accepted_gestures=accepted,correct_class_and_iou50=correct,accepted_precision=correct/max(accepted,1),target_frame_recall=correct/max(targets,1),note='Single frozen images; does not measure next-frame motion or two-result confirmation.')
    (out/'pipeline_report.json').write_text(json.dumps(report,indent=2));(out/'pipeline_predictions.json').write_text(json.dumps(records))
    # Fixture choice is validation-only and is not an accuracy measurement.
    from train import data
    vd=out/'vectors';fixture=None
    for im,boxes,uid in data('val'):
        if not boxes:continue
        dh=infer(im[None,...,None],layers);p=select(dh[0])
        if not p['valid'] or p['score']<det_threshold:continue
        full=np.repeat(np.repeat(im,5,axis=0),5,axis=1)
        q=integer_infer(crop_pixels(full,p['roi'])[None],cl)[0];cid=classification(q,class_threshold)
        if cid==255:continue
        (vd/'auto_frame.hex').write_text(''.join(f'{int(v):02x}\n' for v in im.ravel()))
        (vd/'auto_head.hex').write_text(''.join(f'{int(v)&65535:04x}\n' for v in dh.ravel()))
        (vd/'auto_scores.hex').write_text(''.join(f'{int(v)&65535:04x}\n' for v in q.ravel()))
        (vd/'auto_info.hex').write_text(''.join(f'{int(v):04x}\n' for v in [*p['roi'],cid]))
        fixture=dict(source_id=uid,split='val',roi=p['roi'],class_id=cid,synthetic_upsampling='256x144 image replicated5x5, for exact pixel-stream verification only')
        break
    if fixture is None:raise RuntimeError('No accepted validation fixture; inspect model before integration')
    (vd/'auto_description.json').write_text(json.dumps(fixture,indent=2))
    print(json.dumps(report,indent=2));print('FIXTURE',fixture,flush=True)
if __name__=='__main__':main()
