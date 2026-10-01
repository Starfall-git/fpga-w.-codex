"""v1.1 / 1: Download a bounded HaGRID subset and recover original subject splits.

Images are fetched from a public mirror. Labels, boxes and user_id come from
the original HaGRIDv2 annotations, not the mirror's random split/license claim.
Only cropped 128px grayscale images are stored; original image SHA256 is logged.
"""
import csv
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import io
import json
from pathlib import Path
import time
import urllib.request
import zipfile
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
MIRROR = "https://huggingface.co/datasets/ntsrigaud/hagrid-subset/resolve/main/"
ANNOTATIONS = "https://rndml-team-cv.obs.ru-moscow-1.hc.sbercloud.ru/datasets/hagrid_v2/annotations_with_landmarks/annotations.zip"
LABELS = ["fist", "peace", "palm", "ok", "like", "no_gesture"]


def fetch(url, headers=None):
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers or {}), timeout=90) as r:
                if headers and "Range" in headers and r.status != 206:
                    raise RuntimeError("Server ignored range request")
                return r.read()
        except Exception:
            if attempt == 4: raise
            time.sleep(1 + attempt)


class RemoteZip(io.RawIOBase):
    def __init__(self):
        self.pos = 0
        with urllib.request.urlopen(urllib.request.Request(ANNOTATIONS, method="HEAD"), timeout=30) as r:
            self.size = int(r.headers["Content-Length"])

    def seekable(self): return True
    def tell(self): return self.pos
    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else self.pos + offset if whence == 1 else self.size + offset
        return self.pos
    def read(self, size=-1):
        if size < 0: size = self.size - self.pos
        if size == 0: return b""
        raw = fetch(ANNOTATIONS, {"Range": f"bytes={self.pos}-{min(self.size, self.pos+size)-1}"})
        self.pos += len(raw)
        return raw


def source_index():
    DATA.mkdir(exist_ok=True)
    table = DATA / "mirror_annotations.csv"
    if not table.exists(): table.write_bytes(fetch(MIRROR + "annotations.csv"))
    rows = [r for r in csv.DictReader(table.read_text().splitlines()) if r["label"] in LABELS]
    ids = {Path(r["image_path"]).stem for r in rows}
    index_file = DATA / "original_annotations.json"
    if index_file.exists(): return rows, json.loads(index_file.read_text())
    original = {}
    with zipfile.ZipFile(RemoteZip()) as archive:
        for split in ("train", "val", "test"):
            for label in LABELS:
                name = f"annotations/{split}/{label}.json"
                raw = archive.read(name)
                annotated = json.loads(raw)
                selected = 0
                for identifier, item in annotated.items():
                    if identifier in ids:
                        original[identifier] = {k: item[k] for k in ("bboxes", "labels", "user_id")}
                        original[identifier]["split"] = split
                        selected += 1
                print(name, "matched", selected, flush=True)
                del annotated, raw
    index_file.write_text(json.dumps(original), encoding="utf-8")
    return rows, original


def crop_square(image, box):
    w, h = image.size
    x, y, bw, bh = box
    cx, cy = (x+bw/2)*w, (y+bh/2)*h
    side = max(bw*w, bh*h)*1.45
    left, top = int(cx-side/2), int(cy-side/2)
    side = max(8, int(side))
    return image.crop((left, top, left+side, top+side)).resize((128,128), Image.Resampling.BOX)


def process(row, ann):
    identifier = Path(row["image_path"]).stem
    record_file = DATA / "records" / (identifier + ".json")
    if record_file.exists(): return json.loads(record_file.read_text())
    raw = fetch(MIRROR + row["image_path"])
    image = ImageOps.exif_transpose(Image.open(io.BytesIO(raw))).convert("L")
    entries = []
    for i, (box, label) in enumerate(zip(ann["bboxes"], ann["labels"])):
        if label not in LABELS: continue
        filename = f"{ann['split']}/{label}/{identifier}_{i}.png"
        path = DATA / "crops" / filename
        path.parent.mkdir(exist_ok=True, parents=True)
        crop_square(image, box).save(path)
        entries.append(dict(path=filename, label=label, split=ann["split"],
                            user_id=ann["user_id"], source_id=identifier,
                            source_url=MIRROR+row["image_path"],
                            source_sha256=hashlib.sha256(raw).hexdigest()))
    # Background negatives from image corners only if no annotated hand overlaps.
    w,h=image.size
    side=min(w,h)//3
    for j,(left,top) in enumerate(((0,0),(w-side,h-side))):
        overlap=any(left < (b[0]+b[2])*w and left+side > b[0]*w and
                    top < (b[1]+b[3])*h and top+side > b[1]*h for b in ann['bboxes'])
        if not overlap and int(identifier.replace('-','')[:8],16)%4==0:
            filename=f"{ann['split']}/no_gesture/{identifier}_bg{j}.png"
            path=DATA/'crops'/filename;path.parent.mkdir(exist_ok=True,parents=True)
            image.crop((left,top,left+side,top+side)).resize((128,128),Image.Resampling.BOX).save(path)
            entries.append(dict(path=filename,label='no_gesture',split=ann['split'],
                                user_id=ann['user_id'],source_id=identifier,
                                source_url=MIRROR+row['image_path'],source_sha256=hashlib.sha256(raw).hexdigest()))
    record_file.write_text(json.dumps(entries),encoding='utf-8')
    return entries


def main():
    rows, original = source_index()
    (DATA/'records').mkdir(exist_ok=True)
    selected = [r for r in rows if Path(r['image_path']).stem in original]
    manifest=[]; failures=[]
    with ThreadPoolExecutor(max_workers=10) as pool:
        futures={pool.submit(process,r,original[Path(r['image_path']).stem]):r for r in selected}
        for count,future in enumerate(as_completed(futures),1):
            try: manifest.extend(future.result())
            except Exception as e: failures.append(dict(row=futures[future],error=str(e)))
            if count%100==0:print('downloaded',count,'/',len(selected),'crops',len(manifest),'errors',len(failures),flush=True)
    # v1.1 / 25: Identical source bytes can have different IDs/subjects.
    # Drop all derivatives of every cross-split hash, independent of labels.
    hash_splits={}
    for r in manifest:hash_splits.setdefault(r['source_sha256'],set()).add(r['split'])
    blocked={h for h,splits in hash_splits.items() if len(splits)>1}
    excluded=[r for r in manifest if r['source_sha256'] in blocked]
    (DATA/'excluded_cross_split.json').write_text(json.dumps(excluded,indent=2))
    manifest=[r for r in manifest if r['source_sha256'] not in blocked]
    manifest.sort(key=lambda r:r['path'])
    subjects={s:{r['user_id'] for r in manifest if r['split']==s} for s in ('train','val','test')}
    if any(subjects[a]&subjects[b] for a,b in [('train','val'),('train','test'),('val','test')]):
        raise RuntimeError('Original subject splits overlap; refuse training')
    (DATA/'manifest.json').write_text(json.dumps(manifest),encoding='utf-8')
    (DATA/'failures.json').write_text(json.dumps(failures),encoding='utf-8')
    counts={s:{l:sum(r['split']==s and r['label']==l for r in manifest) for l in LABELS} for s in subjects}
    (DATA/'summary.json').write_text(json.dumps(dict(counts=counts,subjects={s:len(v) for s,v in subjects.items()},failures=len(failures)),indent=2))
    print(json.dumps(counts,indent=2),flush=True)


if __name__=='__main__': main()
