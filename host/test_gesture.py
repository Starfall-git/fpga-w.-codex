"""v1.1 / 15: Wire-format validation and GUI control/compatibility regressions."""
import time
import unittest
from .gesture import GestureStatus,gesture_status,gesture_control,parse_status
from .client import DemoClient


class GestureTests(unittest.TestCase):
    def test_valid_and_rejection(self):
        status=parse_status(bytes([0,0x11,13,4,0,2,0x34,0x12]))
        self.assertEqual(status.label,'点赞');self.assertEqual(status.frame_id,0x1234)
        self.assertEqual(status.margin,512)
        for p in (bytes([0,0x11,12,4,0,0,0,0]),bytes([0,0x11,29,4,0,0,0,0]),
                  bytes([0,0x11,9,4,0,0,0,0]),bytes([0,0x11,13,5,0,0,0,0])):
            with self.assertRaises(ValueError):parse_status(p)
        with self.assertRaises(RuntimeError):parse_status(bytes([3,0,0,0,0,0,0,0]))
        with self.assertRaises(RuntimeError):parse_status(bytes([0,1,0,0,0,0,0,0]))

    def test_demo_has_no_fake_result(self):
        backend=DemoClient()
        self.assertFalse(gesture_status(backend).enabled)
        self.assertTrue(gesture_control(backend,True).enabled)
        self.assertFalse(gesture_status(backend).valid)
        self.assertEqual(gesture_status(backend).class_id,255)
        backend.reset_defaults()
        self.assertFalse(gesture_status(backend).enabled)
        self.assertFalse(gesture_control(backend,False).enabled)

    def test_gui_start_stop_disconnect(self):
        import tkinter as tk
        from .gui import ImageControlApp
        root=tk.Tk();root.withdraw();app=ImageControlApp(root,demo=True)
        def finish():
            deadline=time.monotonic()+4
            while (app.busy or app.pending) and time.monotonic()<deadline:
                root.update();time.sleep(.005)
            self.assertFalse(app.busy)
        try:
            app.toggle_connection();finish();self.assertTrue(app.gesture_available)
            app.open_gesture();app.gesture_window.withdraw()
            app.toggle_gesture();finish();self.assertTrue(app.gesture_info.enabled)
            self.assertIn('模拟',app.gesture_text.get());self.assertFalse(app.gesture_info.valid)
            app.toggle_gesture();finish();self.assertFalse(app.gesture_info.enabled)
            app.toggle_connection();finish();self.assertFalse(app.gesture_available)
            self.assertEqual(app.gesture_result.get(),'—')
        finally:app.close()


if __name__=='__main__':unittest.main()
