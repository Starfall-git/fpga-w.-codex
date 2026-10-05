"""Independent inference/overlay controls with acknowledged FPGA readback."""
import time
import tkinter as tk
from tkinter import ttk
from .protocol import CAP_ADV_CNN, CnnError


class CnnPanel:
    def __init__(self, app):
        self.app = app
        self.window = tk.Toplevel(app.root)
        self.window.title('TinyML 手势 · 推理与叠加')
        self.window.geometry('620x320')
        self.window.minsize(560, 300)
        self.inference = tk.BooleanVar(value=False)
        self.overlay = tk.BooleanVar(value=False)
        self.readback = tk.StringVar(value='尚未读取设备状态')
        self.hint = tk.StringVar()
        self.status = None
        self.owner = app.client
        body = ttk.Frame(self.window, padding=18)
        body.pack(fill='both', expand=True)
        ttk.Label(body, text='TinyML 手势识别', font=('Microsoft YaHei UI', 15, 'bold')).pack(anchor='w')
        ttk.Label(body, textvariable=self.readback, wraplength=570).pack(anchor='w', pady=12)
        row = ttk.Frame(body); row.pack(fill='x')
        self.inference_box = ttk.Checkbutton(row, text='启用推理', variable=self.inference)
        self.inference_box.pack(side='left', padx=(0, 25))
        self.overlay_box = ttk.Checkbutton(row, text='叠加识别结果', variable=self.overlay)
        self.overlay_box.pack(side='left')
        row = ttk.Frame(body); row.pack(fill='x', pady=14)
        self.apply_button = ttk.Button(row, text='应用设置', command=self.apply)
        self.apply_button.pack(side='left')
        self.refresh_button = ttk.Button(row, text='读取实际状态', command=self.refresh)
        self.refresh_button.pack(side='left', padx=10)
        ttk.Label(body, textvariable=self.hint, wraplength=570).pack(anchor='w')
        ttk.Label(body, text='静态自检版尚未启用实时摄像头推理；打开叠加也不会凭空产生识别结果。',
                  wraplength=570, foreground='#64748b').pack(anchor='w', pady=12)
        self.sync()
        self.refresh()

    def supported(self):
        client = self.app.client
        return bool(client and client.status and client.status.advanced_capabilities & CAP_ADV_CNN)

    def sync(self):
        if not self.window.winfo_exists():
            return
        if self.owner is not self.app.client:
            self.owner = self.app.client
            self.status = None
            self.inference.set(False); self.overlay.set(False)
            self.readback.set('尚未读取设备状态')
        supported = self.supported()
        idle = supported and not (self.app.busy or self.app.pending or self.app.resetting)
        self.refresh_button.configure(state='normal' if idle else 'disabled')
        valid = idle and self.status is not None
        self.apply_button.configure(state='normal' if valid else 'disabled')
        self.overlay_box.configure(state='normal' if valid else 'disabled')
        self.inference_box.configure(state='normal' if valid and (self.status.available or self.status.applied & 1) else 'disabled')
        if not self.app.client:
            self.hint.set('先在主窗口连接设备，再读取实际状态。')
        elif not supported:
            self.hint.set('当前 bitstream 未声明 TinyML 控制能力，原图像功能仍可使用。')
        elif self.status is None:
            self.hint.set('请读取状态；尚未确认推理固件是否就绪。')

    def show(self, status):
        if not self.window.winfo_exists():
            return
        self.status = status
        self.inference.set(bool(status.applied & 1))
        self.overlay.set(bool(status.applied & 2))
        label = lambda flags: f'推理{"开" if flags & 1 else "关"} / 叠加{"开" if flags & 2 else "关"}'
        prefix = '模拟演示 · ' if self.app.client.simulated else ''
        self.readback.set(prefix + f'实际：{label(status.applied)}；请求：{label(status.requested)}')
        self.hint.set('推理固件已就绪。' if status.available else '推理固件未就绪：静态自检版属于此状态，启用推理暂不可用。')
        if status.code:
            self.hint.set(f'设备拒绝或未完成设置（状态码 {status.code}）；以上显示实际回读，请勿当作已生效。')
        self.sync()

    def fail(self, error):
        if not self.window.winfo_exists():
            return
        if isinstance(error, CnnError):
            self.show(error.status)
        else:
            self.status = None
            self.readback.set('本次未获得确认；最后一次显示不能代表当前状态。')
            self.sync()
        self.hint.set(str(error) + '；请重新读取实际状态。')

    def refresh(self):
        if not self.supported():
            self.sync(); return
        client = self.app.client
        self.app._submit(client.get_cnn, self.show, 'cnn_read')

    def apply(self):
        if not self.supported() or self.status is None:
            return
        inference, overlay = self.inference.get(), self.overlay.get()
        if inference and not self.status.available:
            self.hint.set('固件尚未就绪；请关闭“启用推理”或先加载实时推理固件。')
            return
        self.app.last_interaction = time.monotonic()
        client = self.app.client
        self.app._submit(lambda: client.set_cnn(inference, overlay), self.show, 'cnn_set')
