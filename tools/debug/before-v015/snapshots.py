"""V0.14 / 67: checked DDR snapshot download and immutable local image storage."""
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import binascii
import json
import os
import time
import uuid
from PIL import Image, ImageDraw, ImageOps
from .protocol import Frame, FrameDecoder


class CaptureCancelled(Exception):
    pass


@dataclass(frozen=True)
class SnapshotInfo:
    width: int
    height: int
    frozen: bool


def snapshot_info(client):
    if client.simulated:
        return SnapshotInfo(1280, 720, getattr(client, '_frozen', False))
    p = client._exchange(0x30).payload
    if p[0] or p[1] != 1 or p[6] != 3 or not p[7] & 1:
        raise RuntimeError('当前固件不支持冻结帧传图，请下载 V0.14 或更新固件')
    w, h = int.from_bytes(p[2:4], 'little'), int.from_bytes(p[4:6], 'little')
    if not (1 <= w <= 1280 and 1 <= h <= 720):
        raise ValueError('冻结帧尺寸不合法')
    return SnapshotInfo(w, h, bool(p[7] & 2))


def set_frozen(client, frozen):
    if client.simulated:
        client._frozen = bool(frozen)
        return
    with client.lock:
        previous = client.timeout
        try:
            client.timeout = max(previous, 2.0)
            client.request(0x31, bytes((int(frozen),)) + bytes(7))
        finally:
            client.timeout = previous


def read_row(client, row, width):
    """Own the serial stream through the CRC: never let _exchange discard data.
    On a truncated stream, reconnect before issuing another capture.
    """
    with client.lock:
        seq = client.sequence
        client.sequence = (seq + 1) & 255
        packet = Frame(seq, 0x32, row.to_bytes(2, 'little') + bytes(6)).encode()
        if client.transport.write(packet) != len(packet):
            raise OSError('冻结帧请求发送不完整')
        decoder = FrameDecoder()
        deadline = time.monotonic() + max(2, client.timeout)
        reply = None
        while time.monotonic() < deadline and reply is None:
            for f in decoder.feed(client.transport.read(1)):
                if (f.sequence, f.command) == (seq, 0xb2):
                    reply = f
        if reply is None:
            raise TimeoutError('冻结帧行应答超时，请恢复实时后重试')
        p = reply.payload
        if p[0]:
            raise RuntimeError(f'冻结帧读取失败，设备状态 {p[0]}（4未冻结，5视频超时，6DDR读出错误）')
        length = int.from_bytes(p[3:5], 'little')
        if int.from_bytes(p[1:3], 'little') != row or length != width * 3 or p[5:] != bytes((3, 0, 0)):
            raise ValueError('冻结帧行号/长度/格式不匹配')
        raw = bytearray()
        deadline = time.monotonic() + length * 10 / getattr(client.transport, 'baudrate', 115200) + 2
        while len(raw) < length + 2 and time.monotonic() < deadline:
            raw.extend(client.transport.read(min(4096, length + 2 - len(raw))))
        if len(raw) != length + 2:
            # A line is bounded in length; stop issuing requests on this failure.
            raise TimeoutError('冻结帧像素流不完整，未保存图片；请断开并重新连接')
        if binascii.crc_hqx(raw[:-2], 0xffff) != int.from_bytes(raw[-2:], 'little'):
            raise ValueError('冻结帧 CRC16 校验失败，未保存损坏的图片')
        return bytes(raw[:-2])


def download_snapshot(client, cancel, progress):
    """Freeze first; preserve the frozen frame even if download is cancelled.
    The caller explicitly resumes live video. No partial image is published.
    """
    with client.lock:
        info = snapshot_info(client)
        set_frozen(client, True)
        progress(0, info.height)
        if client.simulated:
            image = Image.new('RGB', (info.width, info.height), '#183348')
            draw = ImageDraw.Draw(image)
            for x in range(0, info.width, 80):
                draw.line((x, 0, info.width-x, info.height), fill='#4faea5', width=3)
            draw.text((40, 40), 'SIMULATED FRAME - NOT CAMERA DATA\n' + datetime.now().isoformat(), fill='white')
            for y in range(0, info.height, 30):
                if cancel.is_set(): raise CaptureCancelled('下载已取消；画面保持冻结')
                time.sleep(.015); progress(min(y+30, info.height), info.height)
            return image
        data = bytearray()
        for row in range(info.height):
            if cancel.is_set(): raise CaptureCancelled('下载已取消；画面保持冻结')
            data.extend(read_row(client, row, info.width))
            progress(row+1, info.height)
        return Image.frombytes('RGB', (info.width, info.height), bytes(data))


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
