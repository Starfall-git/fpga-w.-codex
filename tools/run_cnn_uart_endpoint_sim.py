"""Check asynchronous result transfer and pixel-accurate overlay isolation."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/cnn-uart-endpoint-sim"
OUT.mkdir(parents=True, exist_ok=True)
BIN = Path(os.environ.get("MODELSIM_BIN", "D:/WORK/modelsim/win64"))


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
sources = sorted((ROOT / "src/control").glob("*.v")) + sorted((ROOT / "src/cnn").glob("*.v"))
run("vlog", "-sv", *sources, ROOT / "testbench/cnn_uart_endpoint_tb.sv")
if "PASS CNN UART endpoint:" not in run("vsim", "-c", "work.cnn_uart_endpoint_tb", "-do", "run -all; quit -f"):
    raise SystemExit("Overlay simulation did not finish successfully")
