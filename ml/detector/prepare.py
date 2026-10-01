"""v1.2 / 1: Recover full images and all hand boxes for spatial detection.
Original subject split and cross-split SHA exclusions are inherited from v1.1.
Keep full-frame grayscale JPEGs only, never alter classifier training data.
"""
import sys,io,json,hashlib,random,argparse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
from PIL import Image,ImageOps
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'gesture'))
from prepare_hagrid import source_index,fetch,MIRROR
ROOT=Path(__file__).resolve().parent
DATA=ROOT/'data'

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--prefetch-tail',type=int,default=0);args=parser.parse_args()
    rows,annotations=source_index()
    records=json.loads((ROOT.parent/'gesture/data/manifest.json').read_text())
    known={r['source_id']:r['source_sha256'] for r in records}
    DATA.mkdir(exist_ok=True);(DATA/'records').mkdir(exist_ok=True);(DATA/'images').mkdir(exist_ok=True)
    def one(row):
        uid=Path(row['image_path']).stem
        cache=DATA/'records'/f'{uid}.json'
        if cache.exists():return json.loads(cache.read_text())
        raw=fetch(MIRROR+row['image_path']+'?download=true')
        if hashlib.sha256(raw).hexdigest()!=known[uid]:raise ValueError('source bytes changed '+uid)
        im=ImageOps.exif_transpose(Image.open(io.BytesIO(raw))).convert('L')
        iw,ih=im.size;scale=min(1280/iw,720/ih)
        nw,nh=round(iw*scale),round(ih*scale);ox,oy=(1280-nw)//2,(720-nh)//2
        canvas=Image.new('L',(1280,720),128)
        canvas.paste(im.resize((nw,nh),Image.Resampling.BOX),(ox,oy))
        canvas.save(DATA/'images'/f'{uid}.jpg',quality=95)
        ann=annotations[uid]
        boxes=[]
        for box,label in zip(ann['bboxes'],ann['labels']):
            x,y,w,h=box
            x1=max(0,min(1280,x*nw+ox));y1=max(0,min(720,y*nh+oy))
            x2=max(x1,min(1280,(x+w)*nw+ox));y2=max(y1,min(720,(y+h)*nh+oy))
            if x2-x1>=8 and y2-y1>=8:boxes.append([x1/1280,y1/720,(x2-x1)/1280,(y2-y1)/720,label])
        item=dict(id=uid,path=f'images/{uid}.jpg',split=ann['split'],user_id=ann['user_id'],source_sha256=known[uid],boxes=boxes)
        cache.write_text(json.dumps(item));return item
    selected=[r for r in rows if Path(r['image_path']).stem in known]
    random.Random(1202).shuffle(selected)
    if args.prefetch_tail:selected=selected[-args.prefetch_tail:]
    result=[];errors=[]
    with ThreadPoolExecutor(max_workers=24 if args.prefetch_tail else 48) as pool:
        tasks={pool.submit(one,r):r for r in selected}
        for n,f in enumerate(as_completed(tasks),1):
            try:result.append(f.result())
            except Exception as e:
                errors.append(dict(row=tasks[f],error=str(e)))
                (DATA/'failures_partial.json').write_text(json.dumps(errors,indent=2))
                print('DOWNLOAD ERROR',str(e)[:160],flush=True)
            if n%100==0:print(n,'/',len(selected),'errors',len(errors),flush=True)
    if args.prefetch_tail:
        print('PREFETCH COMPLETE',len(result),'errors',len(errors),flush=True);return
    result.sort(key=lambda x:x['id'])
    (DATA/'manifest.json').write_text(json.dumps(result))
    (DATA/'failures.json').write_text(json.dumps(errors,indent=2))
    if errors:raise SystemExit('Incomplete download; rerun to resume')
    print('COMPLETE',len(result),flush=True)
if __name__=='__main__':main()
