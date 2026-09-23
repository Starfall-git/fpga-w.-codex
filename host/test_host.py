"""V0.4 tests: independent CRC check vector, framing, serial errors and GUI flow."""
import time
import unittest
from .protocol import *
from .client import SerialClient, DemoClient


class FakeSerial:
    def __init__(self, mode="ok"):
        self.mode, self.buffer, self.writes = mode, bytearray(), []
        self.value = 128

    def write(self, packet):
        self.writes.append(packet)
        request = Frame.decode(packet)
        if self.mode == "timeout":
            return len(packet)
        if request.command == Command.SET_THRESHOLD:
            self.value = int.from_bytes(request.payload[:2], "little")
        code = 2 if self.mode == "error" else 0
        body = bytes((code, self.value & 255, self.value >> 8, 1, 1, 0, 0, 0))
        reply = Frame(request.sequence, request.command | 128, body).encode()
        stale = Frame((request.sequence-1) & 255, request.command | 128, body).encode()
        corrupt = reply[:-1] + bytes((reply[-1] ^ 1,))
        self.buffer.extend(b"noise" + stale + corrupt + reply)
        return len(packet)

    def read(self, size):
        raw = bytes(self.buffer[:3])
        del self.buffer[:3]
        return raw

    def close(self):
        pass


class ProtocolTests(unittest.TestCase):
    def test_crc_standard_vector(self):
        self.assertEqual(crc8(b"123456789"), 0xf4)

    def test_split_noise_crc_recovery(self):
        frame = Frame(165, 16, threshold_payload(4095))
        raw = frame.encode()
        decoder = FrameDecoder()
        frames = []
        for byte in b"noise\xa5" + raw[:-1] + b"\x00" + raw + raw:
            frames.extend(decoder.feed(bytes((byte,))))
        self.assertEqual(frames, [frame, frame])

    def test_payload_limits(self):
        self.assertEqual(threshold_payload(4095)[:2], b"\xff\x0f")
        for value in (-1, 4096, True, 1.2, "128"):
            with self.assertRaises(ValueError): threshold_payload(value)
        self.assertEqual(len(crop_payload(0, 0, 1280, 720)), 8)
        for args in ((0, 0, 0, 1), (1279, 0, 2, 1), (0, 719, 1, 2)):
            with self.assertRaises(ValueError): crop_payload(*args)
        for args in ((1, 0), (1, 11), (6, 1)):
            with self.assertRaises(ValueError): zoom_payload(*args)
        self.assertEqual(zoom_payload(1, 4)[:4], b"\x01\x00\x04\x00")

    def test_serial_fragmented_stale_corrupt(self):
        fake = FakeSerial()
        client = SerialClient(transport=fake)
        self.assertEqual(client.get_status().threshold, 128)
        for value in (0, 256, 4095):
            self.assertEqual(client.set_threshold(value).threshold, value)
        self.assertEqual(len(fake.writes), 4)
        self.assertEqual([Frame.decode(p).sequence for p in fake.writes], [0, 1, 2, 3])

    def test_unsupported_no_send(self):
        fake = FakeSerial()
        client = SerialClient(transport=fake)
        client.get_status()
        for method, args in ((client.set_flip, (True,)), (client.set_crop, (0, 0, 10, 10)),
                             (client.set_zoom, (1, 2))):
            with self.assertRaises(RuntimeError): method(*args)
        self.assertEqual(len(fake.writes), 1)

    def test_error_timeout_no_retry(self):
        with self.assertRaises(DeviceError): SerialClient(transport=FakeSerial("error")).get_status()
        fake = FakeSerial("timeout")
        with self.assertRaises(TimeoutError): SerialClient(transport=fake, timeout=.01).get_status()
        self.assertEqual(len(fake.writes), 1)

    def test_demo_explicit(self):
        client = DemoClient()
        self.assertTrue(client.simulated)
        self.assertEqual(client.set_threshold(512).threshold, 512)
        self.assertEqual(client.get_status().capabilities, 127)

    def test_percent_modes_and_device_defaults(self):
        self.assertEqual(percent_ratio('10%'),(1,10))
        self.assertEqual(percent_ratio('500'),(5,1))
        self.assertEqual(percent_ratio('123.45%'),(2469,2000))
        for text in ('9.99%','500.01%','NaN','inf','0.1','12.345%'):
            with self.assertRaises(ValueError): percent_ratio(text)
        client=DemoClient()
        self.assertFalse(client.get_status().sobel_enabled)
        client.set_threshold(777)
        self.assertEqual(client.set_isp(True,True).isp_flags,3)
        client.set_flip(True,True); client.set_zoom(5,1)
        status,geometry=client.reset_defaults()
        self.assertEqual(status.threshold,777)
        self.assertEqual(status.isp_flags,0)
        self.assertEqual(geometry,Geometry())

    def test_serial_read_does_not_wait_for_128_bytes(self):
        class ExactSerial(FakeSerial):
            @property
            def in_waiting(self): return len(self.buffer)
            def read(self,size):
                if size>len(self.buffer): raise AssertionError('Would wait for timeout despite complete reply')
                data=bytes(self.buffer[:size]); del self.buffer[:size]; return data
        client=SerialClient(transport=ExactSerial())
        self.assertEqual(client.get_status().threshold,128)
        self.assertGreaterEqual(client.last_roundtrip_ms,0)

    def test_geometry_roundtrip_and_cross_validation(self):
        client = DemoClient()
        result = client.set_flip(True, True)
        self.assertTrue(result.vertical and result.horizontal)
        result = client.set_crop(12, 24, 640, 360)
        self.assertEqual((result.x,result.y,result.width,result.height),(12,24,640,360))
        result = client.set_zoom(3,2)
        self.assertEqual((result.numerator,result.denominator),(3,2))
        self.assertEqual(client.get_geometry(),result)
        client.set_zoom(1,1)
        client.set_crop(1279,719,1,1)
        with self.assertRaises(DeviceError): client.set_zoom(1,4)
        self.assertEqual(client.get_geometry().numerator,1)
        self.assertEqual(client.reset_geometry(),Geometry())

    def test_geometry_pages_invalid(self):
        with self.assertRaises(ValueError): Geometry.from_pages([bytes(8)]*4)
        self.assertEqual(flip_payload(True,True),b'\x03'+bytes(7))
        with self.assertRaises(ValueError): flip_payload(True,1)


