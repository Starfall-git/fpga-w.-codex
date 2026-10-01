"""V0.16: independent image-space oracle for Gaussian, Scharr and streaming Canny."""
from pathlib import Path
import random,subprocess,collections,argparse
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--preserve',type=int,default=0);parser.add_argument('--invert',type=int,default=0);args=parser.parse_args()
W,H,T=64,40,80
out=ROOT/f'tools/debug/advanced_isp_{args.preserve}_{args.invert}';out.mkdir(parents=True,exist_ok=True)
def window(image,valid,x,y,guard=2):
 if x<guard or y<guard:return None
 if not all(valid[yy][xx] for yy in range(y-2,y+1) for xx in range(x-2,x+1)):return None
 return [image[yy][xx] for yy in range(y-2,y+1) for xx in range(x-2,x+1)]
def reference(im):
 ga=[[0]*W for _ in range(H)];gv=[[False]*W for _ in range(H)]
 mag=[[0]*W for _ in range(H)];direction=[[0]*W for _ in range(H)];mv=[[False]*W for _ in range(H)]
 full=[[True]*W for _ in range(H)]
 for y in range(H):
  for x in range(W):
   p=window(im,full,x,y)
   if p is not None:
    if args.preserve:p=[v if abs(v-p[4])<=16 else p[4] for v in p]
    ga[y][x]=(sum(v*w for v,w in zip(p,[1,2,1,2,4,2,1,2,1]))+8)//16;gv[y][x]=True
 for y in range(H):
  for x in range(W):
   p=window(ga,gv,x,y,8)
   if p is None:continue
   a,b,c,d,e,f,g,h,i=p
   gx=3*(c-a)+10*(f-d)+3*(i-g);gy=3*(g-a)+10*(h-b)+3*(i-c)
   ax,ay=abs(gx),abs(gy);mag[y][x]=(ax+ay)//4;mv[y][x]=True
   direction[y][x]=0 if ay*256<=ax*106 else 2 if ax*256<=ay*106 else 1 if (gx<0)==(gy<0) else 3
 labels=[[0]*W for _ in range(H)];lv=[[False]*W for _ in range(H)]
 for y in range(H):
  for x in range(W):
   p=window(mag,mv,x,y)
   if p is None:continue
   lv[y][x]=True;dr=direction[y-1][x-1];a,b=[(3,5),(0,8),(1,7),(2,6)][dr]
   if p[4]>=p[a] and p[4]>p[b] and p[4]>=T//2:labels[y][x]=2 if p[4]>=T else 1
 for _ in range(2):
  new=[[0]*W for _ in range(H)];nv=[[False]*W for _ in range(H)]
  for y in range(H):
   for x in range(W):
    p=window(labels,lv,x,y)
    if p is not None:
     nv[y][x]=True;new[y][x]=2 if p[4]==2 or (p[4]==1 and 2 in p) else p[4]
  labels,lv=new,nv
 sch=[[min(255,max(0,mag[y][x]-T)//2) if mv[y][x] else 0 for x in range(W)] for y in range(H)]
 can=[[255 if lv[y][x] and labels[y][x]==2 else 0 for x in range(W)] for y in range(H)]
 if args.invert:
  sch=[[255-v for v in row] for row in sch];can=[[255-v for v in row] for row in can]
 return ga,sch,can
rng=random.Random(1600)
patterns=[[[100]*W for _ in range(H)],[[30 if x<W//2 else 170 for x in range(W)] for y in range(H)],
 [[40 if x<y else 180 for x in range(W)] for y in range(H)],
 [[100+rng.randrange(-8,9) for x in range(W)] for y in range(H)],
 [[rng.randrange(256) for x in range(W)] for y in range(H)]]
# Directed weak contour with strong seed; isolated impulses and fine ripples.
patterns += [[[40 if x<W//2 else (100 if 22<=y<=24 else 60) for x in range(W)] for y in range(H)],
 [[240 if x==32 and y==24 else 100 for x in range(W)] for y in range(H)],
 [[100+(6 if (x+y)%2 else -6) for x in range(W)] for y in range(H)]]
blur,_,_=reference(patterns[3])
raw_error=sum((patterns[3][y-1][x-1]-100)**2 for y in range(2,H) for x in range(2,W))
blur_error=sum((blur[y][x]-100)**2 for y in range(2,H) for x in range(2,W))
assert blur_error<raw_error
print(f'Fine-noise squared error {raw_error} -> {blur_error}',flush=True)
if args.preserve:
 blur,_,_=reference(patterns[1])
 assert all(blur[y][x]==patterns[1][y-1][x-1] for y in range(2,H) for x in range(2,W))
pipe=collections.deque([(1,0,0,0,0,0)]*23)
with (out/'vectors.txt').open('w') as f:
 def emit(vs,de,value=0,g=0,s=0,c=0):
  pipe.append((1,vs,de,g*0x010101,s*0x010101,c*0x010101));expected=pipe.popleft()
  f.write(' '.join(format(v,'x') for v in (1,vs,de,value*0x010101,*expected))+'\n')
 for im in patterns:
  ga,sch,can=reference(im)
  for _ in range(32):emit(0,0)
  for _ in range(10):emit(1,0)
  for y in range(H):
   for x in range(W):emit(1,1,im[y][x],ga[y][x],sch[y][x],can[y][x])
   for _ in range(6):emit(1,0)
 for _ in range(32):emit(0,0)
bin=Path('D:/intelfpga/modelsim_ase/win32aloem')
sources=list((ROOT/'src/isp').glob('*.v'))+[ROOT/'testbench/advanced_isp_tb.sv']
logs=[]
for tool,params in [('vlib',['work']),('vlog',['-sv',*map(str,sources)]),('vsim',['-c','work.advanced_isp_tb',f'-gPRESERVE={args.preserve}',f'-gINVERT={args.invert}','-do','onerror {quit -code 1}; run -all; quit -code 0'])]:
 p=subprocess.run([str(bin/(tool+'.exe')),*params],cwd=out,capture_output=True,text=True,errors='replace')
 logs.append(p.stdout+p.stderr);(out/'simulation.log').write_text('\n'.join(logs),encoding='utf-8')
 if p.returncode or '** Fatal' in logs[-1] or '** Error' in logs[-1]:raise SystemExit(logs[-1])
assert 'PASS ADVANCED' in logs[-1],logs[-1]
print(logs[-1][-500:])
