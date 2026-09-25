"""V0.11 / 55: validate eight-direction RTL against signed kernel dot products."""
from pathlib import Path
import os
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tools/debug/sobel8_sim"
OUT.mkdir(parents=True, exist_ok=True)
KERNELS = (
    (-1, -2, -1, 0, 0, 0, 1, 2, 1),
    (-2, -1, 0, -1, 0, 1, 0, 1, 2),
    (-1, 0, 1, -2, 0, 2, -1, 0, 1),
    (0, 1, 2, -1, 0, 1, -2, -1, 0),
)
rng = random.Random(135)
windows = [[255 if bits & (1 << i) else 0 for i in range(9)] for bits in range(512)]
windows += [[value] * 9 for value in range(256)]
windows += [[rng.randrange(256) for _ in range(9)] for _ in range(1000)]
count = 0
with (OUT / "vectors.txt").open("w", encoding="ascii") as f:
    for window in windows:
        mag = max(abs(sum(p * k for p, k in zip(window, kernel))) for kernel in KERNELS)
        for threshold in sorted({0, mag, min(4095, mag + 1), 4095}):
            polarity = rng.randrange(2)
            de, valid = int(rng.random() > .05), int(rng.random() > .1)
            hs, vs = rng.randrange(2), rng.randrange(2)
            def binary(t):
                hit = valid and mag >= t
                return 0xffffff if de and (hit == bool(polarity)) else 0
            adaptive = binary(max(threshold, window[4], 1))
            fixed = binary(threshold)
            diagnostic = min(mag, 255) * 0x010101 if de and valid else 0
            pixels = int.from_bytes(bytes(window), "big")
            f.write(" ".join(f"{x:x}" for x in (pixels, threshold, polarity, de, valid,
                    hs, vs, adaptive, fixed, diagnostic)) + "\n")
            count += 1
bin_dir = Path(os.environ.get("MODELSIM_BIN", "D:/intelfpga/modelsim_ase/win32aloem"))
logs = []
for exe, args in (
    ("vlib", ["work"]),
    ("vlog", ["-sv", str(ROOT / "src/isp/video_sobel.v"), str(ROOT / "testbench/sobel8_tb.sv")]),
    ("vsim", ["-c", "work.sobel8_tb", "-do", "onerror {quit -code 1}; run -all; quit -code 0"]),
):
    result = subprocess.run([str(bin_dir / (exe + ".exe")), *args], cwd=OUT,
                            capture_output=True, text=True, errors="replace")
    logs.append(result.stdout + result.stderr)
    (OUT / "simulation.log").write_text("\n".join(logs), encoding="utf-8")
    if result.returncode or "** Error" in logs[-1] or "** Fatal" in logs[-1]:
        raise SystemExit(logs[-1])
assert "PASS SOBEL8" in logs[-1], logs[-1]
print(f"PASS SOBEL8: {count} independent kernel vectors; {OUT / 'simulation.log'}")
