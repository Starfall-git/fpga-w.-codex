"""Load and verify the existing ELF, then run its static self-test through GDB.
Requires the matching .bit already configured and official OpenOCD on port3333.
No Flash access. No hardware breakpoint is required.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--project', type=Path, required=True)
    ap.add_argument('--sdk', type=Path, default=Path('C:/Users/SteLl1a/Desktop/Work/FPGA_Contest/env/RISCV-IDE'))
    ap.add_argument('--run-ms', type=int, default=10000)
    args = ap.parse_args()
    if not 1 <= args.run_ms <= 60000:
        ap.error("--run-ms must be between 1 and 60000")
    work = args.project.resolve() / 'board-run'
    elf = work / 'firmware/evsoc_tinyml_gesture.elf'
    gdb = args.sdk / 'toolchain/bin/riscv-none-elf-gdb.exe'
    header = '''set pagination off
set confirm off
set print pretty on
set remotetimeout 30
file firmware/evsoc_tinyml_gesture.elf
target extended-remote localhost:3333
monitor halt
monitor debug_level 1
monitor adapter speed 800
'''
    def run(name, body):
        script = work / 'debug' / (name + '.gdb')
        script.write_text(header + body, encoding='utf-8')
        with (work / (name + '.log')).open('w', encoding='utf-8') as log:
            proc = subprocess.run([str(gdb), '-batch', '-x', str(script)], cwd=work,
                                  stdout=log, stderr=subprocess.STDOUT, timeout=180)
        text = (work / (name + '.log')).read_text(encoding='utf-8', errors='replace')
        (work / (name + '.exitcode')).write_text(str(proc.returncode))
        print(text, flush=True)
        if proc.returncode:
            raise RuntimeError(f'{name} failed; see its log. Firmware was not accepted as passed.')
        return text
    verified = run('load-verify', 'load\nmonitor reset halt\ncompare-sections\nmonitor halt\ndisconnect\nquit\n')
    sections = re.findall(r'Section (\S+), range .*: (\S+)', verified)
    if not sections or any(status != 'matched.' for _, status in sections):
        raise RuntimeError('ELF section verification failed; do not execute corrupted firmware')
    text = run('run-static', f'''set $pc = _start
monitor resume 0x1000
monitor sleep {args.run_ms}
monitor halt
print cnn_debug_status
printf "CNN_RESULT %u %u %u %u %u\\n", cnn_debug_status.magic, cnn_debug_status.stage, cnn_debug_status.error, cnn_debug_status.completed, cnn_debug_status.passed
set $cnn_sample = 0
while $cnn_sample < 3
printf "CNN_VECTOR %d %d %d %d %u %u\\n", $cnn_sample, cnn_debug_status.actual[$cnn_sample][0], cnn_debug_status.actual[$cnn_sample][1], cnn_debug_status.actual[$cnn_sample][2], cnn_debug_status.ticks_hi[$cnn_sample], cnn_debug_status.ticks_lo[$cnn_sample]
set $cnn_sample = $cnn_sample + 1
end
monitor reg pc
monitor reg mcause
monitor reg mepc
monitor reg mtval
disconnect
quit
''')
    found = re.search(r'CNN_RESULT (\d+) (\d+) (\d+) (\d+) (\d+)', text)
    if not found:
        raise RuntimeError('No readable self-test status')
    magic, stage, error, completed, passed = map(int, found.groups())
    vectors = [list(map(int, row)) for row in re.findall(r'CNN_VECTOR (\d+) (-?\d+) (-?\d+) (-?\d+) (\d+) (\d+)', text)]
    expected = [[11, 0, -2], [-1, 79, -60], [1, -75, 63]]
    outputs_match = len(vectors) == 3 and [row[1:4] for row in vectors] == expected
    completed_run = magic == 0x47444231 and completed == 3 and stage in (9, 255)
    result = dict(elf_execution_verified=completed_run, vectors=vectors, expected=expected, elf_sha256=hashlib.sha256(elf.read_bytes()).hexdigest(),
                  sections=sections, magic=hex(magic), stage=stage, error=error,
                  completed=completed, passed=passed,
                  target_run_verified=(magic == 0x47444231 and stage == 9 and error == 0 and completed == passed == 3 and outputs_match))
    (work / 'static-result.json').write_text(json.dumps(result, indent=2) + '\n')
    if not result['target_run_verified']:
        raise RuntimeError('ELF executed but strict INT8 comparison failed' if completed_run else 'Self-test incomplete; inspect static-result.json and run-static.log')
    print('PASS: existing ELF verified and all three INT8 vectors matched.')

if __name__ == '__main__':
    main()
