"""V0.18: reversible annotation layers, persisted text, catalog and deletion."""
import tempfile, unittest
from PIL import Image
from .snapshots import ImageDocument,FrameStore
from .ddr_store import FrameCatalog,store_control,StoreStatus
from .client import DemoClient
class EditorTests(unittest.TestCase):
 def test_erase_protects_text_and_image(self):
  doc=ImageDocument(Image.new('RGB',(160,100),'navy'))
  doc.add('line',[(10,20),(120,20)],'red',5)
  doc.add('text',[(20,45)],'white',20,'文字 ABC')
  before=doc.image.copy();doc.erase([(65,20)],20)
  self.assertEqual(doc.image.getpixel((65,20)),(0,0,128))
  self.assertEqual(doc.image.getpixel((10,20)),(255,0,0))
  doc.erase([(0,60),(160,60)],100,whole=True)
  self.assertEqual([o['kind'] for o in doc.objects],['text'])
  self.assertEqual(doc.image.crop((0,45,160,100)).tobytes(),before.crop((0,45,160,100)).tobytes())
  doc.undo();doc.undo();self.assertEqual(doc.image.tobytes(),before.tobytes())
 def test_transform_text_save_restore_and_full_undo(self):
  original=Image.new('RGB',(100,80),'black');doc=ImageDocument(original)
  doc.add('rectangle',[(4,4),(70,65)],'red',3);doc.add('text',[(20,20)],'white',14,'old')
  doc.crop((10,10,90,70));doc.flip(True);doc.resize(150);doc.edit_text(1,'new')
  with tempfile.TemporaryDirectory() as folder:
   store=FrameStore(folder);path=store.save(original);store.replace_document(path,doc)
   self.assertEqual(len(store.entries()),1)
   reopened=store.document(path);self.assertEqual(reopened.objects[1]['text'],'new')
   self.assertEqual(reopened.image.tobytes(),doc.image.tobytes())
   reopened.edit_text(1,'again');self.assertNotEqual(reopened.image.tobytes(),doc.image.tobytes())
   reopened.reset();self.assertEqual(reopened.image.tobytes(),original.tobytes())
  for _ in range(6):doc.undo()
  self.assertEqual(doc.image.size,original.size);self.assertEqual(doc.image.tobytes(),original.tobytes())
 def test_all_shapes(self):
  for kind in ('line','curve','rectangle','ellipse','triangle','polygon','diamond','arrow'):
   doc=ImageDocument(Image.new('RGB',(80,80)))
   doc.add(kind,[(10,10),(50,50),(20,60)] if kind=='polygon' else [(10,10),(60,60)],'white',3)
   self.assertIsNotNone(doc.image.getbbox(),kind);doc.undo();self.assertIsNone(doc.image.getbbox())
 def test_catalog_and_delete(self):
  catalog=FrameCatalog();catalog.sync((9,));catalog.sync((1,9));self.assertEqual(catalog.ordered(),[9,1])
  self.assertEqual([catalog.entries[s]['number'] for s in catalog.ordered()],[1,2])
  with self.assertRaises(ValueError):catalog.rename(9,2)
  catalog.rename(9,12);catalog.sync((1,));catalog.sync((1,9));self.assertEqual(catalog.ordered(),[1,9])
  client=DemoClient()
  for _ in range(8):store_control(client,1)
  store_control(client,4,selection=(0,1,2,3,4));status=store_control(client,6,2)
  self.assertNotIn(2,status.saved);self.assertEqual(status.mode,0)
  self.assertEqual(len(store_control(client,1).saved),8)
  client.ddr_status=StoreStatus(8,(1,),0,0,2)
  with self.assertRaises(RuntimeError):store_control(client,6,1)

 def test_crop_returns_pen_and_right_drag(self):
  import tkinter as tk,time
  from .frame_gallery import Editor
  root=tk.Tk();root.withdraw()
  try:
   with tempfile.TemporaryDirectory() as folder:
    store=FrameStore(folder);path=store.save(Image.new('RGB',(400,200),'white'))
    editor=Editor(root,store,path)
    for _ in range(8):root.update();time.sleep(.02)
    editor.fit()
    class Event:pass
    def at(x,y):
     e=Event();e.x,e.y=editor.screen((x,y));return e
    editor.set_tool('crop','裁剪');editor.press(at(20,20));editor.release(at(200,120))
    self.assertEqual(editor.tool.get(),'pen');self.assertEqual(editor.doc.base.size,(180,100))
    e=at(30,30);editor.pan_press(e);p=(editor.pan_x,editor.pan_y);e.x+=22;e.y+=11;editor.pan_drag(e)
    self.assertEqual((editor.pan_x,editor.pan_y),(p[0]+22,p[1]+11))
    editor.undo();self.assertEqual(editor.doc.base.size,(400,200))
    editor.doc.add('arrow',[(10,10),(60,60)],'red',3);editor.save()
    self.assertEqual(len(store.entries()),1);self.assertEqual(len(store.document(path).objects),1)
    editor.restore();self.assertEqual(editor.doc.objects,[]);editor.save();self.assertEqual(store.load(path).getpixel((10,10)),(255,255,255))
    editor.win.destroy()
  finally:root.destroy()

 def test_reconnect_order_and_protocol_metadata(self):
  from .ddr_store import store_status
  from types import SimpleNamespace
  import threading
  class Client:
   simulated=False;lock=threading.RLock()
   def _exchange(self,cmd,payload=None):
    if cmd==0x30:return SimpleNamespace(payload=bytes((0,3,8,2,2,2,0,0)))
    slot=payload[0];order={1:30,9:21}[slot]
    return SimpleNamespace(payload=bytes((0,slot))+order.to_bytes(4,'little')+bytes(2))
  status=store_status(Client());catalog=FrameCatalog();catalog.sync(status.saved,status.orders)
  self.assertEqual(catalog.ordered(),[9,1]);self.assertEqual([catalog.entries[s]['number'] for s in catalog.ordered()],[1,2])

 def test_hdmi_thumbnail_binding_and_close_restores_live(self):
  import tkinter as tk,time
  from unittest.mock import patch
  from .gui import ImageControlApp
  from .hdmi_source import HDMIFrame
  root=tk.Tk();root.withdraw();client=DemoClient();client.simulated=False
  state=[StoreStatus(8,(1,9),0,0,3,((1,2),(9,1)))];calls=[]
  class Source:
   available=True;running=True
   def latest(self):return HDMIFrame(Image.new('RGB',(32,18),(state[0].display,0,0)),1,time.monotonic())
   def close(self):pass
  def control(client,action,frame_id=0,selection=()):
   calls.append((action,frame_id));state[0]=StoreStatus(8,(1,9),2 if action==3 else 0,frame_id,3,((1,2),(9,1)));return state[0]
  app=ImageControlApp(root,hdmi_source=Source());app.auto_poll.set(False);app.client=client;app.snapshot_available=True
  try:
   with patch('host.gui.store_control',side_effect=control),patch('host.gui.store_status',side_effect=lambda _:state[0]):
    app._store_status(state[0]);app.open_ddr_store()
    end=time.monotonic()+5
    while app.busy and time.monotonic()<end:root.update();time.sleep(.01)
    self.assertFalse(app.busy)
    self.assertEqual(calls[:2],[(3,9),(3,1)])
    for slot in (1,9):self.assertEqual(app.ddr_catalog.entries[slot]['thumbnail'].getpixel((0,0)),(slot,0,0))
    self.assertEqual(state[0].mode,0)
    app.close_ddr_store()
    while app.busy:root.update();time.sleep(.01)
    self.assertEqual(calls[-1],(0,0))
  finally:app.close()
