"""V0.17 capture lifecycle and full-resolution export regression."""
import tempfile,time,unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image
from .hdmi_source import HDMIFrame,USBCaptureSource,HDMIPreview
from .snapshots import FrameStore

class CaptureTests(unittest.TestCase):
 def test_worker_conversion_stop_and_no_stale_frame(self):
  import numpy as np
  class Capture:
   released=False
   def isOpened(self):return True
   def set(self,*args):return True
   def read(self):time.sleep(.005);return True,np.full((4,6,3),(1,2,3),dtype=np.uint8)
   def release(self):self.released=True
  cap=Capture();s=USBCaptureSource()
  with patch('cv2.VideoCapture',return_value=cap):
   s.start(9)
   try:
    end=time.monotonic()+2
    while s.latest() is None and time.monotonic()<end:time.sleep(.01)
    self.assertEqual(s.latest().image.getpixel((0,0)),(3,2,1))
    with self.assertRaises(RuntimeError):s.start(9)
   finally:s.close();s._thread.join(2)
  self.assertTrue(cap.released);self.assertFalse(s.running);self.assertIsNone(s.latest())
 def test_failure(self):
  s=USBCaptureSource()
  with patch('cv2.VideoCapture',side_effect=RuntimeError('busy')):
   s.start(0);s._thread.join(2)
  self.assertIn('busy',s.status);self.assertIsNone(s.latest())
 def test_preview_save_full_image(self):
  import tkinter as tk
  class Source:
   status='test';frame=HDMIFrame(Image.new('RGB',(1280,720),'red'),1,time.monotonic())
   def latest(self):return self.frame
   def close(self):self.frame=None
  root=tk.Tk();root.withdraw()
  try:
   with tempfile.TemporaryDirectory() as folder:
    source=Source();store=FrameStore(folder);preview=HDMIPreview(root,source,store)
    root.update();preview.save();self.assertEqual(len(store.entries()),1)
    with Image.open(store.entries()[0]) as image:self.assertEqual(image.size,(1280,720))
    dest=Path(folder)/'export.png'
    with patch('host.hdmi_source.filedialog.asksaveasfilename',return_value=str(dest)):preview.export()
    with Image.open(dest) as image:self.assertEqual(image.size,(1280,720));self.assertEqual(image.getpixel((0,0)),(255,0,0))
    preview.stop();preview.update();self.assertEqual(str(preview.save_button['state']),'disabled')
    preview.close()
  finally:root.destroy()
