"""V0.19: camera protocol, failure handling, tuning validation and GUI actions."""

import unittest

import threading

from types import SimpleNamespace

from unittest.mock import patch

from .client import DemoClient

from .protocol import Frame,DeviceStatus

from .camera_controls import register,manual,auto_adjust,tuning,camera_defaults,ControlPanel





class WireClient:

    simulated=False

    def __init__(self):

        self.status=DeviceStatus(0,128,1,255,0,31)

        self.lock=threading.RLock();self.calls=[];self.regs={0x3100:19,0x312a:32,0x3152:1000,0x3164:200}

        self.failure=0;self.config=(0,50)

    def _exchange(self,cmd,payload):

        self.calls.append((cmd,payload))

        if self.failure:return Frame(0,cmd|128,bytes((self.failure,))+bytes(7))

        if cmd==0x40:

            a=int.from_bytes(payload[1:3],'little');v=int.from_bytes(payload[3:5],'little')

            if payload[0]:self.regs[a]=v

            return Frame(0,cmd|128,b'\0'+self.regs[a].to_bytes(2,'little')+bytes(5))

        if cmd==0x14:self.config=tuple(payload[:2])

        return Frame(0,cmd|128,b'\0'+bytes(self.config)+bytes(5))





class CameraTests(unittest.TestCase):

    def test_wire_manual_and_readback(self):

        c=WireClient();r=manual(c,450,1,40)

        writes=[p for cmd,p in c.calls if cmd==0x40 and p[0]]

        self.assertEqual(writes[0],b'\1\0\x31\0\0\0\0\0')

        self.assertEqual(r[0x3100],19);self.assertEqual(r[0x3012],450);self.assertEqual(r[0x30b0],0x490)

        for args in ((0,1,32),(673,1,32),(10,4,32),(10,1,129)):

            n=len(c.calls)

            with self.assertRaises(ValueError):manual(c,*args)

            self.assertEqual(len(c.calls),n)



    def test_error_stops_sequence_and_old_device_guard(self):

        c=WireClient();c.failure=6

        with self.assertRaises(RuntimeError):manual(c,450,1,32)

        self.assertEqual(len(c.calls),1)

        c.status=DeviceStatus(0,128,1,255,0,15)

        with self.assertRaises(RuntimeError):register(c,0x3012,10)

        self.assertEqual(len(c.calls),1)



    def test_auto_exposure_limits_roi_and_defaults(self):

        c=WireClient();manual(c,100,0,32);auto_adjust(c)

        self.assertEqual(c.regs[0x3100],19)

        self.assertEqual(c.regs[0x3146],960)

        self.assertEqual(c.regs[0x3166],986)

        self.assertLess(c.regs[0x3168],c.regs[0x3166])

        self.assertEqual(tuning(c,7,35),(7,35));self.assertEqual(tuning(c),(7,35))

        for f,p in ((16,50),(0,24),(0,76)):

            with self.assertRaises(ValueError):tuning(c,f,p)

        camera_defaults(c)

        self.assertEqual(c.regs[0x3100],19);self.assertEqual(c.regs[0x3012],672)

        self.assertEqual(tuning(c),(0,50))



    def test_partial_failure_restores_auto(self):

        # Reproduce V0.19's precise fault: ROI write rejected AFTER AE was disabled.

        for failed_address,operation in ((0x3140,auto_adjust),(0x305e,lambda c:manual(c,450,1,40))):

            c=WireClient();exchange=c._exchange

            def reject(cmd,payload):

                if cmd==0x40 and payload[0] and int.from_bytes(payload[1:3],'little')==failed_address:

                    return Frame(0,0xc0,b'\2'+bytes(7))

                return exchange(cmd,payload)

            c._exchange=reject

            with self.assertRaisesRegex(RuntimeError,'已恢复自动曝光'):operation(c)

            self.assertEqual(c.regs[0x3100],0x13)



    def test_recovery_readback_is_required(self):

        c=WireClient();exchange=c._exchange

        def fail_read(cmd,payload):

            if cmd==0x40 and payload[:3]==b'\0\0\x31':return Frame(0,0xc0,bytes(8))

            return exchange(cmd,payload)

        c._exchange=fail_read

        with self.assertRaisesRegex(RuntimeError,'未能确认自动调光恢复'):manual(c,400,0,32,restore_auto=True)



    def test_manual_failure_does_not_enable_auto(self):
        c=WireClient();exchange=c._exchange
        def reject(cmd,payload):
            if cmd==0x40 and payload[0] and int.from_bytes(payload[1:3],'little')==0x305e:
                return Frame(0,0xc0,b'\2'+bytes(7))
            return exchange(cmd,payload)
        c._exchange=reject
        with self.assertRaisesRegex(RuntimeError,'已保持手动调光'):
            manual(c,250,1,40,restore_auto=False)
        self.assertEqual(c.regs[0x3100],0)

    def test_manual_mode_persists_until_auto(self):
        c=WireClient()
        manual(c,250,1,40,restore_auto=False)
        self.assertEqual(c.regs[0x3100],0)
        manual(c,260,2,45)
        self.assertEqual(c.regs[0x3100],0)
        self.assertEqual(c.regs[0x3012],260)
        auto_adjust(c)
        self.assertEqual(c.regs[0x3100],19)
        manual(c,270,1,32)
        self.assertEqual(c.regs[0x3100],19)

    def test_gui_panel_controls_and_demo(self):

        import tkinter as tk

        root=tk.Tk();root.withdraw();c=DemoClient()

        app=SimpleNamespace(root=root,client=c,resetting=False,busy=False,pending={})

        app._submit=lambda operation,success,kind:success(operation())

        try:

            panel=ControlPanel(app);root.update()

            panel.rows.set(300);panel.analog.set(1);panel.digital.set(40);panel.submit_manual()

            self.assertEqual(c.camera_registers[0x3012],300)

            # Focus via mouse handler, then actual key events; one integer step per key.

            for widget,var,start,address,expected in (

                (panel.widgets[0],panel.rows,300,0x3012,301),

                (panel.widgets[1],panel.analog,1,0x30b0,0x4a0),

                (panel.widgets[2],panel.digital,32,0x305e,33)):

                widget.focus_force();root.update();var.set(start)

                widget.event_generate('<Right>');root.update()

                self.assertEqual(round(var.get()),start+1)

                root.after(230,root.quit);root.mainloop()

                self.assertEqual(c.camera_registers[address],expected)

                self.assertEqual(c.camera_registers[0x3100],19)

            panel.rows.set(1)

            panel.key_step(SimpleNamespace(widget=panel.widgets[0]),panel.rows,1,672,-1)

            self.assertEqual(panel.rows.get(),1);panel.submit_manual()

            panel.recommended();self.assertEqual(c.isp_tuning,(7,50))

            panel.percent.set(90);panel.submit_tuning();self.assertEqual(c.isp_tuning,(7,50))

            panel.submit_manual_mode();self.assertEqual(c.camera_registers[0x3100],0)
            panel.rows.set(234);panel.submit_manual()
            self.assertEqual(c.camera_registers[0x3100],0)
            self.assertEqual(c.camera_registers[0x3012],234)
            panel.submit_auto();self.assertEqual(c.camera_registers[0x3100],19)

            camera_defaults(c);panel.read();self.assertFalse(panel.flags[0].get())

            app.client=None;panel.submit_manual() # stale window never sends to a disconnected backend

            root.update()

        finally:

            if 'panel' in locals():panel.close()

            root.destroy()





if __name__=='__main__':unittest.main()

