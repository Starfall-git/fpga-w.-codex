"""Compare a resource candidate using the unchanged r3 ELF and official tools.

Run with Efinity's bin/python3.bat. JTAG programming is volatile; no Flash access.
Requires exclusive access to the FT232H adapter and TCP port 3333.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SDK = Path('C:/Users/SteLl1a/Desktop/Work/FPGA_Contest/env/RISCV-IDE')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--project', type=Path, required=True)
    ap.add_argument('--run-name', default='board-comparison-r1')
    ap.add_argument('--skip-program', action='store_true', help='Only for an image just programmed with a retained log')
    ap.add_argument('--elf', type=Path, help='Explicit derived validation firmware; recorded by hash')
    ap.add_argument('--reference-report', type=Path, help='Independent desktop reference backend report')
    args = ap.parse_args()
    project = args.project.resolve()
    project.relative_to(ROOT / 'artifacts')
    with socket.socket() as check:
        if check.connect_ex(('127.0.0.1', 3333)) == 0:
            raise RuntimeError('Port 3333 is occupied; close the existing debug session first')
    work = project / args.run_name
    work.mkdir(exist_ok=False)
    baseline = ROOT / 'artifacts/evsoc-debug-lanes-r3/board-run'
    shutil.copytree(baseline / 'debug', work / 'debug')
    shutil.copy2(baseline / 'cpu0.yaml', work / 'cpu0.yaml')
    shutil.copytree(baseline / 'firmware', work / 'firmware')
    if args.elf:
        if not args.reference_report:
            raise RuntimeError('A derived ELF requires its independent reference report')
        shutil.copy2(args.elf, work / 'firmware/evsoc_tinyml_gesture.elf')
    bit = project / 'outflow/Ti60_AR0135.bit'
    elf = work / 'firmware/evsoc_tinyml_gesture.elf'
    flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
    def run(command, name, cwd=work, timeout=180):
        with (work / name).open('w', encoding='utf-8') as log:
            result = subprocess.run(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=timeout, creationflags=flags)
        result.check_returncode()
        return (work / name).read_text(encoding='utf-8', errors='replace')
    if not args.skip_program:
        programmer = Path(os.environ['EFINITY_HOME']) / 'pgm/bin/efx_pgm/ftdi_program.py'
        log = run([sys.executable, str(programmer), str(bit), '-m', 'jtag', '-u',
                   'ftdi://0x0403:0x6014:2:6/1', '-b', 'Generic Board Profile Using FT232H',
                   '--jtag_clock_freq', '1000000'], 'program-jtag.log')
        if 'finished with JTAG programming' not in log:
            raise RuntimeError('No JTAG programming completion message')
    with (work / 'openocd.log').open('w', encoding='utf-8') as log:
        server = subprocess.Popen([str(SDK / 'openocd/bin/openocd.exe'), '-f',
                                   'cnn_ft232h_ti.cfg', '-f', 'debug_ti.cfg'],
                                  cwd=work / 'debug', stdout=log, stderr=subprocess.STDOUT,
                                  creationflags=flags)
        try:
            time.sleep(4)
            if server.poll() is not None:
                raise RuntimeError('OpenOCD exited; inspect openocd.log')
            gdb = str(SDK / 'toolchain/bin/riscv-none-elf-gdb.exe')
            verified = run([gdb, '-batch', '-x', 'debug/load-verify.gdb'], 'load-verify.log')
            sections = re.findall(r'Section (\S+), range .*: (\S+)', verified)
            if len(sections) != 5 or any(status != 'matched.' for _, status in sections):
                raise RuntimeError('ELF section readback did not match')
            source = (work / 'debug/run-static.gdb').read_text()
            source = source.replace('print cnn_debug_status', 'print hw_accel_setting\nprint cnn_debug_status')
            (work / 'debug/run-static.gdb').write_text(source)
            output = run([gdb, '-batch', '-x', 'debug/run-static.gdb'], 'run-static.log', timeout=60)
            match = re.search(r'CNN_RESULT (\d+) (\d+) (\d+) (\d+) (\d+)', output)
            if not match:
                raise RuntimeError('No readable CNN_RESULT')
            magic, stage, error, completed, passed = map(int, match.groups())
            vectors = [list(map(int, row)) for row in re.findall(
                r'CNN_VECTOR (\d+) (-?\d+) (-?\d+) (-?\d+) (\d+) (\d+)', output)]
            expected = [[11, 0, -2], [-1, 79, -60], [1, -75, 63]]
            reference_sha = None
            if args.reference_report:
                reference = json.loads(args.reference_report.read_text())
                if reference['model_sha256'] != '7891518a9b70ec6b3be8649123651780ce87ede1e69a9a49c394c17d203a0baa':
                    raise RuntimeError('Reference report is for a different model')
                expected = [v['output_int8'] for v in reference['reference_vectors']]
                reference_sha = sha(args.reference_report)
            result = dict(bit_sha256=sha(bit), elf_sha256=sha(elf),
                          programmed_in_this_run=not args.skip_program,
                          reference_report_sha256=reference_sha,
                          magic=magic, stage=stage, error=error, completed=completed, passed=passed,
                          vectors=vectors, expected=expected,
                          invoke_ms=[((v[4] << 32) + v[5]) / 96000 for v in vectors],
                          execution_verified=magic == 0x47444231 and completed == 3 and stage in (9, 255),
                          exact_match_verified=magic == 0x47444231 and stage == 9 and error == 0 and
                          completed == passed == 3 and [v[1:4] for v in vectors] == expected,
                          live_camera_verified=False)
            (work / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
            print(json.dumps(result, indent=2), flush=True)
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()

if __name__ == '__main__':
    main()
