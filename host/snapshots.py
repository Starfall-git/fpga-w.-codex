"""V0.15: local image warehouse/editor; UART pixel transport removed.
Images will be supplied by the HDMI capture interface, independently of DDR IDs.
"""
from datetime import datetime, timezone
from pathlib import Path
import json
import os
import uuid
from PIL import Image, ImageDraw, ImageOps, ImageFont, ImageChops
import copy, io, base64, hashlib, math


class FrameStore:
    """Each entry is an atomically published PNG, with optional JSON metadata.
    No central mutable index: interrupted saves cannot corrupt other frames.
    """
    def __init__(self, root=None):
        self.root = Path(root or (Path.home() / 'Pictures' / 'VF-Ti60-FrozenFrames'))
        self.root.mkdir(parents=True, exist_ok=True)

    def save(self, image, parent=None, simulated=None):
        if simulated is None:
            simulated = False
            if parent:
                try:
                    metadata = self.root / (Path(parent).stem + '.json')
                    simulated = bool(json.loads(metadata.read_text(encoding='utf-8')).get('simulated'))
                except (OSError, ValueError):
                    pass
        key = datetime.now().strftime('%Y%m%d-%H%M%S-') + uuid.uuid4().hex[:10]
        path = self.root / (key + '.png')
        temp = self.root / (key + '.tmp')
        image.convert('RGB').save(temp, format='PNG')
        os.replace(temp, path)
        meta = dict(created=datetime.now(timezone.utc).isoformat(), parent=parent, simulated=simulated)
        path.with_suffix('.json').write_text(json.dumps(meta, ensure_ascii=False), encoding='utf-8')
        return path

    def entries(self):
        return sorted(self.root.glob('*.png'), reverse=True)

    def load(self, path):
        path = Path(path).resolve()
        if path.parent != self.root.resolve(): raise ValueError('不是仓库中的图片')
        with Image.open(path) as source: return source.convert('RGB')


    # V0.18 / 86: flattened PNG plus editable annotations, bound by image hash.
    def replace_document(self, path, document):
        path=Path(path).resolve()
        if path.parent!=self.root.resolve():raise ValueError('不是仓库中的图片')
        data=io.BytesIO();document.image.save(data,format='PNG');raw=data.getvalue()
        metadata=document.serialize();metadata['sha256']=hashlib.sha256(raw).hexdigest()
        edit=path.with_suffix('.edit.json');tmp=path.with_suffix('.edit.tmp')
        tmp.write_text(json.dumps(metadata,ensure_ascii=False),encoding='utf-8');os.replace(tmp,edit)
        temp=path.with_suffix('.tmp');temp.write_bytes(raw);os.replace(temp,path)

    def document(self,path):
        image=self.load(path);doc=ImageDocument(image)
        try:
            path=Path(path);meta=json.loads(path.with_suffix('.edit.json').read_text(encoding='utf-8'))
            if meta['sha256']==hashlib.sha256(path.read_bytes()).hexdigest():doc=ImageDocument.deserialize(meta)
        except (OSError,ValueError,KeyError):pass
        return doc


