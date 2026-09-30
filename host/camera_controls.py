"""V0.19 / 88-91: acknowledged camera registers and frame-boundary ISP tuning.
/* Changes: manual exposure/gain, on-chip AE restart, independent denoise/link knobs.
   Register ACK means bus completion, not that optical exposure has settled. */
"""
import struct
import tkinter as tk
from tkinter import ttk


def register(client, address, value=None):
    if client.simulated:
        if not hasattr(client,'camera_registers'):
            client.camera_registers={0x3012:672,0x305e:32,0x30b0:0x4a0,0x3100:19,
                                     0x3102:1280,0x3110:320,0x312a:0x220,0x3152:1280,0x3164:672,0x3140:0,0x3142:0,0x3144:1280,0x3146:960,0x3166:986,0x3168:419}
        if value is not None:client.camera_registers[address]=value
        return client.camera_registers[address]
    if not client.status or not client.status.advanced_capabilities & 16:
        raise RuntimeError('曝光调节需要 V0.19 或更新的 bit 文件')
    payload=struct.pack('<BHH',int(value is not None),address,value or 0)+bytes(3)
    response=client._exchange(0x40,payload).payload
    if response[0]:raise RuntimeError(f'摄像头寄存器操作失败，状态 {response[0]}；请回读后重试')
    return int.from_bytes(response[1:3],'little')


def camera_read(client):
    with client.lock:
        return {a:register(client,a) for a in (0x3100,0x3012,0x30b0,0x305e,0x312a,0x3152,0x3164)}


def manual(client, rows, analog, digital):
    if not 1<=rows<=672 or analog not in range(4) or not 32<=digital<=128:
        raise ValueError('曝光或增益超出范围')
    with client.lock:
        for a,v in ((0x3100,0),(0x3012,rows),(0x30b0,0x480|(analog<<4)),(0x305e,digital)):
            register(client,a,v)
            if register(client,a)!=v:raise RuntimeError('摄像头写入后回读不一致，停止后续设置')
        return camera_read(client)


def auto_adjust(client):
    # Sensor AE optimizes brightness, not an edge-sharpness objective. Keep digital
    # gain at unity to avoid amplifying noise; permit AE exposure/analog adjustment.
    with client.lock:
        for a,v in ((0x3100,0),(0x305e,32),(0x3102,1280),(0x3110,320),
                    (0x3140,0),(0x3142,0),(0x3144,1280),(0x3146,720),
                    (0x3166,600),(0x3168,400),(0x3100,3)):
            register(client,a,v)
        return camera_read(client)


def camera_defaults(client):
    with client.lock:
        for a,v in ((0x3100,0),(0x3012,672),(0x30b0,0x4a0),(0x305e,32),
                    (0x3102,1280),(0x3110,320),(0x3140,0),(0x3142,0),(0x3144,1280),
                    (0x3146,960),(0x3166,986),(0x3168,419),(0x3100,19)):
            register(client,a,v)
        tuning(client,0,50)


def tuning(client, flags=None, percentage=50):
    if flags is not None and (flags & ~15 or not 25<=percentage<=75):
        raise ValueError('算法设置范围错误')
    if client.simulated:
        if flags is not None:client.isp_tuning=(flags,percentage)
        return getattr(client,'isp_tuning',(0,50))
    response=client._exchange(0x15 if flags is None else 0x14,
                             bytes(8) if flags is None else bytes((flags,percentage))+bytes(6)).payload
    if response[0]:raise RuntimeError(f'算法设置失败，状态 {response[0]}')
    return tuple(response[1:3])


