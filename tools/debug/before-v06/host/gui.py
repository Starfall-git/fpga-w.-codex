"""V0.5 / 23: live geometry controls and confirmed readback; COM stays off the UI thread."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from fractions import Fraction
import json
from pathlib import Path
import queue
import tkinter as tk
from tkinter import ttk, messagebox, filedialog
from .client import SerialClient, DemoClient, list_ports
from .protocol import (Command, Frame, CAP_THRESHOLD, CAP_FLIP, CAP_CROP, CAP_ZOOM,
                       threshold_payload, flip_payload, crop_payload, zoom_payload)


class ImageControlApp:
    def __init__(self, root, demo=False):
        self.root = root
        root.title("VF-Ti60 · 实时图像控制台")
        root.geometry("1060x880")
        root.minsize(1020, 820)
        self.executor = ThreadPoolExecutor(max_workers=1)
        self.events = queue.Queue()
        self.client = None
        self.busy = False
        self.closing = False
        self.caps = 0
        self.mode = tk.StringVar(value="模拟演示" if demo else "串口硬件")
        self.port = tk.StringVar()
        self.baud = tk.StringVar(value="115200")
        self.threshold = tk.StringVar(value="128")
        self.readback = tk.StringVar(value="—")
        self.connection = tk.StringVar(value="未连接")
        self.message = tk.StringVar(value="选择串口并连接；也可切换到模拟演示。")
        self.cap_text = tk.StringVar(value="等待查询设备能力")
        self.flip = tk.BooleanVar(value=False)
        self.flip_horizontal = tk.BooleanVar(value=False)
        self.geometry_readback = tk.StringVar(value="尚未回读图像变换配置")
        self.crop = {name: tk.StringVar(value=value) for name, value in
                     (("x", "0"), ("y", "0"), ("width", "1280"), ("height", "720"))}
        self.zoom = tk.StringVar(value="1")
        self.auto_poll = tk.BooleanVar(value=True)
        self._build()
        self.refresh_ports()
        root.protocol("WM_DELETE_WINDOW", self.close)
        root.after(50, self._drain)
        root.after(1500, self._poll)
        self._states()

    def _build(self):
        style = ttk.Style()
        if "clam" in style.theme_names():
            style.theme_use("clam")
        style.configure("TFrame", background="#f3f5f8")
        style.configure("TLabel", background="#f3f5f8", font=("Microsoft YaHei UI", 10))
        style.configure("TButton", padding=(12, 6), font=("Microsoft YaHei UI", 10))
        style.configure("TLabelframe", background="#f3f5f8")
        style.configure("TLabelframe.Label", font=("Microsoft YaHei UI", 11, "bold"))
        style.configure("Title.TLabel", font=("Microsoft YaHei UI", 21, "bold"), foreground="#17364c")
        style.configure("Value.TLabel", font=("Consolas", 26, "bold"), foreground="#137c70")
        main = ttk.Frame(self.root, padding=22)
        main.pack(fill="both", expand=True)
        ttk.Label(main, text="实时图像控制台", style="Title.TLabel").pack(anchor="w")
        ttk.Label(main, text="VF-Ti60F225  /  OV5640 → DDR3 → 几何变换 → Sobel → HDMI").pack(anchor="w", pady=(3, 16))
        connection = ttk.LabelFrame(main, text="01  连接设备", padding=12)
        connection.pack(fill="x")
        self.mode_box = ttk.Combobox(connection, textvariable=self.mode,
                                     values=("串口硬件", "模拟演示"), width=11, state="readonly")
        self.mode_box.grid(row=0, column=0, padx=(0, 9))
        self.mode_box.bind("<<ComboboxSelected>>", lambda _: self._states())
        self.port_box = ttk.Combobox(connection, textvariable=self.port, width=14, state="readonly")
        self.port_box.grid(row=0, column=1, padx=6)
        self.refresh_button = ttk.Button(connection, text="刷新串口", command=self.refresh_ports)
        self.refresh_button.grid(row=0, column=2, padx=6)
        ttk.Label(connection, text="波特率").grid(row=0, column=3, padx=(10, 2))
        self.baud_entry = ttk.Entry(connection, textvariable=self.baud, width=9)
        self.baud_entry.grid(row=0, column=4, padx=6)
        self.connect_button = ttk.Button(connection, text="连接", command=self.toggle_connection)
        self.connect_button.grid(row=0, column=5, padx=6)
        ttk.Label(connection, textvariable=self.connection).grid(row=0, column=6, padx=12)
        ttk.Label(connection, text="8N1 · 无流控 · 默认 115200；UART 仅传控制命令，图像仍从 HDMI 输出。",
                  foreground="#64748b").grid(row=1, column=0, columnspan=7, sticky="w", pady=(9, 0))

        threshold = ttk.LabelFrame(main, text="02  Sobel 阈值  ·  当前已实现", padding=14)
        threshold.pack(fill="x", pady=14)
        ttk.Label(threshold, text="输入阈值（0–4095）").grid(row=0, column=0, sticky="w")
        self.threshold_entry = ttk.Entry(threshold, textvariable=self.threshold, width=13, font=("Consolas", 17))
        self.threshold_entry.grid(row=1, column=0, sticky="w", pady=9)
        self.threshold_entry.bind("<Return>", lambda _: self.apply_threshold())
        self.apply_button = ttk.Button(threshold, text="确认并应用", command=self.apply_threshold)
        self.apply_button.grid(row=1, column=1, padx=16)
        self.query_button = ttk.Button(threshold, text="查询当前值", command=self.query)
        self.query_button.grid(row=1, column=2, padx=5)
        ttk.Checkbutton(threshold, text="定时回读按键变化", variable=self.auto_poll).grid(row=2, column=0, columnspan=3, sticky="w")
        ttk.Label(threshold, text="已确认值 · 模拟模式下为模拟回读").grid(row=0, column=3, padx=(30, 0), sticky="w")
        ttk.Label(threshold, textvariable=self.readback, style="Value.TLabel").grid(row=1, column=3, sticky="w", padx=(30, 0))
        ttk.Label(threshold, text="输入不会自动发送；确认后在 FPGA 场消隐生效，收到应答才更新右侧数值。",
                  foreground="#64748b").grid(row=3, column=0, columnspan=4, sticky="w", pady=(8, 0))

        future = ttk.LabelFrame(main, text="03  图像变换  ·  帧边界应用", padding=12)
        future.pack(fill="x")
        ttk.Label(future, text="先裁剪，再翻转、最近邻缩放；720p 居中显示，缩小补黑、放大截取。输入后点击应用。",
                  foreground="#64748b").pack(anchor="w", pady=(0, 10))
        tabs = ttk.Notebook(future)
        tabs.pack(fill="x")
        self.feature_buttons = []
        for title, capability, kind in (("上下 / 左右翻转", CAP_FLIP, "flip"), ("自定义裁剪", CAP_CROP, "crop"),
                                         ("放大 / 缩小", CAP_ZOOM, "zoom")):
            panel = ttk.Frame(tabs, padding=12)
            tabs.add(panel, text=title)
            if kind == "flip":
                ttk.Checkbutton(panel, text="上下翻转", variable=self.flip).pack(side="left", padx=5)
                ttk.Checkbutton(panel, text="左右翻转", variable=self.flip_horizontal).pack(side="left", padx=5)
            elif kind == "crop":
                for name, label in (("x", "X"), ("y", "Y"), ("width", "宽"), ("height", "高")):
                    ttk.Label(panel, text=label).pack(side="left", padx=(0, 5))
                    ttk.Entry(panel, textvariable=self.crop[name], width=6).pack(side="left", padx=(0, 12))
            else:
                ttk.Label(panel, text="倍率").pack(side="left", padx=(0, 9))
                ttk.Combobox(panel, textvariable=self.zoom, values=("0.25", "0.5", "1", "1.5", "2", "3", "4"),
                             width=10, state="readonly").pack(side="left")
            apply = ttk.Button(panel, text="应用到 FPGA", command=lambda k=kind: self.apply_feature(k))
            apply.pack(side="right", padx=6)
            self.feature_buttons.append((apply, capability))
            ttk.Button(panel, text="预览命令", command=lambda k=kind: self.preview(k)).pack(side="right", padx=6)
        bottom = ttk.Frame(future)
        bottom.pack(fill="x", pady=(10, 0))
        ttk.Label(bottom, textvariable=self.cap_text).pack(side="left")
        ttk.Button(bottom, text="保存配置草稿", command=self.save_draft).pack(side="right")
        self.reset_geometry_button = ttk.Button(bottom, text="恢复全图 / 1倍 / 不翻转", command=self.reset_geometry)
        self.reset_geometry_button.pack(side="right", padx=8)
        ttk.Label(future, textvariable=self.geometry_readback, wraplength=940,
                  foreground="#137c70").pack(fill="x", pady=(10,0))

        log_frame = ttk.LabelFrame(main, text="04  通信记录", padding=8)
        log_frame.pack(fill="both", expand=True, pady=(14, 8))
        self.log = tk.Text(log_frame, height=7, wrap="word", font=("Consolas", 10),
                           background="#142735", foreground="#d7e5ee", relief="flat", state="disabled")
        scroll = ttk.Scrollbar(log_frame, command=self.log.yview)
        self.log.configure(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        self.log.pack(fill="both", expand=True)
        ttk.Label(main, textvariable=self.message, wraplength=940, foreground="#17364c").pack(fill="x", anchor="w")

    def _states(self):
        connected = self.client is not None
        for widget in (self.mode_box, self.port_box):
            widget.configure(state="disabled" if connected or self.busy else "readonly")
        self.baud_entry.configure(state="disabled" if connected or self.busy else "normal")
        self.refresh_button.configure(state="disabled" if connected or self.busy else "normal")
        self.connect_button.configure(text="断开" if connected else "连接", state="disabled" if self.busy else "normal")
        enabled = connected and not self.busy
        self.apply_button.configure(state="normal" if enabled and self.caps & CAP_THRESHOLD else "disabled")
        self.query_button.configure(state="normal" if enabled else "disabled")
        for button, cap in self.feature_buttons:
            button.configure(state="normal" if enabled and self.caps & cap else "disabled")
        self.reset_geometry_button.configure(state="normal" if enabled and self.caps & 14 == 14 else "disabled")

    def _trace(self, direction, raw):
        self.events.put(("log", f"{direction}  {raw.hex(' ').upper()}"))

    def _log(self, message):
        self.log.configure(state="normal")
        self.log.insert("end", datetime.now().strftime("%H:%M:%S")+"  "+message+"\n")
        if int(self.log.index("end-1c").split(".")[0]) > 500:
            self.log.delete("1.0", "100.0")
        self.log.see("end")
        self.log.configure(state="disabled")

    def _submit(self, operation, success):
        if self.busy or self.closing:
            return
        self.busy = True
        self._states()
        future = self.executor.submit(operation)
        future.add_done_callback(lambda result: self.events.put(("done", result, success)))

    def _drain(self):
        while not self.events.empty():
            item = self.events.get_nowait()
            if item[0] == "log":
                self._log(item[1])
            else:
                self.busy = False
                try:
                    item[2](item[1].result())
                except Exception as error:
                    self.message.set(str(error))
                    self._log("错误  "+str(error))
                self._states()
        if not self.closing:
            self.root.after(50, self._drain)

    def refresh_ports(self):
        try:
            ports = list_ports()
            self.port_box.configure(values=[p[0] for p in ports])
            if ports and self.port.get() not in [p[0] for p in ports]:
                self.port.set(ports[0][0])
            if not ports:
                self.port.set("")
        except ImportError:
            self.message.set("串口模式需要 pyserial：pip install -r host/requirements.txt；模拟演示可直接使用。")

    def toggle_connection(self):
        if self.busy:
            return
        if self.client:
            backend = self.client
            def disconnected(_):
                self.client = None
                self.caps = 0
                self.readback.set("—")
                self.connection.set("未连接")
                self.cap_text.set("等待查询设备能力")
                self.geometry_readback.set("尚未回读图像变换配置")
                self.message.set("连接已断开。")
            self._submit(backend.close, disconnected)
            return
        try:
            mode, port, baud = self.mode.get(), self.port.get(), int(self.baud.get())
            if not 1200 <= baud <= 1000000:
                raise ValueError("波特率应为 1200～1000000，并与 FPGA 一致")
            if mode == "串口硬件" and not port:
                raise ValueError("请先选择串口")
        except ValueError as error:
            self.message.set(str(error))
            return
        def connect():
            backend = DemoClient(self._trace) if mode == "模拟演示" else SerialClient(port, baud, trace=self._trace)
            try:
                status = backend.get_status()
                geometry = backend.get_geometry() if status.capabilities & 14 else None
            except Exception:
                backend.close()
                raise
            return backend, status, geometry
        def connected(result):
            self.client, status, geometry = result
            self.connection.set("模拟 · 未连接硬件" if self.client.simulated else f"已连接 {port}")
            self._status(status)
            if geometry:
                self._geometry(geometry)
                self._load_geometry_draft(geometry)
            else:
                self.geometry_readback.set("当前 bitstream 仅支持阈值；请下载 V0.5 几何变换版本。")
        self.message.set("正在连接并查询协议版本及设备能力…")
        self._submit(connect, connected)

    def _status(self, status):
        self.caps = status.capabilities
        self.readback.set(str(status.threshold))
        names = [name for bit, name in ((1, "阈值"), (2, "翻转"), (4, "裁剪"), (8, "缩放")) if self.caps & bit]
        self.cap_text.set("设备能力："+" / ".join(names)+f"；协议 V{status.version}")
        prefix = "模拟回读" if self.client.simulated else "FPGA 已确认"
        self.message.set(f"{prefix}：当前阈值 {status.threshold}。")

    def apply_threshold(self):
        if not self.client or self.busy or not self.caps & CAP_THRESHOLD:
            return
        try:
            value = int(self.threshold.get())
            threshold_payload(value)
        except ValueError:
            self.message.set("阈值必须是 0～4095 的整数，未发送命令。")
            return
        self.message.set("已提交，等待 FPGA 在场消隐应用并返回确认…")
        self._submit(lambda: self.client.set_threshold(value), self._status)

    def query(self):
        if self.client and not self.busy:
            backend = self.client
            def read():
                status = backend.get_status()
                return status, backend.get_geometry() if status.capabilities & 14 else None
            def updated(result):
                self._status(result[0])
                if result[1]: self._geometry(result[1])
            self._submit(read, updated)

    def _poll(self):
        if self.auto_poll.get():
            self.query()
        if not self.closing:
            self.root.after(1500, self._poll)

    def _feature(self, kind):
        if kind == "flip":
            args = (self.flip.get(),self.flip_horizontal.get())
            return Command.SET_FLIP, flip_payload(*args), args
        if kind == "crop":
            args = tuple(int(self.crop[name].get()) for name in ("x", "y", "width", "height"))
            return Command.SET_CROP, crop_payload(*args), args
        value = Fraction(self.zoom.get())
        args = (value.numerator, value.denominator)
        return Command.SET_ZOOM, zoom_payload(*args), args

    def preview(self, kind):
        try:
            command, payload, _ = self._feature(kind)
            raw = Frame(0, command, payload).encode()
            self._log("草稿（未发送）  "+raw.hex(" ").upper())
            self.message.set("命令已校验并显示在记录中，尚未发送到硬件。")
        except (ValueError, ZeroDivisionError) as error:
            self.message.set("参数无效："+str(error))

    def apply_feature(self, kind):
        if not self.client or self.busy:
            return
        cap = {"flip": CAP_FLIP, "crop": CAP_CROP, "zoom": CAP_ZOOM}[kind]
        if not self.caps & cap:
            self.message.set("当前 RTL 尚未实现此功能。")
            return
        try:
            _, _, args = self._feature(kind)
        except (ValueError, ZeroDivisionError) as error:
            self.message.set(str(error))
            return
        operation = getattr(self.client, "set_"+kind)
        self.message.set("正在应用图像变换，等待帧边界确认和配置回读…")
        self._submit(lambda: operation(*args), self._geometry)

    def _geometry(self, geometry):
        prefix = "模拟回读" if self.client.simulated else "上次 FPGA 已确认"
        self.geometry_readback.set(
            f"{prefix}：上下 {'开' if geometry.vertical else '关'} / 左右 {'开' if geometry.horizontal else '关'}；"
            f"裁剪 ({geometry.x}, {geometry.y}, {geometry.width}, {geometry.height})；"
            f"倍率 {geometry.numerator}/{geometry.denominator}。")
        self.message.set(f"{prefix}：图像变换配置已回读，图像通过 HDMI 输出。")
        if geometry.faults:
            errors = []
            if geometry.faults & 1: errors.append("出现过显示缺行（已补黑）")
            if geometry.faults & 2: errors.append("出现过 DDR 读响应错误")
            self.message.set("硬件诊断："+"；".join(errors)+"。标志保持至 FPGA 复位。")

    def _load_geometry_draft(self, geometry):
        self.flip.set(geometry.vertical)
        self.flip_horizontal.set(geometry.horizontal)
        for name in self.crop: self.crop[name].set(str(getattr(geometry,name)))
        self.zoom.set(str(Fraction(geometry.numerator,geometry.denominator)))

    def reset_geometry(self):
        if not self.client or self.busy or self.caps & 14 != 14: return
        def updated(geometry):
            self._geometry(geometry)
            self._load_geometry_draft(geometry)
        self.message.set("依次恢复1倍缩放、全图裁剪和不翻转；每一步均等待硬件确认…")
        self._submit(self.client.reset_geometry, updated)

    def save_draft(self):
        try:
            value = int(self.threshold.get())
            threshold_payload(value)
            for kind in ("flip", "crop", "zoom"):
                self._feature(kind)
        except (ValueError, ZeroDivisionError) as error:
            self.message.set("不能保存："+str(error))
            return
        path = filedialog.asksaveasfilename(defaultextension=".json", initialfile="image_settings.json",
                                           filetypes=[("JSON 配置", "*.json")])
        if path:
            try:
                Path(path).write_text(json.dumps({"protocol_version": 1, "threshold": value,
                    "flip_vertical": self.flip.get(), "flip_horizontal": self.flip_horizontal.get(),
                    "crop": {k: int(v.get()) for k,v in self.crop.items()},
                    "zoom": str(Fraction(self.zoom.get())), "note": "配置草稿，不代表硬件已应用"},
                    ensure_ascii=False, indent=2), encoding="utf-8")
                self.message.set("配置草稿已保存。")
            except OSError as error:
                self.message.set("保存失败："+str(error))

    def close(self):
        if self.closing:
            return
        self.closing = True
        # Queue cleanup after any in-flight bounded serial operation, including connect.
        pending_client = self.client
        def cleanup():
            if pending_client:
                pending_client.close()
            while not self.events.empty():
                item = self.events.get_nowait()
                if item[0] == "done":
                    try:
                        result = item[1].result()
                        if isinstance(result, tuple) and hasattr(result[0], "close"):
                            result[0].close()
                    except Exception:
                        pass
        self.executor.submit(cleanup)
        self.executor.shutdown(wait=False)
        self.root.destroy()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--demo", action="store_true", help="Select simulation mode without opening a COM port")
    args = parser.parse_args()
    root = tk.Tk()
    ImageControlApp(root, demo=args.demo)
    root.mainloop()


if __name__ == "__main__":
    main()
