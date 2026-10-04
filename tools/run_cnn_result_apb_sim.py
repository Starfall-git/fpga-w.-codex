"""Verify the APB publication protocol against the actual asynchronous mailbox."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/cnn-result-apb-sim"
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
run("vlog", "-sv", ROOT / "src/cnn/cnn_result_mailbox.v", ROOT / "src/cnn/cnn_result_apb.v",
    ROOT / "testbench/cnn_result_apb_tb.sv")
if "PASS CNN result APB:" not in run("vsim", "-c", "work.cnn_result_apb_tb", "-do", "run -all; quit -f"):
    raise SystemExit("APB simulation did not finish successfully")

# Compile a real caller with the vendor SDK. This is not a target execution.
SDK = Path(os.environ.get("RISCV_SDK", "C:/Users/SteLl1a/Desktop/Work/FPGA_Contest/env/RISCV-IDE"))
PROJECT = ROOT / "artifacts/evsoc-gesture-r1/embedded_sw/SapphireSoc"
source = OUT / "publish_test.cc"
source.write_text('#include "gesture_result.h"\nint publish_test(uintptr_t base) { return gesture_publish_result(base, 42, 2, 3, 14, 11, 1, 2); }\n')
command = [str(SDK / "toolchain/bin/riscv-none-elf-g++.exe"), "-c",
           "-march=rv32im_zicsr_zifencei", "-mabi=ilp32", "-O2", "-Wall", "-Werror",
           "-I" + str(ROOT / "firmware/evsoc_gesture"),
           "-I" + str(PROJECT / "bsp/efinix/EfxSapphireSoc/include"),
           "-I" + str(PROJECT / "software/standalone/driver"),
           str(source), "-o", str(OUT / "publish_test.o")]
compiled = subprocess.run(command, capture_output=True, text=True)
(OUT / "firmware_compile.log").write_text(compiled.stdout + compiled.stderr, encoding="utf-8")
if compiled.returncode:
    raise SystemExit(compiled.stdout + compiled.stderr)
import hashlib
import json
files = ["src/cnn/cnn_result_apb.v", "src/cnn/cnn_result_mailbox.v",
         "testbench/cnn_result_apb_tb.sv", "firmware/evsoc_gesture/gesture_result.h",
         "tools/run_cnn_result_apb_sim.py"]
report = {"simulation_pass": True, "firmware_compile_exit": compiled.returncode,
          "firmware_command": command, "hardware_verified": False,
          "top_integrated": False,
          "sha256": {f: hashlib.sha256((ROOT / f).read_bytes()).hexdigest() for f in files},
          "simulation_log_sha256": hashlib.sha256((OUT / "vsim.log").read_bytes()).hexdigest()}
(OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print("PASS vendor RISC-V result publisher compilation")
