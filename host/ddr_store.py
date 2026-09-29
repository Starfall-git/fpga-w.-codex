"""V0.15 / 71: serial metadata only; DDR slot IDs are session-local."""
from dataclasses import dataclass

@dataclass(frozen=True)
class StoreStatus:
    capacity: int
    saved: tuple
    mode: int
    display: int


def parse_status(p):
    if p[0]:
        raise RuntimeError({2:'帧编号或对比选择无效',4:'请先继续直播，再冻结一个新的帧',5:'等待显示帧边界超时',7:'DDR帧仓库已满，请清空后重新记录'}.get(p[0],f'设备错误 {p[0]}'))
    if p[1]!=2:raise RuntimeError('需要V0.15 DDR仓库固件；旧版串口传图不再使用')
    mask=int.from_bytes(p[4:6],'little');ids=tuple(i for i in range(12) if mask & (1<<i))
    if mask>>12 or len(ids)!=p[3] or not 1<=p[2]<=8 or len(ids)>p[2] or p[6]>3:
        raise ValueError('DDR仓库状态非法')
    return StoreStatus(p[2],ids,p[6],p[7])


def store_status(client):
    if client.simulated:
        return getattr(client,'ddr_status',StoreStatus(8,(),0,0))
    return parse_status(client._exchange(0x30).payload)


def store_control(client, action, frame_id=0, selection=()):
    if action not in range(6):raise ValueError('DDR操作无效')
    if action==3 and frame_id not in range(12):raise ValueError('帧编号必须为0～11')
    ids=set(selection)
    if action==4 and (not ids or any(i not in range(12) for i in ids)):raise ValueError('请选择有效DDR帧')
    mask=sum(1<<i for i in ids)
    with client.lock:
        if client.simulated:
            status=store_status(client);saved=list(status.saved);mode=status.mode;display=status.display
            if action==0:mode=0
            elif action==1:
                if mode!=0:raise RuntimeError('请先继续直播再冻结')
                if len(saved)>=8:raise RuntimeError('DDR帧仓库已满')
                saved.append(next(i for i in range(12) if i not in saved))
            elif action==2:mode=1
            elif action==3:
                if frame_id not in saved:raise ValueError('帧已失效')
                mode=2;display=frame_id
            elif action==4:
                if not ids.issubset(saved):raise ValueError('帧已失效')
                mode=3
            elif action==5:saved=[];mode=0
            client.ddr_status=StoreStatus(8,tuple(sorted(saved)),mode,display)
            return client.ddr_status
        previous=client.timeout
        try:
            client.timeout=max(2,previous)
            return parse_status(client._exchange(0x31,bytes((action,frame_id))+mask.to_bytes(2,'little')+bytes(4)).payload)
        finally:client.timeout=previous
