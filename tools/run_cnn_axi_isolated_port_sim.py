"""Run the named CNN DDR module regression and fail on missing PASS or errors."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/cnn-axi-isolated-port-sim"
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
run("vlog", "-sv", ROOT / "src/cnn/cnn_axi_transaction_buffer.v", ROOT / "src/cnn/cnn_axi_window.v", ROOT / "src/cnn/cnn_axi_isolated_port.v", ROOT / "testbench/cnn_axi_isolated_port_tb.sv")
if "PASS CNN isolated port:" not in run("vsim", "-c", "work.cnn_axi_isolated_port_tb", "-do", "run -all; quit -f"):
    raise SystemExit("Memory window simulation did not finish successfully")
