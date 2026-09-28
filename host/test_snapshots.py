"""V0.14 / 69: fragmented pixel transport and non-destructive image workflow."""
import binascii
import json
import tempfile
import threading
import unittest
from pathlib import Path
from PIL import Image
from .client import SerialClient, DemoClient
from .protocol import Frame
from .snapshots import FrameStore, ImageDocument, read_row, download_snapshot, CaptureCancelled
from .frame_gallery import comparison_columns, Gallery, Editor, Comparison

class PixelSerial:
    baudrate=115200
    def __init__(self, corrupt=False):
        self.buffer=bytearray(); self.corrupt=corrupt
    def write(self, packet):
        f=Frame.decode(packet); row=int.from_bytes(f.payload[:2],'little')
        self.pixels=bytes((i+row)&255 for i in range(24))
        crc=binascii.crc_hqx(self.pixels,0xffff)^int(self.corrupt)
        body=bytes((0,row,0,24,0,3,0,0))
        self.buffer.extend(Frame(f.sequence,0xb2,body).encode()+self.pixels+crc.to_bytes(2,'little'))
        return len(packet)
    def read(self, size):
        count=min(size,7); data=bytes(self.buffer[:count]); del self.buffer[:count]; return data

class SnapshotTests(unittest.TestCase):
    def test_fragmented_rows_and_crc(self):
        serial=PixelSerial();client=SerialClient(transport=serial)
        for row in range(3):
            self.assertEqual(read_row(client,row,8),bytes((i+row)&255 for i in range(24)))
            self.assertFalse(serial.buffer)
        with self.assertRaisesRegex(ValueError,'CRC16'):
            read_row(SerialClient(transport=PixelSerial(True)),0,8)
    def test_cancel_preserves_freeze(self):
        cancel=threading.Event();cancel.set();client=DemoClient()
        with self.assertRaises(CaptureCancelled):download_snapshot(client,cancel,lambda *_:None)
        self.assertTrue(client._frozen)
    def test_edits_preserve_original(self):
        with tempfile.TemporaryDirectory() as folder:
            store=FrameStore(folder);im=Image.new('RGB',(20,10),'black');im.putpixel((1,2),(255,0,0))
            original=store.save(im,simulated=True);doc=ImageDocument(store.load(original))
            doc.flip(True);self.assertEqual(doc.image.getpixel((18,2)),(255,0,0));doc.undo()
            doc.crop((10,8,0,0));self.assertEqual(doc.image.size,(10,8));doc.resize(200)
            self.assertEqual(doc.image.size,(20,16));doc.checkpoint();doc.stroke([(0,0),(10,10)],'white',2)
            edited=store.save(doc.image,parent=original.name)
            self.assertEqual(store.load(original).tobytes(),im.tobytes())
            self.assertTrue(json.loads(edited.with_suffix('.json').read_text())['simulated'])
            self.assertEqual(len(FrameStore(folder).entries()),2)
            with self.assertRaises(ValueError):doc.resize(501)
    def test_layout_adapts(self):
        sizes=[(1280,720)]*4
        self.assertEqual(comparison_columns(sizes,1280,800),2)
        self.assertEqual(comparison_columns(sizes,500,1600),1)
    def test_gui_capture_resume_cancel(self):
        import tkinter as tk
        import time
        from .gui import ImageControlApp
        root=tk.Tk();root.withdraw();app=ImageControlApp(root,demo=True);app.auto_poll.set(False)
        def finish():
            deadline=time.monotonic()+3
            while app.busy and time.monotonic()<deadline:root.update();time.sleep(.01)
            self.assertFalse(app.busy)
        try:
            with tempfile.TemporaryDirectory() as folder:
                app.frame_store=FrameStore(folder)
                app.toggle_connection();finish();self.assertTrue(app.snapshot_available)
                app.capture_frame();finish()
                self.assertTrue(app.frame_frozen);self.assertEqual(len(app.frame_store.entries()),1)
                app.resume_video();finish();self.assertFalse(app.frame_frozen)
                app.capture_frame();app.capture_cancel.set();finish()
                self.assertTrue(app.frame_frozen);self.assertEqual(len(app.frame_store.entries()),1)
                app.resume_video();finish()
        finally:app.close()

    def test_gui_gallery_editor_comparison(self):
        import tkinter as tk
        import time
        root=tk.Tk();root.withdraw()
        try:
            with tempfile.TemporaryDirectory() as folder:
                store=FrameStore(folder)
                paths=[store.save(Image.new('RGB',(320,180),color)) for color in ('red','green','blue')]
                gallery=Gallery(root,store);editor=Editor(root,store,paths[0],gallery.refresh)
                comparison=Comparison(root,store,paths,gallery.refresh)
                for _ in range(15):root.update();time.sleep(.02)
                self.assertEqual(len(gallery.photos),3);self.assertEqual(len(comparison.cells),3)
                editor.flip(True);editor.percent.set('50');editor.resize();editor.save();root.update()
                self.assertEqual(len(store.entries()),4);self.assertEqual(editor.doc.image.size,(160,90))
                for obj in (comparison,editor,gallery):obj.win.destroy()
        finally:root.destroy()

if __name__=='__main__':unittest.main()
