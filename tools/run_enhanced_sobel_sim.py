"""V0.8: independent image-domain enhanced Sobel reference vs RTL using ModelSim.

Usage: python tools/run_enhanced_sobel_sim.py [--width 32] [--height 24]
Set MODELSIM_BIN if vsim/vlog/vlib are not on PATH.
"""
import argparse
from collections import deque
import os
from pathlib import Path
import random
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--width", type=int, default=32)
    parser.add_argument("--height", type=int, default=24)
    args = parser.parse_args()
    w, h = args.width, args.height
    assert 3 <= w <= 4095 and 3 <= h <= 4095
    out = ROOT / "tools/debug" / f"enhanced_sobel_sim_{w}x{h}"
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(5640)
    reset_result = (1, 1, 0, 0, 0, 0)
    delayed = deque([reset_result] * 14)
    cycles = 0
    with (out / "vectors.txt").open("w", encoding="ascii") as f:
        def emit(rst, hs, vs, de, rgb, magnitude=(False,0), valid=False):
            nonlocal delayed, cycles
            binary = 0xffffff if valid and magnitude[0] else 0
            strength = min(255, magnitude[1]) * 0x010101 if valid else 0
            zero = 0xffffff if valid else 0
            current = (hs, vs, de, binary, strength, zero)
            if rst:
                delayed.append(current)
                expected = delayed.popleft()
            else:
                delayed = deque([reset_result] * 14)
                expected = reset_result
            f.write(" ".join(f"{n:x}" for n in (rst, hs, vs, de, rgb, *expected)) + "\n")
            cycles += 1

        def blank(n, vs=1):
            for t in range(n):
                emit(1, int(t % 4 != 0), vs, 0, rng.randrange(1 << 24))

        def frame(image):
            gray = [[(((p >> 16) & 255) + 2 * ((p >> 8) & 255) + (p & 255)) // 4
                     for p in row] for row in image]
            mag = [[0]*w for _ in range(h)]
            direction = [[0]*w for _ in range(h)]
            for y in range(2,h):
                for x in range(2,w):
                    a,b,c = gray[y-2][x-2:x+1]
                    d,_,f_ = gray[y-1][x-2:x+1]
                    g,k,i = gray[y][x-2:x+1]
                    gx=c+2*f_+i-a-2*d-g; gy=g+2*k+i-a-2*b-c
                    mag[y][x]=abs(gx)+abs(gy)
                    direction[y][x] = 0 if 2*abs(gy)<=abs(gx) else 2 if 2*abs(gx)<=abs(gy) else 1 if (gx<0)==(gy<0) else 3
            nms = [[0]*w for _ in range(h)]
            for y in range(4,h):
                for x in range(4,w):
                    cy,cx=y-1,x-1
                    dy,dx=((0,1),(1,1),(1,0),(1,-1))[direction[cy][cx]]
                    m=mag[cy][cx]
                    if m>=mag[cy-dy][cx-dx] and m>=mag[cy+dy][cx+dx]: nms[y][x]=m
            state=[[2 if x>=4 and y>=4 and nms[y][x]>=128 else 1 if x>=4 and y>=4 and nms[y][x]>=64 else 0 for x in range(w)] for y in range(h)]
            connected=[[False]*w for _ in range(h)]
            for y in range(6,h):
                for x in range(6,w):
                    v=state[y-1][x-1]
                    connected[y][x]=v==2 or v==1 and any(state[yy][xx]==2 for yy in range(y-2,y+1) for xx in range(x-2,x+1) if (yy,xx)!=(y-1,x-1))
            blank(20, vs=0)
            blank(17)
            for y,row in enumerate(image):
                for x,pixel in enumerate(row):
                    valid=x>=8 and y>=8
                    edge=valid and connected[y-1][x-1] and any(connected[yy][xx] for yy in range(y-2,y+1) for xx in range(x-2,x+1) if (yy,xx)!=(y-1,x-1))
                    strength=nms[y-2][x-2] if valid else 0
                    emit(1,1,1,1,pixel,(edge,strength),valid)
                blank(1+y%7)
            blank(12)

        for _ in range(3): emit(0, 1, 0, 0, 0)
        patterns = [
            lambda x,y: 0,
            lambda x,y: 0xffffff,
            lambda x,y: 0xffffff if x >= w//2 else 0,
            lambda x,y: 0xffffff if y >= h//2 else 0,
            lambda x,y: 0xffffff if x*w//h >= y else 0,
            lambda x,y: 0xffffff if (x+y)%2 else 0,
            lambda x,y: 0xffffff if (x,y)==(w//2,h//2) else 0,
            lambda x,y: 0x202020 if x >= w//2 else 0,  # |Gx| = 128 threshold equality
            lambda x,y: rng.randrange(1 << 24),       # exercises RGB conversion
            lambda x,y: 0x707070,                     # previous frame contamination
        ]
        for pattern in patterns:
            frame([[pattern(x,y) for x in range(w)] for y in range(h)])
        frame([[rng.randrange(1 << 24) for x in range(w)] for y in range(h)])
        frame([[0x808080 for x in range(w)] for y in range(h)])
        blank(20)

    def tool(name):
        if os.getenv("MODELSIM_BIN"):
            return str(Path(os.environ["MODELSIM_BIN"]) / (name + ".exe"))
        found = shutil.which(name)
        if not found:
            raise RuntimeError(f"{name} not found; set MODELSIM_BIN")
        return found

    sources = [ROOT / "src/isp" / n for n in
               ("video_window3x3.v", "video_window3x3_generic.v", "video_sobel.v", "video_processing.v")]
    sources.append(ROOT / "testbench/enhanced_video_processing_tb.sv")
    commands = [
        [tool("vlib"), "work"],
        [tool("vlog"), "-sv", *map(str, sources)],
        [tool("vsim"), "-c", "-onfinish", "stop", f"-gWIDTH={w}",
         "work.enhanced_video_processing_tb", "+VECTORS=vectors.txt", "-do",
         "onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0"],
    ]
    log = []
    for command in commands:
        result = subprocess.run(command, cwd=out, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, errors="replace")
        log.append(result.stdout)
        (out / "simulation.log").write_text("\n".join(log), encoding="utf-8")
        if result.returncode:
            raise RuntimeError(result.stdout)
    if "PASS:" not in log[-1]:
        raise RuntimeError(log[-1])
    print(f"PASS: {cycles} cycles, {w}x{h}; binary/strength/thresholds/bypass/VS polarity")
    print(f"Log: {out / 'simulation.log'}")


if __name__ == "__main__":
    main()
