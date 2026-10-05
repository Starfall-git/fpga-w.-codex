"""V0.16: mode exclusivity, frame flags, old-device refusal, GUI defaults."""
import time,unittest
from .client import DemoClient
from .protocol import isp_payload
class AdvancedTests(unittest.TestCase):
 def test_flags_and_defaults(self):
  client=DemoClient()
  status=client.set_isp(False,False,False,False,False,True,True)
  self.assertEqual(status.isp_flags,104)
  self.assertEqual(status.advanced_capabilities & 15,15)
  self.assertEqual(client.reset_defaults()[0].isp_flags,0)
  with self.assertRaises(ValueError):isp_payload(True,False,False,False,True)
 def test_gui_mutual_selection(self):
  import tkinter as tk
  from .gui import ImageControlApp
  root=tk.Tk();root.withdraw();app=ImageControlApp(root,demo=True);app.auto_poll.set(False)
  def finish():
   end=time.monotonic()+3
   while app.busy and time.monotonic()<end:root.update();time.sleep(.01)
   self.assertFalse(app.busy)
  try:
   app.toggle_connection();finish()
   app.sobel.set(True);app.apply_isp('sobel');finish()
   app.scharr.set(True);app.apply_isp('scharr');finish()
   self.assertFalse(app.sobel.get());self.assertEqual(app.client.status.isp_flags,16)
   app.canny.set(True);app.apply_isp('canny');finish()
   self.assertFalse(app.scharr.get());self.assertTrue(app.gaussian.get())
   self.assertEqual(app.client.status.isp_flags,40)
   app.reset_defaults();finish();self.assertFalse(app.canny.get());self.assertFalse(app.gaussian.get())
  finally:app.close()
