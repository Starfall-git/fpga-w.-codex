"""v1.1 / 7: Hardware-only inference status; simulation never invents predictions."""
from dataclasses import dataclass

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

    @property
    def label(self):
        return LABELS[self.class_id] if self.valid else '未识别到有效手势'


def parse_status(payload):
    if len(payload)!=8:raise ValueError('手势状态长度错误')
    if payload[0]:raise RuntimeError(f'手势命令失败：状态 {payload[0]}（需要v1.1固件）')
    if payload[1]!=0x11:raise RuntimeError('手势固件版本不兼容，需要v1.1')
    flags,cid=payload[2:4]
    if flags&0xe0 or cid not in (*range(5),255):raise ValueError('手势状态字段非法')
    valid=bool(flags&4)
    if valid and (not flags&1 or not flags&8 or flags&16 or cid==255):
        raise ValueError('手势有效标志与设备状态矛盾')
    if not valid and cid!=255:raise ValueError('无效结果未清除类别')
    return GestureStatus(bool(flags&1),bool(flags&2),valid,bool(flags&8),bool(flags&16),cid,
                         int.from_bytes(payload[4:6],'little'),int.from_bytes(payload[6:8],'little'))


def gesture_status(client):
    if client.simulated:return getattr(client,'gesture_state',GestureStatus())
    return parse_status(client._exchange(0x40).payload)


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
