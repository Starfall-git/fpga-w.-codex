"""V0.4: run physical UART / asynchronous pixel-domain integration simulation."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
out = ROOT / "tools/debug/uart_sim"
out.mkdir(parents=True, exist_ok=True)
bin_dir = Path(os.environ.get("MODELSIM_BIN", "D:/intelfpga/modelsim_ase/win32aloem"))


def run(exe, *args):
    result = subprocess.run([str(bin_dir / (exe + ".exe")), *args], cwd=out,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(result.stdout)
    (out / (exe + ".log")).write_text(result.stdout, encoding="utf-8")
    if result.returncode or "** Error" in result.stdout or "** Fatal" in result.stdout:
        raise SystemExit(1)
    return result.stdout


if not (out / "work").exists():
    run("vlib", "work")
sources = sorted((ROOT / "src/control").glob("*.v"))
# V0.9 / 46: this checkout uses the standalone Sobel; obsolete generic-window
# dependency from the previous algorithm must not break the UART regression.
sources.append(ROOT / "src/isp/video_sobel.v")
run("vlog", "-sv", *[str(p) for p in sources], str(ROOT / "testbench/uart_control_tb.sv"))
output = run("vsim", "-c", "work.uart_control_tb", "-do", "run -all; quit -f")
if "PASS UART:" not in output:
    raise SystemExit("UART simulation did not finish successfully")
