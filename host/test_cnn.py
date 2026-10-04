import unittest
from .protocol import Frame, CnnStatus, CnnError, cnn_payload, DeviceStatus
from .client import SerialClient


class Transport:
    def __init__(self, capability=63, timeout=False, mismatch=False):
        self.capability=capability; self.timeout=timeout; self.mismatch=mismatch
        self.buffer=bytearray(); self.writes=[]; self.state=0
    def write(self, raw):
        f=Frame.decode(raw); self.writes.append(f.command)
        if f.command==1: p=bytes((0,128,0,1,255,0,self.capability,0))
        else:
            wanted=f.payload[0] if f.command==0x51 else self.state
            actual=self.state if self.timeout or self.mismatch else wanted
            p=bytes((5 if self.timeout else 0,actual,wanted,1,1,0,0,0))
            self.state=actual
        self.buffer.extend(Frame(f.sequence,f.command|128,p).encode())
        return len(raw)
    def read(self, size):
        raw=bytes(self.buffer[:size]); del self.buffer[:size]; return raw


class CnnTests(unittest.TestCase):
    def test_independent_controls(self):
        t=Transport(); c=SerialClient(transport=t)
        for state in range(4):
            result=c.set_cnn(bool(state&1),bool(state&2))
            self.assertEqual(result.applied,state)
            self.assertEqual(c.get_cnn().applied,state)
    def test_legacy_never_receives_new_command(self):
        t=Transport(capability=31); c=SerialClient(transport=t)
        with self.assertRaises(RuntimeError): c.set_cnn(True,True)
        self.assertEqual(t.writes,[1])
    def test_timeout_keeps_actual_and_requested_distinct(self):
        c=SerialClient(transport=Transport(timeout=True))
        with self.assertRaises(CnnError) as caught: c.set_cnn(True,True)
        self.assertEqual((caught.exception.status.applied,caught.exception.status.requested),(0,3))
    def test_false_ack_rejected(self):
        with self.assertRaises(RuntimeError): SerialClient(transport=Transport(mismatch=True)).set_cnn(True,True)
    def test_bad_abi_reserved_bits_and_types(self):
        with self.assertRaises(ValueError): cnn_payload(1,False)
        for p in [bytes((0,4,0,1,1,0,0,0)),bytes((0,0,0,1,2,0,0,0)),bytes((0,0,0,1,1,0,0,1))]:
            with self.assertRaises(ValueError): CnnStatus.from_frame(Frame(1,0xd0,p))
        for cap in (47,63):
            self.assertEqual(DeviceStatus.from_frame(Frame(1,0x81,bytes((0,128,0,1,255,0,cap,0)))).advanced_capabilities,cap)

if __name__=='__main__': unittest.main()
