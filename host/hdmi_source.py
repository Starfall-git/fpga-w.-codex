"""V0.17 / 80-82: USB capture implements the V0.15 HDMI boundary.
Driver reads stay on a worker; Tk receives only the latest RGB image.
UART remains control-only. Closing the preview releases capture asynchronously.
"""
from dataclasses import dataclass
from typing import Protocol
from PIL import Image, ImageTk
import tkinter as tk
from tkinter import ttk, filedialog
import threading
import time
from pathlib import Path
from datetime import datetime

@dataclass(frozen=True)
class HDMIFrame:
    image: Image.Image
    sequence: int
    timestamp: float

class HDMIFrameSource(Protocol):
    @property
    def available(self) -> bool: ...
    def latest(self) -> HDMIFrame | None: ...
    def close(self) -> None: ...

class PendingHDMISource:
    available=False
    def latest(self):return None
    def close(self):pass

# V0.17 / 80: USB UVC capture owns all blocking driver operations on a worker.
class USBCaptureSource:
    def __init__(self):
        self._lock=threading.Lock();self._stop=threading.Event();self._thread=None
        self._frame=None;self._sequence=0;self.status='请选择USB采集卡并开始预览'

    @staticmethod
    def devices():
        import cv2
        from cv2_enumerate_cameras import enumerate_cameras
        return [(c.index,c.name) for c in enumerate_cameras(cv2.CAP_DSHOW)]

    @property
    def running(self):return self._thread is not None and self._thread.is_alive()
    @property
    def available(self):return self.latest() is not None
    def latest(self):
        with self._lock:
            frame=self._frame
        return frame if frame and time.monotonic()-frame.timestamp<2 and not self._stop.is_set() else None

    def start(self,index,width=1280,height=720,fps=60):
        if self.running:raise RuntimeError('采集仍在运行或停止中，请稍后重试')
        self._stop.clear()
        with self._lock:self._frame=None
        self.status='正在打开采集卡…'
        self._thread=threading.Thread(target=self._capture,args=(index,width,height,fps),daemon=True)
        self._thread.start()

    def _capture(self,index,width,height,fps):
        cap=None
        try:
            import cv2
            cap=cv2.VideoCapture(index,cv2.CAP_DSHOW)
            if not cap.isOpened():raise RuntimeError('无法打开设备；请关闭占用采集卡的其他软件')
            cap.set(cv2.CAP_PROP_FOURCC,cv2.VideoWriter_fourcc(*'MJPG'))
            cap.set(cv2.CAP_PROP_FRAME_WIDTH,width);cap.set(cv2.CAP_PROP_FRAME_HEIGHT,height)
            cap.set(cv2.CAP_PROP_FPS,fps)
            count=0;since=time.monotonic();measured=0.0;failures=0
            while not self._stop.is_set():
                ok,bgr=cap.read()
                if not ok:
                    failures+=1
                    if failures>=30:raise RuntimeError('没有收到视频帧，请检查HDMI输入、USB连接或重新开始')
                    self._stop.wait(.03);continue
                failures=0
                image=Image.fromarray(cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB))
                now=time.monotonic();count+=1
                if now-since>=1:measured=count/(now-since);count=0;since=now
                with self._lock:
                    self._sequence+=1;self._frame=HDMIFrame(image,self._sequence,now)
                self.status=f'USB采集：{image.width}×{image.height} · 实测 {measured:.1f} 帧/秒'
        except Exception as error:self.status='采集失败：'+str(error)
        finally:
            if cap is not None:cap.release()
            with self._lock:self._frame=None
            if self._stop.is_set():self.status='采集已停止'

    def close(self):
        # Never release a driver from another thread or block Tk on a stuck read.
        self._stop.set()
        with self._lock:self._frame=None


