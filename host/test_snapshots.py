"""V0.15: control-only DDR store, local image preservation and editor movement."""
import json
import tempfile
import unittest
from PIL import Image
from .client import DemoClient
from .snapshots import FrameStore, ImageDocument
from .frame_gallery import comparison_columns, Gallery, Editor, Comparison
from .ddr_store import store_status, store_control, parse_status
from .hdmi_source import PendingHDMISource

class SnapshotTests(unittest.TestCase):
    def test_ddr_capacity_and_modes(self):
        client=DemoClient()
        for _ in range(8):self.assertEqual(store_control(client,1).mode,0)
        with self.assertRaises(RuntimeError):store_control(client,1)
        self.assertEqual(store_control(client,2).mode,1)
        self.assertEqual(store_control(client,3,frame_id=3).display,3)
        self.assertEqual(store_control(client,4,selection=(1,3,7)).mode,3)
        self.assertEqual(len(store_control(client,0).saved),8)
        self.assertEqual(store_control(client,5).saved,())
    def test_metadata_validation_and_no_uart_images(self):
        self.assertEqual(parse_status(bytes((0,2,8,2,9,0,2,3))).saved,(0,3))
        with self.assertRaises(RuntimeError):parse_status(bytes((0,1,8,0,0,0,0,0)))
        with self.assertRaises(ValueError):parse_status(bytes((0,2,8,1,0,0,0,0)))
        self.assertFalse(PendingHDMISource().available);self.assertIsNone(PendingHDMISource().latest())
    def test_gui_ddr_controls(self):
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
                app.frame_store=FrameStore(folder);app.toggle_connection();finish()
                app.capture_frame();finish();self.assertEqual(len(app.ddr_status.saved),1)
                self.assertEqual(app.ddr_status.mode,0);self.assertFalse(app.frame_store.entries())
                app.ddr_action(2);finish();self.assertEqual(app.ddr_status.mode,1)
                app.resume_video();finish();app.capture_frame();finish()
                app.open_ddr_store();finish();root.update();self.assertEqual(len(app.ddr_selected),2)
                [v.set(True) for v in app.ddr_selected.values()];app.compare_selected();finish()
                self.assertEqual(app.ddr_status.mode,3)
                app.close_ddr_store();finish();self.assertEqual(app.ddr_status.mode,0)
        finally:app.close()

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
                editor.fit();origin=editor.origin;editor.move(25,-15)
                self.assertEqual(editor.origin,(origin[0]+25,origin[1]-15))
                class Event:pass
                event=Event();event.x=editor.origin[0]+10*editor.scale;event.y=editor.origin[1]+12*editor.scale
                px,py=editor.point(event);self.assertAlmostEqual(px,10,delta=1);self.assertAlmostEqual(py,12,delta=1)
                editor.fill();self.assertEqual(editor.pan_x,0);editor.fit()
                editor.flip(True);editor.percent.set('50');editor.resize();editor.save();root.update()
                self.assertEqual(len(store.entries()),3);self.assertEqual(editor.doc.image.size,(160,90))
                for obj in (comparison,editor,gallery):obj.win.destroy()
        finally:root.destroy()

if __name__=='__main__':unittest.main()
