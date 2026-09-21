"""V0.4: serial request/response client. No implicit retries or background writes."""
import threading
import time
from .protocol import (Command, DeviceStatus, DeviceError, Frame, FrameDecoder,
                       CAP_THRESHOLD, CAP_FLIP, CAP_CROP, CAP_ZOOM,
                       threshold_payload, flip_payload, crop_payload, zoom_payload)


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
        self.lock = threading.Lock()
        self.trace = trace or (lambda direction, raw: None)
        self.status = None

    def request(self, command, payload=bytes(8)):
        with self.lock:
            sequence = self.sequence
            self.sequence = (sequence+1) & 255
            packet = Frame(sequence, command, payload).encode()
            decoder = FrameDecoder()
            self.trace("TX", packet)
            if self.transport.write(packet) != len(packet):
                raise OSError("串口未完整发送命令")
            deadline = time.monotonic()+self.timeout
            while time.monotonic() < deadline:
                raw = self.transport.read(128)
                if not raw:
                    continue
                self.trace("RX", raw)
                for frame in decoder.feed(raw):
                    if frame.sequence != sequence or frame.command != (command | 0x80):
                        continue
                    status = DeviceStatus.from_frame(frame)
                    self.status = status
                    if status.code:
                        raise DeviceError(status)
                    return status
            raise TimeoutError("未收到匹配的 FPGA 确认；是否生效未知，请查询回读后再操作")

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

    def set_flip(self, enabled):
        payload = flip_payload(enabled)
        self._require(CAP_FLIP)
        return self.request(Command.SET_FLIP, payload)

    def set_crop(self, x, y, width, height):
        payload = crop_payload(x, y, width, height)
        self._require(CAP_CROP)
        return self.request(Command.SET_CROP, payload)

    def set_zoom(self, numerator, denominator):
        payload = zoom_payload(numerator, denominator)
        self._require(CAP_ZOOM)
        return self.request(Command.SET_ZOOM, payload)

    def close(self):
        self.transport.close()


class DemoClient:
    """Explicit simulation mode: exercises GUI and protocol without opening COM."""
    simulated = True

    def __init__(self, trace=None):
        self.trace = trace or (lambda direction, raw: None)
        self.status = DeviceStatus(0, 128, 1, CAP_THRESHOLD)
        self.sequence = 0

    def _exchange(self, cmd, payload=bytes(8)):
        request = Frame(self.sequence, cmd, payload)
        self.trace("模拟TX", request.encode())
        if cmd == Command.SET_THRESHOLD:
            value = int.from_bytes(payload[:2], "little")
            self.status = DeviceStatus(0, value, 1, CAP_THRESHOLD)
        body = bytes((0, self.status.threshold & 255, self.status.threshold >> 8, 1, CAP_THRESHOLD, 0, 0, 0))
        self.trace("模拟RX", Frame(self.sequence, cmd | 0x80, body).encode())
        self.sequence = (self.sequence+1) & 255
        return self.status

    def get_status(self):
        return self._exchange(Command.GET_STATUS)

    def set_threshold(self, value):
        return self._exchange(Command.SET_THRESHOLD, threshold_payload(value))

    def close(self):
        pass
