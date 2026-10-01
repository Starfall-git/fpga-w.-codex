"""v1.1 / 7: Hardware-only inference status; simulation never invents predictions."""
from dataclasses import dataclass,replace

LABELS=('拳头','剪刀','布','OK','点赞')


@dataclass(frozen=True)
class GestureStatus:
    enabled: bool=False
    busy: bool=False
    valid: bool=False
    ready: bool=True
    stale: bool=True
    class_id: int=255
    margin: int=0
    frame_id: int=0
    # v1.2 / 11: explicit capability and latest detected crop.
    auto_mode: bool=False
    region: tuple | None=None

    @property
    def label(self):
        return LABELS[self.class_id] if self.valid else '未识别到有效手势'


def parse_status(payload):
    if len(payload)!=8:raise ValueError('手势状态长度错误')
    if payload[0]:raise RuntimeError(f'手势命令失败：状态 {payload[0]}（需要v1.1固件）')
    if payload[1] not in (0x11,0x12):raise RuntimeError('手势固件版本不兼容，需要v1.1/v1.2')
    flags,cid=payload[2:4]
    if flags&0xe0 or cid not in (*range(5),255):raise ValueError('手势状态字段非法')
    valid=bool(flags&4)
    if valid and (not flags&1 or not flags&8 or flags&16 or cid==255):
        raise ValueError('手势有效标志与设备状态矛盾')
    if not valid and cid!=255:raise ValueError('无效结果未清除类别')
    return GestureStatus(bool(flags&1),bool(flags&2),valid,bool(flags&8),bool(flags&16),cid,
                         int.from_bytes(payload[4:6],'little'),int.from_bytes(payload[6:8],'little'),payload[1]==0x12)


def gesture_status(client):
    if client.simulated:return getattr(client,'gesture_state',GestureStatus())
    with client.lock:
        status=parse_status(client._exchange(0x40).payload)
        if status.auto_mode:
            region=parse_region(client._exchange(0x42).payload)
            status=replace(status,region=region if status.enabled and not status.stale else None)
        return status


def gesture_control(client,enabled):
    if type(enabled) is not bool:raise ValueError('识别开关必须为布尔值')
    with client.lock:
        if client.simulated:
            client.gesture_state=GestureStatus(enabled=enabled)
            return client.gesture_state
        parse_status(client._exchange(0x41,bytes((int(enabled),))+bytes(7)).payload)
        status=gesture_status(client)
        if status.enabled!=enabled:raise RuntimeError('识别开关回读与请求不一致')
        return status


# v1.2 / 11: This is the latest detection crop, not a video preview or probability.
def parse_region(payload):
    if len(payload)!=8 or payload[0]!=0 or payload[1]!=0x12:raise ValueError('定位状态回复非法')
    x=int.from_bytes(payload[2:4],'little');y=int.from_bytes(payload[4:6],'little');side=int.from_bytes(payload[6:8],'little')
    if side==0:
        if x or y:raise ValueError('无定位结果时坐标必须清零')
        return None
    if side%64 or not 64<=side<=704 or x+side>1280 or y+side>720:raise ValueError('定位区域超出画面')
    return x,y,side
