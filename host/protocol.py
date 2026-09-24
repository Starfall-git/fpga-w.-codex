"""V0.4: transport-independent protocol shared by GUI, tests and future tools."""
from dataclasses import dataclass
from enum import IntEnum
import struct
from decimal import Decimal
from fractions import Fraction
import re

HEADER = b"\xa5\x5a"
FRAME_SIZE = 13
PROTOCOL_VERSION = 1
CAP_THRESHOLD, CAP_FLIP, CAP_CROP, CAP_ZOOM = 1, 2, 4, 8
CAP_ISP, CAP_WIDE_ZOOM, CAP_DEFAULTS = 16, 32, 64  # V0.6
CAP_MEDIAN = 128  # V0.9: runtime optional Median


class Command(IntEnum):
    GET_STATUS = 0x01
    # V0.5: four-page readback of committed geometry; V1 framing is unchanged.
    GET_CONFIG = 0x02
    SET_THRESHOLD = 0x10
    SET_ISP = 0x11
    DEFAULTS = 0x12
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


def flip_payload(enabled: bool, horizontal: bool = False) -> bytes:
    """V0.5: bit0 vertical (V0.4 compatible), bit1 horizontal."""
    if type(enabled) is not bool or type(horizontal) is not bool:
        raise ValueError("翻转标志必须是布尔值")
    return bytes((int(enabled) | (int(horizontal) << 1),)) + bytes(7)


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
    # V0.6: full uint16 ratios support percentages without floating-point rounding.
    _integer(numerator, 1, 65535, "缩放分子")
    _integer(denominator, 1, 65535, "缩放分母")
    if numerator*10 < denominator or numerator > denominator*5:
        raise ValueError("缩放范围必须为 10%～500%")
    return struct.pack("<HH", numerator, denominator) + bytes(4)


def percent_ratio(text: str) -> tuple[int, int]:
    """V0.6: 10..500 percent, optional %, up to two decimal places."""
    value = text.strip().removesuffix('%').strip()
    if not re.fullmatch(r'\d+(?:\.\d{1,2})?', value):
        raise ValueError("请输入10%～500%，最多两位小数，按回车应用")
    number = Decimal(value)
    if not Decimal(10) <= number <= Decimal(500):
        raise ValueError("缩放范围必须为10%～500%")
    ratio = Fraction(number)/100
    return ratio.numerator, ratio.denominator


def isp_payload(enabled: bool, inverted: bool, median: bool = False) -> bytes:
    # V0.9 / 45: retain the first two bits for older firmware.
    if any(type(value) is not bool for value in (enabled, inverted, median)):
        raise ValueError("Sobel、反相和中值滤波状态必须为布尔值")
    return bytes((int(enabled) | (int(inverted)<<1) | (int(median)<<2),))+bytes(7)


@dataclass(frozen=True)
class DeviceStatus:
    code: int
    threshold: int
    version: int
    capabilities: int
    isp_flags: int = 0

    @property
    def sobel_enabled(self): return bool(self.isp_flags & 1)

    @property
    def inverted(self): return bool(self.isp_flags & 2)

    @property
    def median_enabled(self): return bool(self.isp_flags & 4)

    @classmethod
    def from_frame(cls, frame: Frame):
        status = cls(frame.payload[0], int.from_bytes(frame.payload[1:3], "little"),
                     frame.payload[3], frame.payload[4], frame.payload[5])
        if status.version != PROTOCOL_VERSION:
            raise ValueError(f"协议版本不匹配：设备为 {status.version}")
        # V0.9 / 45: bit2 is valid only when capability bit7 is advertised.
        if (status.threshold > 4095 or any(frame.payload[6:]) or status.isp_flags>7 or
                (status.isp_flags and not status.capabilities & CAP_ISP) or
                (status.median_enabled and not status.capabilities & CAP_MEDIAN)):
            raise ValueError("设备状态字段不合法")
        return status


class DeviceError(RuntimeError):
    def __init__(self, status: DeviceStatus):
        self.status = status
        meanings = {1: "FPGA 检测到 CRC 错误", 2: "FPGA 拒绝参数", 3: "当前 RTL 尚未实现此功能"}
        super().__init__(meanings.get(status.code, f"设备错误 {status.code}"))


@dataclass(frozen=True)
class Geometry:
    """V0.5: confirmed settings, distinct from GUI draft values."""
    vertical: bool = False
    horizontal: bool = False
    x: int = 0
    y: int = 0
    width: int = 1280
    height: int = 720
    numerator: int = 1
    denominator: int = 1
    faults: int = 0

    @classmethod
    def from_pages(cls, pages):
        if len(pages) != 4:
            raise ValueError("配置回读页数错误")
        for index, raw in enumerate(pages):
            if len(raw) != 8 or raw[0] or raw[1] != index:
                raise ValueError("配置回读状态或页号错误")
            if any(raw[4:] if index == 0 else raw[6:]):
                raise ValueError("配置回读保留字段错误")
        flags, faults = pages[0][2:4]
        if flags > 3 or faults > 3:
            raise ValueError("配置回读标志错误")
        x,y = struct.unpack('<HH',pages[1][2:6])
        w,h = struct.unpack('<HH',pages[2][2:6])
        n,d = struct.unpack('<HH',pages[3][2:6])
        crop_payload(x,y,w,h)
        zoom_payload(n,d)
        if w*n < d or h*n < d:
            raise ValueError("缩放后图像尺寸不足一个像素")
        return cls(bool(flags & 1),bool(flags & 2),x,y,w,h,n,d,faults)
