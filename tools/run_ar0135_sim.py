"""V0.7 / 34: run wire-level I2C and full 720p capture regression."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tools/debug/ar0135_sim"
OUT.mkdir(parents=True, exist_ok=True)
BIN = Path(os.environ.get("MODELSIM_BIN", "D:/intelfpga/modelsim_ase/win32aloem"))


def run(name, *args):
    result = subprocess.run([str(BIN / (name + ".exe")), *map(str, args)], cwd=OUT,
                            capture_output=True, text=True)
    output = result.stdout + result.stderr
    (OUT / (name + ".log")).write_text(output, encoding="utf-8")
    print(output)
    if result.returncode or "** Error" in output or "** Fatal" in output:
        raise SystemExit(1)
    return output


if not (OUT / "work").exists():
    run("vlib", "work")
run("vlog", "-sv", *(ROOT / "src/cmos_i2c" / f for f in
    ["I2C_AR0135_1280720_Config.v", "ar0135_init.v", "ar0135_capture.v"]),
    ROOT / "testbench/ar0135_tb.sv")
output = run("vsim", "-c", "work.ar0135_tb", "-do", "run -all; quit -f")
if "PASS AR0135:" not in output:
    raise SystemExit("Camera simulation did not pass")
