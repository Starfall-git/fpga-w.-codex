"""V0.9: independent RGB/median/Sobel image reference for all four ISP modes."""
from collections import deque
from pathlib import Path
import os, random, shutil, subprocess

ROOT=Path(__file__).resolve().parents[1]
WIDTH,HEIGHT=16,12
out=ROOT/'tools/debug/median_modes_16x12'; out.mkdir(parents=True,exist_ok=True)
rng=random.Random(135)
reset=(1,1,0,0,0,0,0,0)
pipe=deque([reset]*10)
cycles=0

def gray(rgb): return (((rgb>>16)&255)+2*((rgb>>8)&255)+(rgb&255))//4

def modes(image):
 h=len(image); w=len(image[0]); g=[[gray(p) for p in row] for row in image]
 med=[[0]*w for _ in range(h)]
 for y in range(2,h):
  for x in range(2,w): med[y][x]=sorted(g[yy][xx] for yy in range(y-2,y+1) for xx in range(x-2,x+1))[4]
 def sobel(src):
  result=[[0]*w for _ in range(h)]
  for y in range(2,h):
   for x in range(2,w):
    a,b,c=src[y-2][x-2:x+1]; d,_,f=src[y-1][x-2:x+1]; p,q,r=src[y][x-2:x+1]
    mag=abs(c+2*f+r-a-2*d-p)+abs(p+2*q+r-a-2*b-c)
    result[y][x]=0xffffff if mag>=128 else 0
  return result
 direct=sobel(g); filtered=sobel(med)
 return med,direct,filtered

with (out/'vectors.txt').open('w',encoding='ascii') as f:
 def emit(rst,hs,vs,de,rgb,raw=0,med=0,edge=0,both=0):
  global cycles,pipe
  cur=(hs,vs,de,raw,med,edge,both,0)
  if rst: pipe.append(cur); expected=pipe.popleft()
  else: pipe=deque([reset]*10); expected=reset
  f.write(' '.join(f'{v:x}' for v in (rst,hs,vs,de,rgb,*expected[:7]))+'\n');cycles+=1
 def blank(n,vs=1):
  for k in range(n): emit(1,1,vs,0,rng.randrange(1<<24))
 for _ in range(4): emit(0,1,0,0,0)
 for kind in range(6):
  if kind==0: image=[[0x777777 for x in range(WIDTH)] for y in range(HEIGHT)]
  elif kind==1: image=[[0xffffff if x>=8 else 0 for x in range(WIDTH)] for y in range(HEIGHT)]
  elif kind==2: image=[[0x204080 if (x,y)==(7,6) else 0x505050 for x in range(WIDTH)] for y in range(HEIGHT)]
  elif kind==3: image=[[rng.randrange(1<<24) for x in range(WIDTH)] for y in range(HEIGHT)]
  elif kind==4: image=[[0xffffff if (x+y)%2 else 0 for x in range(WIDTH)] for y in range(HEIGHT)]
  else: image=[[0x505050 for x in range(WIDTH)] for y in range(HEIGHT)]
  med,edge,both=modes(image)
  blank(20,vs=0);blank(20)
  for y,row in enumerate(image):
   for x,p in enumerate(row): emit(1,1,1,1,p,p,med[y][x]*0x010101,edge[y][x],both[y][x])
   blank(4)
  blank(20)

def tool(name):
 path=Path(os.environ.get('MODELSIM_BIN','D:/intelfpga/modelsim_ase/win32aloem'))/(name+'.exe')
 return str(path) if path.exists() else shutil.which(name)
sources=[ROOT/'src/isp'/s for s in ('video_window3x3.v','sort3_8bit.v','video_median3x3.v','video_sobel.v','video_processing.v')]
sources.append(ROOT/'testbench/median_modes_tb.sv')
cmds=[[tool('vlib'),'work'],[tool('vlog'),'-sv',*map(str,sources)],[tool('vsim'),'-c','work.median_modes_tb','+VECTORS=vectors.txt','-do','onerror {quit -code 1}; run -all; quit -code 0']]
logs=[]
for cmd in cmds:
 p=subprocess.run(cmd,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace')
 logs.append(p.stdout);(out/'simulation.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error:' in p.stdout or '** Fatal:' in p.stdout: raise SystemExit(p.stdout[-2200:])
if 'PASS MEDIAN MODES' not in logs[-1]: raise SystemExit(logs[-2200:])
print(f'PASS: {cycles} cycles, all four pixel modes and HS/VS/DE; log {out/"simulation.log"}')
