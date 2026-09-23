"""V0.4: serial request/response client. No implicit retries or background writes."""
import threading
import time
from dataclasses import replace
from .protocol import (Command, DeviceStatus, DeviceError, Frame, FrameDecoder,
                       CAP_THRESHOLD, CAP_FLIP, CAP_CROP, CAP_ZOOM,
                       threshold_payload, flip_payload, crop_payload, zoom_payload, Geometry,
                       CAP_ISP, CAP_DEFAULTS, CAP_WIDE_ZOOM, isp_payload)


def list_ports():
    from serial.tools import list_ports as ports
    return [(p.device, p.description) for p in ports.comports()]


class SerialClient:
    simulated = False

    def __init__(self, port=None, baud=115200, timeout=1.0, transport=None, trace=None):
        if transport is None:
            import serial
            transport = serial.Serial(port=None, baudrate=baud, bytesize=8, parity="N", stopbits=1,
                                      timeout=0.05, write_timeout=0.5, xonxoff=False, rtscts=False)
            transport.dtr = False
            transport.rts = False
            transport.port = port
            try:
                transport.open()
            except Exception:
                transport.close()
                raise
        self.transport = transport
        self.timeout = timeout
        self.sequence = 0
        self.lock = threading.RLock()
        self.trace = trace or (lambda direction, raw: None)
        self.status = None
        self.geometry = None
        self.last_roundtrip_ms = 0.0

    # V0.5: raw exchange supports command-specific GET_CONFIG response payloads.
    def _exchange(self, command, payload=bytes(8)):
        with self.lock:
            sequence = self.sequence
            self.sequence = (sequence+1) & 255
            packet = Frame(sequence, command, payload).encode()
            started = time.monotonic()
            decoder = FrameDecoder()
            self.trace("TX", packet)
            if self.transport.write(packet) != len(packet):
                raise OSError("串口未完整发送命令")
            deadline = time.monotonic()+self.timeout
            while time.monotonic() < deadline:
                # V0.6: read(128) used to wait for a 50ms timeout for a 13-byte reply.
                # Block for the first byte only, then drain bytes already available.
                raw = self.transport.read(min(128, max(1, getattr(self.transport, 'in_waiting', 0))))
                if not raw:
                    continue
                self.trace("RX", raw)
                for frame in decoder.feed(raw):
                    if frame.sequence != sequence or frame.command != (command | 0x80):
                        continue
                    self.last_roundtrip_ms = (time.monotonic()-started)*1000
                    return frame
            raise TimeoutError("未收到匹配的 FPGA 确认；是否生效未知，请查询回读后再操作")

    def request(self, command, payload=bytes(8)):
        frame = self._exchange(command, payload)
        status = DeviceStatus.from_frame(frame)
        self.status = status
        if status.code:
            raise DeviceError(status)
        return status

    def get_status(self):
        return self.request(Command.GET_STATUS)

    def _require(self, capability):
        if self.status is None:
            self.get_status()
        if not self.status.capabilities & capability:
            raise RuntimeError("当前设备未声明支持此功能，未发送命令")

    def set_threshold(self, value):
        payload = threshold_payload(value)
        self._require(CAP_THRESHOLD)
        result = self.request(Command.SET_THRESHOLD, payload)
        if result.threshold != value:
            raise RuntimeError(f"设备确认值 {result.threshold} 与请求值 {value} 不一致")
        return result

    def get_geometry(self):
        self._require(CAP_FLIP | CAP_CROP | CAP_ZOOM)
        with self.lock:
            pages = []
            for page in range(4):
                frame = self._exchange(Command.GET_CONFIG, bytes((page,))+bytes(7))
                if frame.payload[0]:
                    raise RuntimeError(f"设备拒绝配置查询，状态 {frame.payload[0]}")
                pages.append(frame.payload)
            self.geometry = Geometry.from_pages(pages)
            return self.geometry

    def set_flip(self, enabled, horizontal=False):
        payload = flip_payload(enabled, horizontal)
        self._require(CAP_FLIP)
        with self.lock:
            self.request(Command.SET_FLIP, payload)
            result = self.get_geometry()
            if (result.vertical, result.horizontal) != (enabled, horizontal):
                raise RuntimeError("翻转回读与请求不一致")
            return result

    def set_crop(self, x, y, width, height):
        payload = crop_payload(x, y, width, height)
        self._require(CAP_CROP)
        with self.lock:
            self.request(Command.SET_CROP, payload)
            result = self.get_geometry()
            if (result.x,result.y,result.width,result.height) != (x,y,width,height):
                raise RuntimeError("裁剪回读与请求不一致")
            return result

    def set_zoom(self, numerator, denominator):
        payload = zoom_payload(numerator, denominator)
        self._require(CAP_ZOOM)
        if not self.status.capabilities & CAP_WIDE_ZOOM and not (numerator<=16 and denominator<=16 and denominator<=4*numerator and numerator<=4*denominator):
            raise RuntimeError("当前bit只支持旧倍率范围，请下载V0.6 bitstream")
        with self.lock:
            self.request(Command.SET_ZOOM, payload)
            result = self.get_geometry()
            if (result.numerator,result.denominator) != (numerator,denominator):
                raise RuntimeError("缩放回读与请求不一致")
            return result

    def reset_geometry(self):
        """Three acknowledged frame commits; safe even after a one-pixel crop."""
        with self.lock:
            self.set_zoom(1,1)
            self.set_crop(0,0,1280,720)
            return self.set_flip(False,False)

    def set_isp(self, enabled, inverted):
        payload = isp_payload(enabled, inverted)
        self._require(CAP_ISP)
        result = self.request(Command.SET_ISP, payload)
        if result.isp_flags != payload[0]: raise RuntimeError("图像模式回读与请求不一致")
        return result

    def reset_defaults(self):
        """V0.6: one device command owns defaults, including future device features."""
        self._require(CAP_DEFAULTS)
        with self.lock:
            status = self.request(Command.DEFAULTS)
            geometry = self.get_geometry() if status.capabilities & CAP_CROP else None
            if status.isp_flags or (geometry and replace(geometry,faults=0) != Geometry()):
                raise RuntimeError("默认设置回读不一致")
            return status, geometry

    def close(self):
        self.transport.close()


