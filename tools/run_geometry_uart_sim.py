"""V0.5 cross-language test: actual Python protocol packets and RTL frame commits."""
from pathlib import Path
import os
import shutil
import struct
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from host.protocol import Frame, Command, threshold_payload, crop_payload, zoom_payload, flip_payload

out=ROOT/'tools/debug/uart_geometry_sim'
out.mkdir(parents=True,exist_ok=True)
packets=[]
threshold=128
isp=0
flags=0
crop=(0,0,1280,720)
zoom=(1,1)


def exchange(cmd,payload=bytes(8),code=0,page_body=None,bad_crc=False):
    seq=len(packets)&255
    request=Frame(seq,cmd,payload).encode()
    if bad_crc: request=request[:-1]+bytes((request[-1]^1,))
    # V0.9 / 46: capability bit7 and applied mode bit2 expose Median.
    body=bytes((code,threshold&255,threshold>>8,1,255,isp,0,0)) if page_body is None else page_body
    reply=Frame(seq,cmd|128,body).encode()
    packets.append((int.from_bytes(request,'little'),int.from_bytes(reply,'little')))


def query():
    pages=[bytes((flags,0))+bytes(4),struct.pack('<HH',*crop[:2])+bytes(2),
           struct.pack('<HH',*crop[2:])+bytes(2),struct.pack('<HH',*zoom)+bytes(2)]
    for page,data in enumerate(pages): exchange(2,bytes((page,))+bytes(7),page_body=bytes((0,page))+data)


exchange(1); query()
for value in (1,2,3,0):
    flags=value
    exchange(32,flip_payload(bool(value&1),bool(value&2))); query()
crop=(100,50,640,360)
exchange(33,crop_payload(*crop)); query()
for value in ((1,10),(1,4),(1,2),(3,2),(5,1),(499,100),(12345,10000)):
    zoom=value
    exchange(34,zoom_payload(*zoom)); query()
for payload in (struct.pack('<HHHH',65535,0,2,1),struct.pack('<HHHH',0,0,0,1),struct.pack('<HHHH',1279,0,2,1)):
    exchange(33,payload,code=2)
for payload in (struct.pack('<HH',0,1)+bytes(4),struct.pack('<HH',1,0)+bytes(4),struct.pack('<HH',6,1)+bytes(4)):
    exchange(34,payload,code=2)
exchange(32,b'\x04'+bytes(7),code=2)
exchange(33,crop_payload(0,0,1280,720),code=1,bad_crc=True)
query()
zoom=(1,1); exchange(34,zoom_payload(*zoom))
crop=(1279,719,1,1); exchange(33,crop_payload(*crop))
exchange(34,zoom_payload(1,4),code=2); query()
crop=(0,0,1280,720); exchange(33,crop_payload(*crop))
threshold=256; exchange(16,threshold_payload(threshold)); exchange(1); query()
exchange(2,b'\x04'+bytes(7),page_body=b'\x02\x04'+bytes(6))
exchange(0x7f,code=3)
# V0.6: mode toggle, reverse while bypassed, bad bits, defaults preserve threshold.
for isp in (1,3,2,0,1,5,4,6,7,0):
    exchange(17,bytes((isp,))+bytes(7)); exchange(1)
exchange(17,b'\x08'+bytes(7),code=2)
flags=3; exchange(32,flip_payload(True,True))
zoom=(5,1); exchange(34,zoom_payload(*zoom))
isp=0; flags=0; crop=(0,0,1280,720); zoom=(1,1)
exchange(18); exchange(1); query()
exchange(18,b'\x01'+bytes(7),code=2)

with (out/'packets.txt').open('w',encoding='ascii') as f:
    f.write(str(len(packets))+'\n')
    for request,reply in packets: f.write(f'{request:026x} {reply:026x}\n')

def tool(name):
    return str(Path(os.environ['MODELSIM_BIN'])/(name+'.exe')) if 'MODELSIM_BIN' in os.environ else shutil.which(name)

sources=list((ROOT/'src/control').glob('*.v'))+[ROOT/'src/isp'/s for s in ('unsigned_divider.v','axi_transform_reader.v')]+[ROOT/'testbench/uart_geometry_tb.sv']
commands=[[tool('vlib'),'work'],[tool('vlog'),'-sv',*map(str,sources)],
          [tool('vsim'),'-c','work.uart_geometry_tb','-do','run -all; quit -f']]
logs=[]
for command in commands:
    result=subprocess.run(command,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace')
    logs.append(result.stdout)
    (out/'simulation.log').write_text('\n'.join(logs),encoding='utf-8')
    if result.returncode or '** Fatal' in result.stdout or '** Error' in result.stdout: raise SystemExit(result.stdout)
if 'PASS UART GEOMETRY:' not in logs[-1]: raise SystemExit(logs[-1])
print(next(line for line in logs[-1].splitlines() if 'PASS UART GEOMETRY:' in line))
