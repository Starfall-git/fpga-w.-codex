"""V0.9: independent RGB/median/Sobel image reference for all four ISP modes."""
import argparse
from collections import deque
from pathlib import Path
import os, random, shutil, subprocess

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--width',type=int,default=16)
parser.add_argument('--height',type=int,default=12)
parser.add_argument('--gray',type=int,choices=(0,1),default=0)
parser.add_argument('--adaptive',type=int,choices=(0,1),default=1)
parser.add_argument('--threshold',type=int,default=128)
parser.add_argument('--invert',type=int,choices=(0,1),default=0)
args=parser.parse_args()
assert 0<=args.threshold<=4095
WIDTH,HEIGHT=args.width,args.height
assert 16<=WIDTH<=1280 and 12<=HEIGHT<=720
out=ROOT/f'tools/debug/median_modes_{WIDTH}x{HEIGHT}_g{args.gray}_a{args.adaptive}_t{args.threshold}_i{args.invert}'; out.mkdir(parents=True,exist_ok=True)
rng=random.Random(135)
reset=(1,1,0,0,0,0,0,0)
pipe=deque([reset]*12)
cycles=0

# V0.11 / 55: independent image-domain reference, both compile-time gray paths.
def gray(rgb):
 r,g,b=(rgb>>16)&255,(rgb>>8)&255,rgb&255
 return (306*r+601*g+117*b)//1024 if args.gray else g

def modes(image):
 h=len(image); w=len(image[0]); g=[[gray(p) for p in row] for row in image]
 med=[[0]*w for _ in range(h)]
 for y in range(2,h):
  for x in range(2,w): med[y][x]=sorted(g[yy][xx] for yy in range(y-2,y+1) for xx in range(x-2,x+1))[4]
 def sobel(src, first_valid):
  result=[[0xffffff if args.invert else 0]*w for _ in range(h)]
  # V0.10 / 50: Median has an invalid two-pixel border. A Sobel window
  # needs three fully valid Median rows/columns. The display edge halo is
  # suppressed through x,y=7 for both paths, so the first output is x,y=8.
  for y in range(first_valid,h):
   for x in range(first_valid,w):
    a,b,c=src[y-2][x-2:x+1]; d,e,f=src[y-1][x-2:x+1]; p,q,r=src[y][x-2:x+1]
    # Four signed convolutions from the reference eight-direction kernels.
    mag=max(abs(c+2*f+r-a-2*d-p),abs(p+2*q+r-a-2*b-c),
            abs(f+2*r+q-b-2*a-d),abs(b+2*c+f-d-2*p-q))
    threshold=max(args.threshold,e,1) if args.adaptive else args.threshold
    result[y][x]=0xffffff if ((mag>=threshold) != bool(args.invert)) else 0
  return result
 direct=sobel(g,8); filtered=sobel(med,8)
 return med,direct,filtered

with (out/'vectors.txt').open('w',encoding='ascii') as f:
 def emit(rst,hs,vs,de,rgb,raw=0,med=0,edge=0,both=0):
  global cycles,pipe
  cur=(hs,vs,de,raw,med,edge,both,0)
  if rst: pipe.append(cur); expected=pipe.popleft()
  else: pipe=deque([reset]*12); expected=reset
  f.write(' '.join(f'{v:x}' for v in (rst,hs,vs,de,rgb,*expected[:7]))+'\n');cycles+=1
 def blank(n,vs=1):
  for k in range(n): emit(1,1,vs,0,rng.randrange(1<<24))
 for _ in range(4): emit(0,1,0,0,0)
 for kind in range(9):
  if kind==0: image=[[0x777777 for x in range(WIDTH)] for y in range(HEIGHT)]
  elif kind==1: image=[[0xffffff if x>=8 else 0 for x in range(WIDTH)] for y in range(HEIGHT)]
  elif kind==2: image=[[0x204080 if (x,y)==(7,6) else 0x505050 for x in range(WIDTH)] for y in range(HEIGHT)]
  elif kind==3: image=[[rng.randrange(1<<24) for x in range(WIDTH)] for y in range(HEIGHT)]
  elif kind==4: image=[[0xffffff if (x+y)%2 else 0 for x in range(WIDTH)] for y in range(HEIGHT)]
  elif kind==5: image=[[0x505050 for x in range(WIDTH)] for y in range(HEIGHT)]
  elif kind==6: image=[[0 if x==0 or y==0 else 0xa0a0a0 for x in range(WIDTH)] for y in range(HEIGHT)]
  elif kind==7: image=[[0 for x in range(WIDTH)] for y in range(HEIGHT)]
  else: image=[[(min(255,4*x+7*y))*0x010101 for x in range(WIDTH)] for y in range(HEIGHT)]
  med,edge,both=modes(image)
  # V0.10 / 50: uniform bright scenes must not grow artificial white rails.
  if kind in (0,6,7) and (args.adaptive or args.threshold>0):
   assert all(v==(0xffffff if args.invert else 0) for row in edge+both for v in row)
  blank(20,vs=0);blank(20)
  for y,row in enumerate(image):
   for x,p in enumerate(row): emit(1,1,1,1,p,p,med[y][x]*0x010101,edge[y][x],both[y][x])
   blank(4)
  blank(20)

def tool(name):
 path=Path(os.environ.get('MODELSIM_BIN','D:/intelfpga/modelsim_ase/win32aloem'))/(name+'.exe')
 return str(path) if path.exists() else shutil.which(name)
sources=[ROOT/'src/isp'/s for s in ('video_rgb2gray.v','video_window3x3.v','sort3_8bit.v','video_median3x3.v','video_sobel.v','video_processing.v')]
sources.append(ROOT/'testbench/median_modes_tb.sv')
cmds=[[tool('vlib'),'work'],[tool('vlog'),'-sv',*map(str,sources)],
      [tool('vsim'),'-c','work.median_modes_tb',f'-gWIDTH={WIDTH}',f'-gGRAY={args.gray}',f'-gADAPTIVE={args.adaptive}',
       f'-gTHRESHOLD={args.threshold}',f'-gINVERT={args.invert}',
       '+VECTORS=vectors.txt','-do','onerror {quit -code 1}; run -all; quit -code 0']]
logs=[]
for cmd in cmds:
 p=subprocess.run(cmd,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace')
 logs.append(p.stdout);(out/'simulation.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Error:' in p.stdout or '** Fatal:' in p.stdout: raise SystemExit(p.stdout[-2200:])
if 'PASS MEDIAN MODES' not in logs[-1]: raise SystemExit(logs[-2200:])
print(f'PASS: {cycles} cycles, all four pixel modes and HS/VS/DE; log {out/"simulation.log"}')
