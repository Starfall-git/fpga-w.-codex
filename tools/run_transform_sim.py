"""V0.5: mathematical nearest-neighbour oracle vs actual dual-clock AXI reader."""
import argparse
import os
from pathlib import Path
import random
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def reference(width, height, flags, x, y, w, h, n, d, bank=1):
    scaled_w, scaled_h = w*n//d, h*n//d
    left, top = max(0, (width-scaled_w)//2), max(0, (height-scaled_h)//2)
    skip_x, skip_y = max(0, (scaled_w-width)//2), max(0, (scaled_h-height)//2)
    for oy in range(height):
        for ox in range(width):
            if not (left <= ox < left+min(width, scaled_w) and top <= oy < top+min(height, scaled_h)):
                yield 0
                continue
            sx, sy = (ox-left+skip_x)*d//n, (oy-top+skip_y)*d//n
            sx = x+(w-1-sx if flags & 2 else sx)
            sy = y+(h-1-sy if flags & 1 else sy)
            yield (((sy*width+sx)*37) ^ (bank*0x4321) ^ (sy*257)) & 65535


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--width', type=int, default=32)
    parser.add_argument('--height', type=int, default=16)
    parser.add_argument('--fullframe', action='store_true', help='Four configurations for a full 720-line timing run')
    args = parser.parse_args()
    w,h = args.width,args.height
    cases = [(flip,0,0,w,h,n,d) for flip in range(4) for n,d in ((1,1),(1,4),(1,2),(3,2),(2,1),(3,1),(4,1))]
    cases += [(flip,1,1,w-3,h-3,n,d) for flip in range(4) for n,d in ((1,1),(2,3),(3,2),(4,1))]
    cases += [(0,w-1,h-1,1,1,1,1),(3,0,0,1,1,4,1)]
    rng = random.Random(225)
    for _ in range(16):
        cw,ch=rng.randint(4,w),rng.randint(4,h)
        n,d=rng.choice(((1,4),(3,4),(4,3),(7,5),(16,15)))
        cases.append((rng.randrange(4),rng.randint(0,w-cw),rng.randint(0,h-ch),cw,ch,n,d))
    if args.fullframe:
        cases=[(0,0,0,w,h,1,1),(3,0,0,w,h,1,1),(1,1,1,w-3,h-3,1,2),(2,1,1,w-3,h-3,3,2)]
    # V0.6: percentage endpoints and two-decimal input ratios.
    cases += [(flip,0,0,w,h,n,d) for flip in (0,3) for n,d in ((1,10),(5,1),(499,100),(12345,10000)) if h*n>=d]
    out=ROOT/'tools/debug'/f'transform_sim_{w}x{h}'
    out.mkdir(parents=True,exist_ok=True)
    with (out/'vectors.txt').open('w',encoding='ascii') as f:
        f.write(f'{len(cases)}\n')
        for index,case in enumerate(cases):
            f.write(' '.join(map(str,case))+'\n')
            f.write(' '.join(f'{pixel:04x}' for pixel in reference(w,h,*case,bank=1+index%2))+'\n')
    def tool(name):
        return str(Path(os.environ['MODELSIM_BIN'])/(name+'.exe')) if 'MODELSIM_BIN' in os.environ else shutil.which(name)
    sources=[ROOT/'src/isp'/s for s in ('unsigned_divider.v','axi_transform_reader.v')]+[ROOT/'testbench/transform_reader_tb.sv']
    commands=[[tool('vlib'),'work'],[tool('vlog'),'-sv',*map(str,sources)],
              [tool('vsim'),'-c',f'-gWIDTH={w}',f'-gHEIGHT={h}','work.transform_reader_tb','+VECTORS=vectors.txt',
               '-do','run -all; quit -f']]
    logs=[]
    for command in commands:
        result=subprocess.run(command,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace')
        logs.append(result.stdout)
        (out/'simulation.log').write_text('\n'.join(logs),encoding='utf-8')
        if result.returncode or '** Error' in result.stdout or '** Fatal' in result.stdout:
            raise SystemExit(result.stdout)
    if 'PASS TRANSFORM:' not in logs[-1]: raise SystemExit(logs[-1])
    print(next(line for line in logs[-1].splitlines() if 'PASS TRANSFORM:' in line))
    print(out/'simulation.log')


if __name__=='__main__': main()
