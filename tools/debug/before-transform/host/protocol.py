"""V0.4: transport-independent protocol shared by GUI, tests and future tools."""
from dataclasses import dataclass
from enum import IntEnum
import struct

HEADER = b"\xa5\x5a"
FRAME_SIZE = 13
PROTOCOL_VERSION = 1
CAP_THRESHOLD, CAP_FLIP, CAP_CROP, CAP_ZOOM = 1, 2, 4, 8


class Command(IntEnum):
    GET_STATUS = 0x01
    SET_THRESHOLD = 0x10
    SET_FLIP = 0x20
    SET_CROP = 0x21
    SET_ZOOM = 0x22


def crc8(data: bytes) -> int:
    crc = 0
    for value in data:
        crc ^= value
        for _ in range(8):
            crc = ((crc << 1) ^ (0x07 if crc & 0x80 else 0)) & 0xff
    return crc


def _integer(value: int, low: int, high: int, name: str) -> int:
    if type(value) is not int or not low <= value <= high:
        raise ValueError(f"{name} 必须是 {low}～{high} 的整数")
    return value


@dataclass(frozen=True)
class Frame:
    sequence: int
    command: int
    payload: bytes = bytes(8)

    def encode(self) -> bytes:
        _integer(self.sequence, 0, 255, "序号")
        if not 0 <= self.command <= 255 or len(self.payload) != 8:
            raise ValueError("命令或数据长度错误")
        body = bytes((self.sequence, self.command)) + self.payload
        return HEADER + body + bytes((crc8(body),))

    @classmethod
    def decode(cls, raw: bytes):
        if len(raw) != FRAME_SIZE or raw[:2] != HEADER or crc8(raw[2:-1]) != raw[-1]:
            raise ValueError("帧头、长度或 CRC 错误")
        return cls(raw[2], raw[3], raw[4:12])


class FrameDecoder:
    """Accept split/coalesced serial reads and recover after garbage or bad CRC."""
    def __init__(self):
        self.buffer = bytearray()

    def feed(self, data: bytes) -> list[Frame]:
        self.buffer.extend(data)
        frames = []
        while True:
            pos = self.buffer.find(HEADER)
            if pos < 0:
                self.buffer[:] = self.buffer[-1:] if self.buffer[-1:] == b"\xa5" else b""
                break
            del self.buffer[:pos]
            if len(self.buffer) < FRAME_SIZE:
                break
            try:
                frame = Frame.decode(bytes(self.buffer[:FRAME_SIZE]))
            except ValueError:
                del self.buffer[0]
            else:
                frames.append(frame)
                del self.buffer[:FRAME_SIZE]
        return frames


def threshold_payload(value: int) -> bytes:
    return struct.pack("<H", _integer(value, 0, 4095, "阈值")) + bytes(6)


def flip_payload(enabled: bool) -> bytes:
    if type(enabled) is not bool:
        raise ValueError("翻转标志必须是布尔值")
    return bytes((int(enabled),)) + bytes(7)


def crop_payload(x: int, y: int, width: int, height: int,
                 image_width=1280, image_height=720) -> bytes:
    _integer(x, 0, image_width-1, "X")
    _integer(y, 0, image_height-1, "Y")
    _integer(width, 1, image_width, "裁剪宽度")
    _integer(height, 1, image_height, "裁剪高度")
    if x + width > image_width or y + height > image_height:
        raise ValueError("裁剪区域超出 1280×720 图像范围")
    return struct.pack("<HHHH", x, y, width, height)


def zoom_payload(numerator: int, denominator: int) -> bytes:
    _integer(numerator, 1, 16, "缩放分子")
    _integer(denominator, 1, 16, "缩放分母")
    if not 0.25 <= numerator / denominator <= 4:
        raise ValueError("缩放倍率必须为 0.25～4")
    return struct.pack("<HH", numerator, denominator) + bytes(4)


@dataclass(frozen=True)
class DeviceStatus:
    code: int
    threshold: int
    version: int
    capabilities: int

    @classmethod
    def from_frame(cls, frame: Frame):
        status = cls(frame.payload[0], int.from_bytes(frame.payload[1:3], "little"),
                     frame.payload[3], frame.payload[4])
        if status.version != PROTOCOL_VERSION:
            raise ValueError(f"协议版本不匹配：设备为 {status.version}")
        if status.threshold > 4095 or any(frame.payload[5:]):
            raise ValueError("设备状态字段不合法")
        return status


class DeviceError(RuntimeError):
    def __init__(self, status: DeviceStatus):
        self.status = status
        meanings = {1: "FPGA 检测到 CRC 错误", 2: "FPGA 拒绝参数", 3: "当前 RTL 尚未实现此功能"}
        super().__init__(meanings.get(status.code, f"设备错误 {status.code}"))
