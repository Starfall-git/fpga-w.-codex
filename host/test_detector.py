"""v1.2 / 16: Real-format location status, old firmware and GUI compatibility."""
import threading,unittest
from types import SimpleNamespace
from .gesture import parse_status,parse_region,gesture_status
class DetectorTests(unittest.TestCase):
    def test_capabilities_and_bounds(self):
        p=bytes([0,0x12,13,0,0,3,1,0])
        self.assertTrue(parse_status(p).auto_mode)
        self.assertFalse(parse_status(p[:1]+b'\x11'+p[2:]).auto_mode)
        self.assertEqual(parse_region(bytes([0,0x12,128,4,80,2,128,0])),(1152,592,128))
        self.assertIsNone(parse_region(bytes([0,0x12,0,0,0,0,0,0])))
        for p in (bytes([0,0x12,1,0,0,0,0,0]),bytes([0,0x12,0,5,0,0,64,0]),bytes([0,0x12,0,0,0,0,65,0])):
            with self.assertRaises(ValueError):parse_region(p)
    def test_status_reads_location_only_for_new_firmware(self):
        class Client:
            simulated=False;lock=threading.RLock()
            def __init__(self,version):self.version=version;self.calls=[]
            def _exchange(self,cmd):
                self.calls.append(cmd)
                return SimpleNamespace(payload=bytes([0,self.version,13,0,0,3,1,0]) if cmd==0x40 else bytes([0,0x12,0,0,0,0,64,0]))
        old=Client(0x11);self.assertIsNone(gesture_status(old).region);self.assertEqual(old.calls,[0x40])
        new=Client(0x12);self.assertEqual(gesture_status(new).region,(0,0,64));self.assertEqual(new.calls,[0x40,0x42])
if __name__=='__main__':unittest.main()