class ImageDocument:
    """V0.18: immutable base snapshots and independent editable annotation objects.
    Erasure affects annotation alpha only; text and camera pixels are protected.
    Geometry is replayed on each object so text remains editable after crop/flip.
    """
    def __init__(self,image):
        self.base=image.convert('RGB').copy();self.original=self.base
        self.objects=[];self.history=[]

    def checkpoint(self):self.history.append((self.base,copy.deepcopy(self.objects)))
    def undo(self):
        if self.history:self.base,self.objects=self.history.pop()
    def reset(self):
        self.checkpoint();self.base=self.original;self.objects=[]

    @staticmethod
    def font(size):
        for name in ('C:/Windows/Fonts/msyh.ttc','C:/Windows/Fonts/simhei.ttf','DejaVuSans.ttf'):
            try:return ImageFont.truetype(name,max(1,int(size)))
            except OSError:pass
        return ImageFont.load_default()

    def layer(self,obj):
        im=Image.new('RGBA',tuple(obj['size']));draw=ImageDraw.Draw(im)
        pts=[tuple(p) for p in obj['points']];kind=obj['kind'];color=obj['color'];width=max(1,round(obj['width']))
        if kind=='text':draw.text(pts[0],obj['text'],font=self.font(obj['width']),fill=color)
        elif kind in ('pen','curve','line','arrow'):
            if len(pts)==1:draw.ellipse((pts[0][0]-width/2,pts[0][1]-width/2,pts[0][0]+width/2,pts[0][1]+width/2),fill=color)
            else:draw.line(pts,fill=color,width=width,joint='curve')
            if kind=='arrow' and len(pts)>1:
                x,y=pts[-1];dx,dy=x-pts[0][0],y-pts[0][1];length=math.hypot(dx,dy)
                if length:
                    ux,uy=dx/length,dy/length;a=max(12,width*4)
                    draw.polygon([(x,y),(x-a*ux+a*.45*uy,y-a*uy-a*.45*ux),(x-a*ux-a*.45*uy,y-a*uy+a*.45*ux)],fill=color)
        elif kind=='polygon':draw.line(pts+[pts[0]],fill=color,width=width,joint='curve')
        else:
            x0,x1=sorted((pts[0][0],pts[-1][0]));y0,y1=sorted((pts[0][1],pts[-1][1]))
            if kind=='rectangle':draw.rectangle((x0,y0,x1,y1),outline=color,width=width)
            elif kind=='ellipse':draw.ellipse((x0,y0,x1,y1),outline=color,width=width)
            elif kind=='triangle':draw.line([((x0+x1)/2,y0),(x1,y1),(x0,y1),((x0+x1)/2,y0)],fill=color,width=width,joint='curve')
            elif kind=='diamond':draw.line([((x0+x1)/2,y0),(x1,(y0+y1)/2),((x0+x1)/2,y1),(x0,(y0+y1)/2),((x0+x1)/2,y0)],fill=color,width=width,joint='curve')
        for op,arg in obj['ops']:
            if op=='crop':im=im.crop(tuple(arg))
            elif op=='flip':im=ImageOps.mirror(im) if arg else ImageOps.flip(im)
            elif op=='resize':im=im.resize(tuple(arg),Image.Resampling.LANCZOS)
            elif op=='erase':
                points,w=arg;alpha=im.getchannel('A');d=ImageDraw.Draw(alpha)
                points=[tuple(p) for p in points]
                if len(points)>1:d.line(points,fill=0,width=w,joint='curve')
                for x,y in points:d.ellipse((x-w/2,y-w/2,x+w/2,y+w/2),fill=0)
                im.putalpha(alpha)
        return im

    @property
    def image(self):
        im=self.base.convert('RGBA')
        for obj in self.objects:im.alpha_composite(self.layer(obj))
        return im.convert('RGB')

    def add(self,kind,points,color,width,text='',checkpoint=True):
        if checkpoint:self.checkpoint()
        self.objects.append(dict(kind=kind,points=list(points),color=color,width=width,text=text,size=self.base.size,ops=[]))
    def stroke(self,points,color,width):self.add('pen',points,color,width,checkpoint=False)
    def text_at(self,point):
        x,y=point
        for i in reversed(range(len(self.objects))):
            obj=self.objects[i]
            if obj['kind']=='text':
                box=self.layer(obj).getbbox()
                if box and box[0]<=x<=box[2] and box[1]<=y<=box[3]:return i
        return None
    def edit_text(self,index,text):
        self.checkpoint();self.objects[index]['text']=text
    def erase(self,points,width,whole=False):
        self.checkpoint();mask=Image.new('L',self.base.size);d=ImageDraw.Draw(mask)
        points=[tuple(p) for p in points]
        if len(points)>1:d.line(points,fill=255,width=width)
        for x,y in points:d.ellipse((x-width/2,y-width/2,x+width/2,y+width/2),fill=255)
        if whole:
            for index in reversed(range(len(self.objects))):
                obj=self.objects[index]
                if obj['kind']!='text' and ImageChops.multiply(self.layer(obj).getchannel('A'),mask).getbbox():
                    del self.objects[index];break
            return
        keep=[]
        for obj in self.objects:
            hit=obj['kind']!='text' and ImageChops.multiply(self.layer(obj).getchannel('A'),mask).getbbox()
            if hit and whole:continue
            if hit:obj['ops'].append(('erase',(points,width)))
            keep.append(obj)
        self.objects=keep

    def transform(self,kind,arg,image):
        self.checkpoint();self.base=image
        for obj in self.objects:obj['ops'].append((kind,arg))
    def crop(self,box):
        x0,y0,x1,y1=map(int,box)
        box=(max(0,min(x0,x1)),max(0,min(y0,y1)),min(self.base.width,max(x0,x1)),min(self.base.height,max(y0,y1)))
        if box[2]<=box[0] or box[3]<=box[1]:raise ValueError('请拖动选择有效裁剪区域')
        self.transform('crop',box,self.base.crop(box))
    def flip(self,horizontal):self.transform('flip',horizontal,ImageOps.mirror(self.base) if horizontal else ImageOps.flip(self.base))
    def resize(self,percent):
        value=float(percent)
        if not 10<=value<=500:raise ValueError('图片缩放范围10%～500%')
        size=tuple(max(1,round(v*value/100)) for v in self.base.size)
        if size[0]*size[1]>40_000_000:raise ValueError('缩放后超过4000万像素，请降低倍率')
        self.transform('resize',size,self.base.resize(size,Image.Resampling.LANCZOS))
    def serialize(self):
        def png(im):
            f=io.BytesIO();im.save(f,format='PNG');return base64.b64encode(f.getvalue()).decode('ascii')
        return dict(version=1,base=png(self.base),original=png(self.original),objects=self.objects)
    @classmethod
    def deserialize(cls,data):
        def load(s):return Image.open(io.BytesIO(base64.b64decode(s))).convert('RGB')
        doc=cls(load(data['original']));doc.base=load(data['base']);doc.objects=data['objects'];return doc
