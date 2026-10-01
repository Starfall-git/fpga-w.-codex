"""V0.15 / 73: replaceable HDMI capture boundary; never falls back to UART.
A future capture adapter should decode on its own worker thread and return a
non-blocking latest() snapshot. Host HDMI input requires a capture device/API.
"""
from dataclasses import dataclass
from typing import Protocol
from PIL import Image, ImageTk
import tkinter as tk
from tkinter import ttk

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

class HDMIPreview:
    def __init__(self,parent,source,store):
        self.source,self.store=source,store
        self.win=tk.Toplevel(parent);self.win.title('HDMI实时图像 · 采集接口');self.win.geometry('900x620')
        self.status=tk.StringVar(value='HDMI采集通路尚未接入；串口仅用于控制。')
        ttk.Label(self.win,textvariable=self.status,padding=8).pack(fill='x')
        self.save_button=ttk.Button(self.win,text='保存HDMI当前图像到本地仓库',command=self.save)
        self.save_button.pack();self.label=ttk.Label(self.win,anchor='center');self.label.pack(fill='both',expand=True)
        self.timer=None;self.last=None;self.sequence=None;self.win.protocol('WM_DELETE_WINDOW',self.close)
        self.update()
    def update(self):
        self.save_button.configure(state='normal' if self.source.available and self.last else 'disabled')
        try:frame=self.source.latest() if self.source.available else None
        except Exception as error:
            frame=None;self.status.set('HDMI采集错误：'+str(error))
        if frame is not None and frame.sequence!=self.sequence:
            self.last=frame;self.sequence=frame.sequence
            image=frame.image.copy();image.thumbnail((max(1,self.label.winfo_width()),max(1,self.label.winfo_height())))
            self.photo=ImageTk.PhotoImage(image,master=self.win);self.label.configure(image=self.photo)
            self.status.set(f'HDMI帧 {frame.sequence} · {frame.image.width}×{frame.image.height}')
        self.timer=self.win.after(33,self.update)
    def save(self):
        if self.last is not None:
            try:
                path=self.store.save(self.last.image);self.status.set('已保存：'+path.name)
            except OSError as error:self.status.set('保存失败：'+str(error))
    def close(self):
        if self.timer:self.win.after_cancel(self.timer)
        self.win.destroy()