class HDMIPreview:
    def __init__(self,parent,source,store):
        self.source,self.store=source,store
        self.win=tk.Toplevel(parent);self.win.title('HDMI实时预览 · USB采集卡');self.win.geometry('1000x740')
        self.status=tk.StringVar(value='请选择采集卡；HDMI OUT直通显示不受预览开关影响。')
        self.saved=tk.StringVar();self.device=tk.StringVar();self.mode=tk.StringVar(value='1280×720 / 60')
        bar=ttk.Frame(self.win,padding=8);bar.pack(fill='x')
        self.box=ttk.Combobox(bar,textvariable=self.device,state='readonly',width=32);self.box.pack(side='left')
        ttk.Button(bar,text='刷新设备',command=self.refresh).pack(side='left',padx=4)
        ttk.Combobox(bar,textvariable=self.mode,state='readonly',width=18,values=('1280×720 / 60','1280×720 / 30','1920×1080 / 30')).pack(side='left')
        ttk.Button(bar,text='开始预览',command=self.start).pack(side='left',padx=4)
        ttk.Button(bar,text='停止',command=self.stop).pack(side='left')
        ttk.Label(self.win,textvariable=self.status,padding=8).pack(fill='x')
        buttons=ttk.Frame(self.win);buttons.pack(fill='x',padx=8)
        self.save_button=ttk.Button(buttons,text='保存当前帧到仓库',command=self.save);self.save_button.pack(side='left')
        self.export_button=ttk.Button(buttons,text='当前帧另存为…',command=self.export);self.export_button.pack(side='left',padx=8)
        ttk.Label(self.win,textvariable=self.saved,wraplength=950).pack(fill='x',padx=8)
        self.label=ttk.Label(self.win,anchor='center');self.label.pack(fill='both',expand=True)
        self.timer=None;self.last=None;self.sequence=None;self.size=None;self.win.protocol('WM_DELETE_WINDOW',self.close)
        self.refresh();self.update()

    def refresh(self):
        if not hasattr(self.source,'devices'):return
        try:
            self.devices=self.source.devices()
            values=[f'{name} [设备 {index}]' for index,name in self.devices];self.box['values']=values
            if values:
                selected=next((i for i,(_,n) in enumerate(self.devices) if 'hagibis' in n.lower()),0)
                self.box.current(selected)
            else:self.device.set('');self.status.set('未发现视频采集设备，请检查USB连接。')
        except Exception as error:self.status.set('设备枚举失败：'+str(error)+'；请安装host/requirements.txt依赖。')

    def start(self):
        if not hasattr(self.source,'start'):return
        try:
            i=self.box.current()
            if i<0:raise ValueError('请先选择USB采集卡')
            width,height,fps=self.mode.get().replace('×',' ').replace('/',' ').split()
            self.source.start(self.devices[i][0],int(width),int(height),int(fps))
            self.last=None;self.sequence=None
        except Exception as error:self.saved.set(str(error))

    def stop(self):
        self.source.close();self.last=None;self.label.configure(image='');self.saved.set('已请求停止采集')

    def update(self):
        # V0.18: manual refresh must not create an extra orphaned Tk timer.
        if self.timer:self.win.after_cancel(self.timer);self.timer=None
        try:frame=self.source.latest()
        except Exception as error:
            frame=None;self.saved.set('读取失败：'+str(error))
        enabled=frame is not None
        for button in (self.save_button,self.export_button):button.configure(state='normal' if enabled else 'disabled')
        self.status.set(getattr(self.source,'status','HDMI采集接口尚未提供图像'))
        if frame is None:
            self.last=None;self.label.configure(image='');self.sequence=None
        else:
            self.last=frame
            size=(max(1,self.label.winfo_width()),max(1,self.label.winfo_height()))
            if frame.sequence!=self.sequence or size!=self.size:
                self.sequence=frame.sequence;self.size=size
                image=frame.image.copy();image.thumbnail(size)
                self.photo=ImageTk.PhotoImage(image,master=self.win);self.label.configure(image=self.photo)
        self.timer=self.win.after(33,self.update)

    def save(self):
        frame=self.source.latest()
        if frame:
            try:self.saved.set('已加入本地仓库：'+str(self.store.save(frame.image)))
            except OSError as error:self.saved.set('保存失败：'+str(error))

    def export(self):
        # Snapshot before opening the dialog; save full resolution, not preview size.
        frame=self.source.latest()
        if frame is None:return
        path=filedialog.asksaveasfilename(parent=self.win,title='保存当前HDMI图像',defaultextension='.png',initialfile=datetime.now().strftime('HDMI-%Y%m%d-%H%M%S.png'),filetypes=[('PNG图像','*.png'),('JPEG图像','*.jpg')])
        if path:
            try:
                frame.image.save(path);self.saved.set('已保存：'+path)
            except (OSError,ValueError) as error:self.saved.set('保存失败：'+str(error))

    def close(self):
        if self.timer:self.win.after_cancel(self.timer)
        self.source.close();self.win.destroy()
