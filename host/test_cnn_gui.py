"""User-visible CNN control, readiness and serial connection failure behavior."""
import time
import gc
import tkinter as tk
import unittest
from unittest.mock import patch
from dataclasses import replace
from .gui import ImageControlApp
from .protocol import CAP_ADV_CNN, CnnError, CnnStatus


class CnnGuiTests(unittest.TestCase):
    def setUp(self):
        self.root = tk.Tk(); self.root.withdraw()
        self.app = ImageControlApp(self.root, demo=True)
        self.app.auto_poll.set(False)

    def tearDown(self):
        self.app.close()
        self.app.executor.shutdown(wait=True)
        self.app = None
        self.root = None
        # Collect destroyed Tcl widgets on the UI thread before the next worker.
        gc.collect()

    def finish(self):
        end = time.monotonic() + 3
        while (self.app.busy or self.app.pending) and time.monotonic() < end:
            self.root.update(); time.sleep(.005)
        self.assertFalse(self.app.busy or self.app.pending)

    def connect_panel(self):
        self.app.toggle_connection(); self.finish()
        self.app.cnn_button.invoke(); self.finish()
        return self.app.cnn_panel

    def test_buttons_acknowledgment_defaults_and_disconnect(self):
        p = self.connect_panel()
        self.assertIn('模拟演示', p.readback.get())
        for wanted in range(4):
            p.inference.set(bool(wanted & 1)); p.overlay.set(bool(wanted & 2))
            p.apply_button.invoke(); self.finish()
            self.assertEqual(p.status.applied, wanted)
        self.app.reset_defaults(); self.finish()
        self.assertEqual(p.status.applied, 0)
        self.app.toggle_connection(); self.finish()
        self.assertIsNone(p.status)
        self.assertEqual(str(p.apply_button.cget('state')), 'disabled')

    def test_not_ready_allows_overlay_but_blocks_inference(self):
        p = self.connect_panel()
        self.app.client.cnn_available = False
        p.refresh_button.invoke(); self.finish()
        self.assertIn('未就绪', p.hint.get())
        self.assertEqual(str(p.inference_box.cget('state')), 'disabled')
        p.overlay.set(True); p.apply_button.invoke(); self.finish()
        self.assertEqual(p.status.applied, 2)
        with patch.object(self.app.client, 'set_cnn') as setter:
            p.inference.set(True); p.apply()
            setter.assert_not_called()

    def test_legacy_board_no_new_command_and_timeout_no_false_success(self):
        p = self.connect_panel()
        self.app.client.status = replace(self.app.client.status, advanced_capabilities=15)
        with patch.object(self.app.client, 'get_cnn') as getter:
            p.refresh(); p.sync(); getter.assert_not_called()
            self.assertIn('未声明', p.hint.get())
        self.app.client.status = replace(self.app.client.status, advanced_capabilities=15 | CAP_ADV_CNN)
        p.refresh(); self.finish()
        with patch.object(self.app.client, 'set_cnn', side_effect=CnnError(CnnStatus(5, 0, 3, True))):
            p.inference.set(True); p.overlay.set(True); p.apply(); self.finish()
            self.assertEqual((p.status.applied, p.status.requested), (0, 3))
            self.assertFalse(p.inference.get())
        with patch.object(self.app.client, 'get_cnn', side_effect=TimeoutError('timeout')):
            p.refresh(); self.finish()
            self.assertIsNone(p.status)
            self.assertEqual(str(p.apply_button.cget('state')), 'disabled')

    def test_serial_open_error_is_distinct_from_handshake_timeout(self):
        self.app.mode.set('串口硬件'); self.app.port.set('COM8')
        with patch('host.gui.SerialClient', side_effect=OSError('access denied')):
            self.app.toggle_connection(); self.finish()
            self.assertIn('无法打开 COM8', self.app.message.get())
        with patch('host.gui.SerialClient') as constructor:
            constructor.return_value.get_status.side_effect = TimeoutError('no reply')
            self.app.toggle_connection(); self.finish()
            self.assertIn('COM8 已打开', self.app.message.get())
            self.assertIn('业务 .bit', self.app.message.get())
            constructor.return_value.close.assert_called_once()
        with patch('host.gui.list_ports', return_value=[]):
            self.app.refresh_ports()
            self.assertEqual(self.app.port.get(), '')
            self.assertIn('未发现 COM', self.app.message.get())


if __name__ == '__main__':
    unittest.main()