class GuiTests(unittest.TestCase):
    def test_connect_apply_geometry_validate_disconnect(self):
        import tkinter as tk
        from .gui import ImageControlApp
        root = tk.Tk()
        root.withdraw()
        app = ImageControlApp(root, demo=True)
        app.auto_poll.set(False)

        def finish():
            deadline = time.monotonic() + 2
            while app.busy and time.monotonic() < deadline:
                root.update()
                time.sleep(.01)
            self.assertFalse(app.busy)

        try:
            app.toggle_connection(); finish()
            self.assertEqual(app.readback.get(), "128")
            app.threshold.set("256")
            self.assertEqual(app.readback.get(), "128")  # Editing alone never sends.
            app.apply_threshold(); finish()
            self.assertEqual(app.readback.get(), "256")
            app.threshold.set("4096"); app.apply_threshold()
            self.assertEqual(app.client.status.threshold, 256)
            for button, _ in app.controls:
                self.assertEqual(str(button.cget("state")), "normal")
            app.flip.set(True); app.flip_horizontal.set(True)
            app.apply_feature('flip'); finish()
            self.assertTrue(app.client.geometry.horizontal)
            app.crop['x'].set('100'); app.crop['width'].set('640'); app.crop['height'].set('360')
            app.apply_feature('crop'); finish()
            self.assertEqual(app.client.geometry.width,640)
            app.zoom.set('150%'); app.apply_feature('zoom'); finish()
            self.assertIn('150%',app.geometry_readback.get())
            app.crop['width'].set('1280'); app.apply_feature('crop')
            self.assertEqual(app.client.geometry.width,640)
            app.sobel.set(True); app.inverted.set(True); app.apply_isp(); finish()
            self.assertEqual(app.client.status.isp_flags,3)
            app.reset_defaults(); finish()
            self.assertEqual(app.client.geometry,Geometry())
            self.assertEqual(app.client.status.isp_flags,0)
            self.assertEqual(app.client.status.threshold,256)
            self.assertIn("A5 5A", app.log.get("1.0", "end"))
            app.toggle_connection(); finish()
            self.assertIsNone(app.client)
        finally:
            app.close()

    def test_busy_edits_coalesce_and_defaults_preserve_pending_threshold(self):
        import tkinter as tk
        from .gui import ImageControlApp
        root=tk.Tk(); root.withdraw(); app=ImageControlApp(root,demo=True); app.auto_poll.set(False)
        def finish():
            deadline=time.monotonic()+3
            while (app.busy or app.pending) and time.monotonic()<deadline:
                root.update(); time.sleep(.005)
            self.assertFalse(app.busy or app.pending)
        try:
            app.toggle_connection(); finish()
            writes=[]; setter=app.client.set_threshold
            def slow(value):
                writes.append(value); time.sleep(.03); return setter(value)
            app.client.set_threshold=slow
            app.threshold.set('201'); app.apply_threshold()
            app.threshold.set('202'); app.apply_threshold()
            app.threshold.set('203'); app.apply_threshold()
            app.flip.set(True); app.apply_feature('flip')
            app.reset_defaults(); finish()
            self.assertEqual(writes,[201,203])
            self.assertEqual(app.client.status.threshold,203)
            self.assertEqual(app.client.geometry,Geometry())
            # Actual checkbox callbacks submit immediately; no Apply button involved.
            app.controls[0][0].invoke(); finish()
            self.assertTrue(app.client.status.sobel_enabled)
            self.assertTrue(app.threshold_entry.bind('<Return>'))
            self.assertTrue(app.zoom_box.bind('<Return>'))
        finally: app.close()


if __name__ == "__main__":
    unittest.main()
