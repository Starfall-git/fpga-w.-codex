"""V0.15: local image warehouse/editor; UART pixel transport removed.
Images will be supplied by the HDMI capture interface, independently of DDR IDs.
"""
from datetime import datetime, timezone
from pathlib import Path
import json
import os
import uuid
from PIL import Image, ImageDraw, ImageOps


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


class ImageDocument:
    """Edits always operate in full-resolution image coordinates."""
    def __init__(self, image):
        self.image = image.convert('RGB').copy()
        self.history = []

    def checkpoint(self):
        self.history.append(self.image.copy())
        self.history = self.history[-12:]

    def undo(self):
        if self.history: self.image = self.history.pop()

    def crop(self, box):
        x0, y0, x1, y1 = map(int, box)
        box = (max(0, min(x0,x1)), max(0,min(y0,y1)), min(self.image.width,max(x0,x1)), min(self.image.height,max(y0,y1)))
        if box[2] <= box[0] or box[3] <= box[1]: raise ValueError('请拖动选择有效裁剪区域')
        self.checkpoint(); self.image = self.image.crop(box)

    def flip(self, horizontal):
        self.checkpoint()
        self.image = ImageOps.mirror(self.image) if horizontal else ImageOps.flip(self.image)

    def resize(self, percent):
        value = float(percent)
        if not 10 <= value <= 500: raise ValueError('图片缩放范围10%～500%')
        size = tuple(max(1, round(v*value/100)) for v in self.image.size)
        if size[0]*size[1] > 40_000_000: raise ValueError('缩放后超过4000万像素，请降低倍率')
        self.checkpoint(); self.image = self.image.resize(size, Image.Resampling.LANCZOS)

    def stroke(self, points, color, width):
        if len(points) >= 2: ImageDraw.Draw(self.image).line(points, fill=color, width=width, joint='curve')
