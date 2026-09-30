"""V0.15 / 71: serial metadata only; DDR slot IDs are session-local."""
from dataclasses import dataclass, replace

@dataclass(frozen=True)
class StoreStatus:
    capacity: int
    saved: tuple
    mode: int
    display: int
    version: int = 3
    orders: tuple = ()


def parse_status(p):
    if len(p)!=8:raise ValueError('DDR状态长度错误')
    if p[0]:
        raise RuntimeError({2:'帧编号或对比选择无效',4:'请先实时显示，再记录一个新的帧',5:'等待显示帧边界超时',7:'DDR帧仓库已满，请删除不需要的帧后记录'}.get(p[0],f'设备错误 {p[0]}'))
    if p[1] not in (2,3):raise RuntimeError('需要V0.15 DDR仓库固件；旧版串口传图不再使用')
    mask=int.from_bytes(p[4:6],'little');ids=tuple(i for i in range(12) if mask & (1<<i))
    if mask>>12 or len(ids)!=p[3] or not 1<=p[2]<=8 or len(ids)>p[2] or p[6]>3:
        raise ValueError('DDR仓库状态非法')
    return StoreStatus(p[2],ids,p[6],p[7],p[1])


def store_status(client):
    if client.simulated:
        return getattr(client,'ddr_status',StoreStatus(8,(),0,0))
    with client.lock:return with_orders(client,parse_status(client._exchange(0x30).payload))


def store_control(client, action, frame_id=0, selection=()):
    if action not in range(7):raise ValueError('DDR操作无效')
    if action in (3,6) and frame_id not in range(12):raise ValueError('帧编号必须为0～11')
    ids=set(selection)
    if action==4 and (not ids or any(i not in range(12) for i in ids)):raise ValueError('请选择有效DDR帧')
    mask=sum(1<<i for i in ids)
    with client.lock:
        if client.simulated:
            status=store_status(client);saved=list(status.saved);mode=status.mode;display=status.display
            if action==6 and status.version<3:raise RuntimeError('单帧删除需要V0.18固件')
            if action==0:mode=0
            elif action==1:
                if mode!=0:raise RuntimeError('请先实时显示再记录')
                if len(saved)>=8:raise RuntimeError('DDR帧仓库已满')
                slot=next(i for i in range(12) if i not in saved);saved.append(slot)
                client.ddr_ordinal=getattr(client,'ddr_ordinal',0)+1
                orders=dict(status.orders);orders[slot]=client.ddr_ordinal
                status=replace(status,orders=tuple(orders.items()))
            elif action==2:mode=1
            elif action==3:
                if frame_id not in saved:raise ValueError('帧已失效')
                mode=2;display=frame_id
            elif action==4:
                if not ids.issubset(saved):raise ValueError('帧已失效')
                mode=3
            elif action==5:saved=[];mode=0
            elif action==6:
                if frame_id not in saved:raise ValueError('帧已失效')
                saved.remove(frame_id);mode=0
            client.ddr_status=StoreStatus(8,tuple(sorted(saved)),mode,display,3,tuple((s,o) for s,o in status.orders if s in saved))
            return client.ddr_status
        if action==6 and store_status(client).version<3:raise RuntimeError('单帧删除需要V0.18固件，请更新bit')
        previous=client.timeout
        try:
            client.timeout=max(2,previous)
            return with_orders(client,parse_status(client._exchange(0x31,bytes((action,frame_id))+mask.to_bytes(2,'little')+bytes(4)).payload))
        finally:client.timeout=previous


def with_orders(client,status):
    if status.version<3:return status
    orders=[]
    for slot in status.saved:
        p=client._exchange(0x33,bytes((slot,))+bytes(7)).payload
        if len(p)!=8 or p[0] or p[1]!=slot or any(p[6:]):raise RuntimeError('读取DDR记录顺序失败')
        order=int.from_bytes(p[2:6],'little')
        if not order:raise ValueError('DDR记录序号无效')
        orders.append((slot,order))
    if len({v for _,v in orders})!=len(orders):raise ValueError('DDR记录序号重复')
    return replace(status,orders=tuple(orders))


class FrameCatalog:
    """V0.18 / 83: session display IDs are independent of physical DDR slots.
    Hardware V3 ordinals preserve capture order across reconnects; wall time is host-local.
    """
    def __init__(self):self.entries={};self.next_number=1;self.next_order=1
    def sync(self,slots,orders=()):
        orders=dict(orders)
        self.entries={s:e for s,e in self.entries.items() if s in slots and (s not in orders or e['order']==orders[s])}
        for slot in sorted(slots,key=lambda s:orders.get(s,s)):
            if slot not in self.entries:
                while any(e['number']==self.next_number for e in self.entries.values()):self.next_number+=1
                self.entries[slot]=dict(number=self.next_number,order=orders.get(slot,self.next_order),time=None,thumbnail=None)
                self.next_number+=1;self.next_order+=1
    def rename(self,slot,number):
        if not isinstance(number,int) or number<1:raise ValueError('编号必须是正整数')
        if any(s!=slot and e['number']==number for s,e in self.entries.items()):raise ValueError('编号已存在，不能重复')
        self.entries[slot]['number']=number
    def ordered(self):return sorted(self.entries,key=lambda s:self.entries[s]['order'])
