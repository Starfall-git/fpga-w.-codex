"""V0.6 / 28: direct controls, latest-value queue, low-latency status updates."""
import argparse
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import queue
import time
import tkinter as tk
from tkinter import ttk
from .client import SerialClient, DemoClient, list_ports
from .protocol import (CAP_THRESHOLD, CAP_FLIP, CAP_CROP, CAP_ZOOM, CAP_ISP,
                       CAP_DEFAULTS, threshold_payload, crop_payload, percent_ratio)


class ImageControlApp:
    def __init__(self, root, demo=False):
        self.root = root
        root.title('VF-Ti60 · 实时图像控制台')
        root.geometry('1000x700')
        root.minsize(950, 650)
        self.executor = ThreadPoolExecutor(max_workers=1)
        self.events = queue.Queue()
        self.pending = OrderedDict()
        self.client = None
        self.busy = self.closing = self.resetting = False
        self.caps = 0
        self.inflight_kind = None
        self.last_interaction = 0.0
        self.mode = tk.StringVar(value='模拟演示' if demo else '串口硬件')
        self.port, self.baud = tk.StringVar(), tk.StringVar(value='115200')
        self.threshold, self.readback = tk.StringVar(value='128'), tk.StringVar(value='—')
        self.connection = tk.StringVar(value='未连接')
        self.message = tk.StringVar(value='连接设备后，阈值与缩放输入回车生效，开关点击即生效。')
        self.cap_text = tk.StringVar(value='')
        self.geometry_readback = tk.StringVar(value='尚未读取图像设置')
        self.mode_readback = tk.StringVar(value='当前模式：—')
        self.latency = tk.StringVar(value='')
        self.flip, self.flip_horizontal = tk.BooleanVar(), tk.BooleanVar()
        self.sobel, self.inverted = tk.BooleanVar(), tk.BooleanVar()
        self.crop = {k: tk.StringVar(value=v) for k,v in (('x','0'),('y','0'),('width','1280'),('height','720'))}
        self.zoom = tk.StringVar(value='100%')
        self.auto_poll = tk.BooleanVar(value=True)
        self.show_log = tk.BooleanVar(value=False)
        self.controls = []
        self._build()
        self.refresh_ports()
        root.protocol('WM_DELETE_WINDOW', self.close)
        self._drain_id=root.after(5, self._drain)
        self._poll_id=root.after(1500, self._poll)
        self._states()

    def _build(self):
        style = ttk.Style()
        if 'clam' in style.theme_names(): style.theme_use('clam')
        for cls in ('TFrame','TLabel','TLabelframe'):
            style.configure(cls, background='#f3f5f8')
        style.configure('TLabel', font=('Microsoft YaHei UI',10))
        style.configure('TButton', padding=(10,6), font=('Microsoft YaHei UI',10))
        style.configure('Title.TLabel', font=('Microsoft YaHei UI',20,'bold'), foreground='#17364c')
        main = ttk.Frame(self.root, padding=20)
        main.pack(fill='both', expand=True)
        ttk.Label(main, text='实时图像控制台', style='Title.TLabel').pack(anchor='w')
        ttk.Label(main, text='VF-Ti60F225   /   HDMI 720p · 原图、Sobel 与几何变换').pack(anchor='w',pady=(4,12))
        connection = ttk.LabelFrame(main,text='连接',padding=10)
        connection.pack(fill='x')
        self.mode_box = ttk.Combobox(connection,textvariable=self.mode,values=('串口硬件','模拟演示'),width=10,state='readonly')
        self.mode_box.pack(side='left',padx=4)
        self.port_box = ttk.Combobox(connection,textvariable=self.port,width=10,state='readonly')
        self.port_box.pack(side='left',padx=4)
        self.refresh_button = ttk.Button(connection,text='刷新',command=self.refresh_ports)
        self.refresh_button.pack(side='left',padx=4)
        ttk.Label(connection,text='波特率').pack(side='left',padx=6)
        self.baud_entry = ttk.Entry(connection,textvariable=self.baud,width=8)
        self.baud_entry.pack(side='left')
        self.connect_button = ttk.Button(connection,text='连接',command=self.toggle_connection)
        self.connect_button.pack(side='left',padx=12)
        ttk.Label(connection,textvariable=self.connection).pack(side='left')

        image = ttk.LabelFrame(main,text='图像',padding=12)
        image.pack(fill='x',pady=12)
        row = ttk.Frame(image); row.pack(fill='x')
        for text, variable in (('Sobel 边缘检测',self.sobel),('黑白反转',self.inverted)):
            button=ttk.Checkbutton(row,text=text,variable=variable,command=self.apply_isp)
            button.pack(side='left',padx=(0,20)); self.controls.append((button,CAP_ISP))
        ttk.Label(row,text='阈值').pack(side='left',padx=(10,6))
        self.threshold_entry=ttk.Entry(row,textvariable=self.threshold,width=9,font=('Consolas',14))
        self.threshold_entry.pack(side='left'); self.controls.append((self.threshold_entry,CAP_THRESHOLD))
        self.threshold_entry.bind('<Return>',lambda _: self.apply_threshold())
        ttk.Label(row,text='0–4095 · 回车生效').pack(side='left',padx=10)
        ttk.Label(image,textvariable=self.mode_readback,foreground='#137c70').pack(anchor='w',pady=(10,0))
        info=ttk.Frame(image); info.pack(fill='x',pady=(4,0))
        ttk.Label(info,text='设备阈值：').pack(side='left')
        ttk.Label(info,textvariable=self.readback,foreground='#137c70').pack(side='left')
        ttk.Label(info,textvariable=self.latency,foreground='#64748b').pack(side='right')

        transform=ttk.LabelFrame(main,text='翻转、缩放与裁剪',padding=12)
        transform.pack(fill='x')
        row=ttk.Frame(transform); row.pack(fill='x')
        for text,variable in (('上下翻转',self.flip),('左右翻转',self.flip_horizontal)):
            button=ttk.Checkbutton(row,text=text,variable=variable,command=lambda: self.apply_feature('flip'))
            button.pack(side='left',padx=(0,20)); self.controls.append((button,CAP_FLIP))
        ttk.Label(row,text='缩放').pack(side='left',padx=(15,5))
        self.zoom_box=ttk.Combobox(row,textvariable=self.zoom,values=('10%','25%','50%','100%','150%','200%','300%','400%','500%'),width=10)
        self.zoom_box.pack(side='left'); self.controls.append((self.zoom_box,CAP_ZOOM))
        self.zoom_box.bind('<<ComboboxSelected>>',lambda _: self.apply_feature('zoom'))
        self.zoom_box.bind('<Return>',lambda _: self.apply_feature('zoom'))
        ttk.Label(row,text='10%–500% · 可输入，回车生效').pack(side='left',padx=10)
        row=ttk.Frame(transform); row.pack(fill='x',pady=12)
        for name,label in (('x','X'),('y','Y'),('width','宽'),('height','高')):
            ttk.Label(row,text=label).pack(side='left',padx=(0,5))
            entry=ttk.Entry(row,textvariable=self.crop[name],width=7)
            entry.pack(side='left',padx=(0,12)); self.controls.append((entry,CAP_CROP))
            entry.bind('<Return>',lambda _: self.apply_feature('crop'))
        crop_button=ttk.Button(row,text='裁剪',command=lambda: self.apply_feature('crop'))
        crop_button.pack(side='left'); self.controls.append((crop_button,CAP_CROP))
        self.defaults_button=ttk.Button(row,text='默认',command=self.reset_defaults)
        self.defaults_button.pack(side='right')
        ttk.Label(transform,text='居中显示：缩小补黑，放大截取。黑白反转只作用于 Sobel；“默认”保留阈值。',foreground='#64748b').pack(anchor='w')
        ttk.Label(transform,textvariable=self.geometry_readback,wraplength=880,foreground='#137c70').pack(fill='x',pady=(8,0))
        ttk.Label(main,textvariable=self.message,wraplength=900).pack(fill='x',pady=12)
        row=ttk.Frame(main); row.pack(fill='x')
        ttk.Checkbutton(row,text='通信记录',variable=self.show_log,command=self._toggle_log).pack(side='left')
        ttk.Label(row,textvariable=self.cap_text,foreground='#64748b').pack(side='right')
        self.log_frame=ttk.Frame(main)
        self.log=tk.Text(self.log_frame,height=6,wrap='word',font=('Consolas',9),background='#142735',foreground='#d7e5ee',state='disabled')
        scroll=ttk.Scrollbar(self.log_frame,command=self.log.yview)
        self.log.configure(yscrollcommand=scroll.set)
        scroll.pack(side='right',fill='y'); self.log.pack(fill='both',expand=True)

    def _toggle_log(self):
        if self.show_log.get(): self.log_frame.pack(fill='both',expand=True,pady=(6,0))
        else: self.log_frame.pack_forget()

    def _states(self):
        connected=self.client is not None
        for widget in (self.mode_box,self.port_box): widget.configure(state='disabled' if connected or self.busy else 'readonly')
        self.baud_entry.configure(state='disabled' if connected or self.busy else 'normal')
        self.refresh_button.configure(state='disabled' if connected or self.busy else 'normal')
        self.connect_button.configure(text='断开' if connected else '连接',state='disabled' if self.busy or self.pending else 'normal')
        # V0.6: edits remain usable while a packet is in flight; latest values are queued.
        for widget,cap in self.controls:
            widget.configure(state='normal' if connected and not self.resetting and self.caps & cap else 'disabled')
        self.defaults_button.configure(state='normal' if connected and not self.resetting and self.caps & CAP_DEFAULTS else 'disabled')

    def _trace(self,direction,raw): self.events.put(('log',f'{direction}  {raw.hex(" ").upper()}'))

    def _log(self,message):
        self.log.configure(state='normal')
        self.log.insert('end',datetime.now().strftime('%H:%M:%S')+'  '+message+'\n')
        if int(self.log.index('end-1c').split('.')[0])>500: self.log.delete('1.0','100.0')
        self.log.see('end'); self.log.configure(state='disabled')

    def _submit(self,operation,success,kind='command'):
        if self.closing: return
        if self.busy:
            if kind!='poll':
                self.pending[kind]=(operation,success)
                self.message.set('已记录最新操作，当前应答完成后立即应用。')
            return
        self.busy=True; self.inflight_kind=kind; self._states()
        future=self.executor.submit(operation)
        future.add_done_callback(lambda result:self.events.put(('done',result,success,kind)))

    def _drain(self):
        while not self.events.empty():
            item=self.events.get_nowait()
            if item[0]=='log': self._log(item[1]); continue
            self.busy=False; self.inflight_kind=None
            try: item[2](item[1].result())
            except Exception as error:
                self.message.set(str(error)); self._log('错误  '+str(error))
                if item[3]=='defaults': self.resetting=False
            self._states()
            if self.pending:
                kind,(operation,success)=self.pending.popitem(last=False)
                self._submit(operation,success,kind)
        if not self.closing: self._drain_id=self.root.after(5,self._drain)

    def refresh_ports(self):
        try:
            ports=list_ports(); self.port_box.configure(values=[p[0] for p in ports])
            if ports and self.port.get() not in [p[0] for p in ports]: self.port.set(ports[0][0])
            if not ports: self.port.set('')
        except ImportError: self.message.set('请安装串口依赖：python -m pip install -r host/requirements.txt')

    def toggle_connection(self):
        if self.busy or self.pending: return
        if self.client:
            backend=self.client
            def disconnected(_):
                self.client=None; self.caps=0; self.connection.set('未连接'); self.readback.set('—')
                self.mode_readback.set('当前模式：—'); self.geometry_readback.set('尚未读取图像设置')
                self.message.set('已断开。')
            self._submit(backend.close,disconnected,'disconnect'); return
        try:
            mode,port,baud=self.mode.get(),self.port.get(),int(self.baud.get())
            if not 1200<=baud<=1000000: raise ValueError('波特率无效')
            if mode=='串口硬件' and not port: raise ValueError('请选择串口')
        except ValueError as error: self.message.set(str(error)); return
        def connect():
            backend=DemoClient(self._trace) if mode=='模拟演示' else SerialClient(port,baud,trace=self._trace)
            try:
                status=backend.get_status()
                geometry=backend.get_geometry() if status.capabilities & CAP_CROP else None
            except Exception: backend.close(); raise
            return backend,status,geometry
        def connected(result):
            self.client,status,geometry=result
            self.connection.set('模拟 · 未连接硬件' if self.client.simulated else f'已连接 {port}')
            self._status(status); self.threshold.set(str(status.threshold))
            self.sobel.set(status.sobel_enabled); self.inverted.set(status.inverted)
            if geometry: self._geometry(geometry); self._load_geometry_draft(geometry)
        self._submit(connect,connected,'connect')

    def _status(self,status,announce=True):
        self.caps=status.capabilities; self.readback.set(str(status.threshold))
        prefix='模拟' if self.client.simulated else '设备'
        mode='Sobel · '+('黑边白底' if status.inverted else '白边黑底') if status.sobel_enabled else '原始图像'
        if status.capabilities & CAP_ISP:
            self.mode_readback.set(f'{prefix}已确认：{mode}；黑白反转'+('开启' if status.inverted else '关闭'))
        else:
            mode='模式由旧版bit固定，无法回读'
            self.mode_readback.set(mode)
        self.cap_text.set('V0.6 功能可用' if status.capabilities & CAP_DEFAULTS else '旧版设备：新功能需下载 V0.6')
        if announce: self.message.set(f'{prefix}已确认：阈值 {status.threshold}，{mode}。')

    def _status_action(self,status):
        self._status(status)
        if not self.client.simulated: self.latency.set(f'最近命令往返 {self.client.last_roundtrip_ms:.1f} ms')

    def apply_threshold(self):
        if not self.client or self.resetting or not self.caps & CAP_THRESHOLD: return
        try: value=int(self.threshold.get()); threshold_payload(value)
        except ValueError: self.message.set('阈值必须为0～4095整数，未发送。'); return
        self.last_interaction=time.monotonic(); backend=self.client
        self._submit(lambda:backend.set_threshold(value),self._status_action,'threshold')

    def apply_isp(self):
        if not self.client or self.resetting or not self.caps & CAP_ISP: return
        enabled,inverted=self.sobel.get(),self.inverted.get(); backend=self.client
        self.last_interaction=time.monotonic()
        self._submit(lambda:backend.set_isp(enabled,inverted),self._status_action,'isp')

    def apply_feature(self,kind):
        if not self.client or self.resetting: return
        cap={'flip':CAP_FLIP,'crop':CAP_CROP,'zoom':CAP_ZOOM}[kind]
        if not self.caps & cap: return
        try:
            if kind=='flip': args=(self.flip.get(),self.flip_horizontal.get())
            elif kind=='crop':
                args=tuple(int(self.crop[k].get()) for k in ('x','y','width','height')); crop_payload(*args)
            else: args=percent_ratio(self.zoom.get())
        except ValueError as error: self.message.set(str(error)); return
        backend=self.client; self.last_interaction=time.monotonic()
        self._submit(lambda:getattr(backend,'set_'+kind)(*args),self._geometry,kind)

    def _geometry(self,g):
        prefix='模拟' if self.client.simulated else '设备'
        self.geometry_readback.set(f'{prefix}已确认：上下'+('开' if g.vertical else '关')+' / 左右'+('开' if g.horizontal else '关')+
            f'；裁剪 ({g.x}, {g.y}, {g.width}, {g.height})；缩放 {g.numerator*100/g.denominator:g}%。')
        self.message.set('图像设置已生效并回读。' if not self.client.simulated else '模拟设置已回读，未连接硬件。')
        if g.faults: self.message.set('设备历史诊断：'+('出现过缺行；' if g.faults&1 else '')+('出现过DDR读错误；' if g.faults&2 else '')+'标志保持至FPGA复位。')

    def _load_geometry_draft(self,g):
        self.flip.set(g.vertical); self.flip_horizontal.set(g.horizontal)
        for name in self.crop: self.crop[name].set(str(getattr(g,name)))
        self.zoom.set(f'{g.numerator*100/g.denominator:g}%')

    def reset_defaults(self):
        if not self.client or self.resetting or not self.caps & CAP_DEFAULTS: return
        # V0.6: defaults supersede unsent edits, never discard an in-flight packet.
        threshold_task=self.pending.get('threshold')
        self.pending.clear()
        if threshold_task: self.pending['threshold']=threshold_task
        self.resetting=True; self._states()
        backend=self.client; self.last_interaction=time.monotonic()
        def updated(result):
            status,geometry=result; self.resetting=False; self._status(status)
            self.sobel.set(status.sobel_enabled); self.inverted.set(status.inverted)
            if geometry: self._geometry(geometry); self._load_geometry_draft(geometry)
            self.message.set('已恢复默认，Sobel阈值保持不变。')
        self._submit(backend.reset_defaults,updated,'defaults')

    def _poll(self):
        # Only one short status request; geometry is read after commands, not every poll.
        if self.auto_poll.get() and self.client and not self.busy and not self.pending and time.monotonic()-self.last_interaction>.3:
            self._submit(self.client.get_status,lambda status:self._status(status,False),'poll')
        if not self.closing: self._poll_id=self.root.after(1500,self._poll)

    def close(self):
        if self.closing: return
        self.closing=True; self.pending.clear(); client=self.client
        # V0.6: cancel owned timers before destroying Tcl widgets.
        for timer in (self._drain_id,self._poll_id):
            self.root.after_cancel(timer)
        def cleanup():
            if client: client.close()
            while not self.events.empty():
                item=self.events.get_nowait()
                if item[0]=='done':
                    try:
                        result=item[1].result()
                        if isinstance(result,tuple) and hasattr(result[0],'close'): result[0].close()
                    except Exception: pass
        self.executor.submit(cleanup); self.executor.shutdown(wait=False); self.root.destroy()


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--demo',action='store_true')
    args=parser.parse_args()
    root=tk.Tk(); ImageControlApp(root,demo=args.demo); root.mainloop()


if __name__=='__main__': main()