class ControlPanel:
    def __init__(self,app):
        self.app=app;self.client=app.client;self.auto_tracking=False;self.dragging=False;self.refresh_id=None
        self.window=tk.Toplevel(app.root);self.window.title('曝光与算法调节');self.window.geometry('760x690')
        main=ttk.Frame(self.window,padding=18);main.pack(fill='both',expand=True)
        camera=ttk.LabelFrame(main,text='摄像头 · 拖动后松开生效，并进入手动模式',padding=12);camera.pack(fill='x')
        self.rows=tk.DoubleVar(value=672);self.analog=tk.DoubleVar(value=2);self.digital=tk.DoubleVar(value=32)
        self.values=tk.StringVar();self.status=tk.StringVar(value='正在读取摄像头…')
        self.widgets=[]
        for label,var,lo,hi in [('曝光',self.rows,1,672),('模拟增益',self.analog,0,3),('数字增益',self.digital,32,128)]:
            row=ttk.Frame(camera);row.pack(fill='x',pady=4)
            ttk.Label(row,text=label,width=12).pack(side='left')
            slider=ttk.Scale(row,variable=var,from_=lo,to=hi,command=lambda _:self.display_values())
            slider.pack(side='left',fill='x',expand=True);slider.bind('<ButtonPress-1>',self.begin_manual);slider.bind('<ButtonRelease-1>',self.submit_manual)
            slider.bind('<KeyRelease>',self.submit_manual);self.widgets.append(slider)
        ttk.Label(camera,textvariable=self.values).pack(anchor='w',pady=6)
        row=ttk.Frame(camera);row.pack(fill='x')
        ttk.Button(row,text='自动调光',command=self.submit_auto).pack(side='left')
        ttk.Button(row,text='回读当前曝光',command=self.read).pack(side='left',padx=8)
        ttk.Label(camera,text='弱光优先增加曝光，再加模拟增益；数字增益也会放大噪声。\n自动调光立即启动，通常需若干帧稳定；运动物体不宜长曝光。',wraplength=680).pack(anchor='w',pady=8)
        ttk.Label(camera,textvariable=self.status,wraplength=680).pack(anchor='w')
        alg=ttk.LabelFrame(main,text='算法选项 · 点击即生效',padding=12);alg.pack(fill='x',pady=14)
        self.flags=[tk.BooleanVar() for _ in range(4)];self.percent=tk.IntVar(value=50)
        for text,var in zip(('增强高斯：双级平滑，细小纹理会有所减弱',
                             'Scharr 幅度方向修正：减轻对斜边的偏重',
                             'Canny 延长弱边连接：2 → 6 个邻接像素',
                             'Canny 去除无邻居的孤立候选（可损失极小细节）'),self.flags):
            ttk.Checkbutton(alg,text=text,variable=var,command=self.submit_tuning).pack(anchor='w',pady=3)
        row=ttk.Frame(alg);row.pack(fill='x',pady=8)
        ttk.Label(row,text='Canny 低阈值 / 主界面高阈值（%）').pack(side='left')
        low=ttk.Spinbox(row,from_=25,to=75,textvariable=self.percent,width=6,command=self.submit_tuning)
        low.pack(side='left',padx=8);low.bind('<Return>',lambda _:self.submit_tuning())
        ttk.Button(alg,text='尝试降噪与连续轮廓组合',command=self.recommended).pack(anchor='w')
        ttk.Label(alg,text='组合：增强高斯 + 方向修正 + 六邻接连接；低阈值 50%。\n高斯开关仍由主界面控制。Sobel 算术保持不变。\n降低低阈值有助保留弱边，也可能连接噪点；不能保证消除光影边界。',wraplength=680).pack(anchor='w',pady=8)
        self.window.protocol('WM_DELETE_WINDOW',self.close)
        self.display_values();self.read()

    def active(self):
        return self.window.winfo_exists() and self.app.client is self.client and not self.app.resetting

    def display_values(self):
        rows=round(self.rows.get());ag=1<<round(self.analog.get())
        self.values.set(f'{rows} 行 ≈ {rows*1650/74250:.2f} ms    模拟 {ag}×    数字 {self.digital.get()/32:.2f}×')

    def show(self,result):
        if not self.active() or self.dragging:return
        r,t=result
        is_auto=bool(r[0x3100]&1)
        actual_rows=r[0x3164] if is_auto else r[0x3012]
        actual_gain=r[0x312a] if is_auto else (((r[0x30b0]>>4)&3)<<8)|r[0x305e]
        self.rows.set(max(1,min(672,actual_rows)))
        self.analog.set((actual_gain>>8)&3);self.digital.set(max(32,min(128,actual_gain&255)))
        for bit,var in enumerate(self.flags):var.set(bool(t[0]&(1<<bit)))
        self.percent.set(t[1]);self.display_values()
        mode='自动（当前曝光/增益可能继续变化）' if r[0x3100]&1 else '手动'
        self.status.set(f'已回读：{mode}；曝光 {actual_rows} 行；模拟 {1<<((actual_gain>>8)&3)}×；数字 {(actual_gain&255)/32:.2f}×')
        self.auto_tracking=is_auto
        if self.refresh_id is None:self.refresh_id=self.window.after(1000,self.refresh_auto)

    def begin_manual(self,event=None):
        self.dragging=True;self.auto_tracking=False

    def refresh_auto(self):
        self.refresh_id=None
        if not self.active():return
        if self.auto_tracking and not self.dragging and not self.app.busy and not self.app.pending:self.read()
        if self.refresh_id is None:self.refresh_id=self.window.after(1000,self.refresh_auto)

    def close(self):
        if self.refresh_id is not None:self.window.after_cancel(self.refresh_id);self.refresh_id=None
        self.window.destroy()

    def submit_manual(self,event=None):
        self.dragging=False;self.auto_tracking=False
        if not self.active():return
        args=(round(self.rows.get()),round(self.analog.get()),round(self.digital.get()))
        self.app._submit(lambda:(manual(self.client,*args),tuning(self.client)),self.show,'camera')

    def submit_auto(self):
        if self.active():self.app._submit(lambda:(auto_adjust(self.client),tuning(self.client)),self.show,'camera')

    def read(self):
        if self.active():self.app._submit(lambda:(camera_read(self.client),tuning(self.client)),self.show,'camera_read')

    def submit_tuning(self):
        if not self.active():return
        try:
            flags=sum(int(v.get())<<b for b,v in enumerate(self.flags));percent=self.percent.get()
            if not 25<=percent<=75:raise ValueError()
        except (ValueError,tk.TclError):self.status.set('低阈值比例请输入25～75，再回车。');return
        def confirmed(result):
            if self.active():self.status.set('算法设置已在帧边界确认生效。')
        self.app._submit(lambda:tuning(self.client,flags,percent),confirmed,'tuning')

    def recommended(self):
        for i,v in enumerate(self.flags):v.set(i<3)
        self.percent.set(50);self.submit_tuning()