class DemoClient(SerialClient):
    """Explicit simulation mode: exercises GUI and protocol without opening COM."""
    simulated = True

    def __init__(self, trace=None):
        self.trace = trace or (lambda direction, raw: None)
        self.status = DeviceStatus(0, 128, 1, 127)
        self.geometry = Geometry()
        self.lock = threading.RLock()
        self.sequence = 0
        self.last_roundtrip_ms = 0.0

    def _exchange(self, cmd, payload=bytes(8)):
        request = Frame(self.sequence, cmd, payload)
        self.trace("模拟TX", request.encode())
        code = 0
        candidate = self.geometry
        if cmd == Command.SET_THRESHOLD:
            value = int.from_bytes(payload[:2], "little")
            self.status = replace(self.status, code=0, threshold=value)
        elif cmd == Command.SET_ISP:
            self.status = replace(self.status, code=0, isp_flags=payload[0])
        elif cmd == Command.DEFAULTS:
            self.status = replace(self.status, code=0, isp_flags=0)
            candidate = Geometry()
        elif cmd == Command.SET_FLIP:
            candidate = replace(candidate,vertical=bool(payload[0]&1),horizontal=bool(payload[0]&2))
        elif cmd == Command.SET_CROP:
            values = [int.from_bytes(payload[i:i+2],'little') for i in range(0,8,2)]
            candidate = replace(candidate,x=values[0],y=values[1],width=values[2],height=values[3])
        elif cmd == Command.SET_ZOOM:
            candidate = replace(candidate,numerator=int.from_bytes(payload[:2],'little'),denominator=int.from_bytes(payload[2:4],'little'))
        elif cmd not in (Command.GET_STATUS,Command.GET_CONFIG):
            code = 3
        if candidate.width*candidate.numerator < candidate.denominator or candidate.height*candidate.numerator < candidate.denominator:
            code = 2
        if code == 0:
            self.geometry = candidate
        body = bytes((code, self.status.threshold & 255, self.status.threshold >> 8, 1, 127, self.status.isp_flags, 0, 0))
        if cmd == Command.GET_CONFIG:
            g = self.geometry
            page = payload[0]
            pairs = ((int(g.vertical)|(int(g.horizontal)<<1),g.faults),(g.x,g.y),(g.width,g.height),(g.numerator,g.denominator))
            if page < 4:
                values = bytes(pairs[0])+bytes(4) if page == 0 else b''.join(v.to_bytes(2,'little') for v in pairs[page])+bytes(2)
                body = bytes((0,page))+values
            else:
                body = bytes((2,page))+bytes(6)
        response = Frame(self.sequence, cmd | 0x80, body)
        self.trace("模拟RX", response.encode())
        self.sequence = (self.sequence+1) & 255
        return response

    def close(self):
        pass
