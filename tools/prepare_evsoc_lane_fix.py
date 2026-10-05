"""Prepare r3 from the preserved r2 hardware with the Sapphire masked-store fix.
Never overwrites a candidate or touches the original fpga-w.-codex checkout.
"""
from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'artifacts/evsoc-debug-reset-r2'
TARGET = ROOT / 'artifacts/evsoc-debug-lanes-r3'

def main():
    if TARGET.exists():
        raise FileExistsError(f'Candidate already exists: {TARGET}')
    TARGET.mkdir()
    skip = shutil.ignore_patterns('work', 'work_syn', 'work_pnr', 'work_pt',
                                 'outflow', 'ooc', '__pycache__', '*.log')
    for name in ('src', 'ip', 'official_source'):
        shutil.copytree(SOURCE / name, TARGET / name, ignore=skip)
    for name in ('example_top.v', 'Ti60_AR0135.xml', 'Ti60_AR0135.peri.xml', 'Ti60_AR0135.pt.sdc'):
        shutil.copy2(SOURCE / name, TARGET / name)
    window = ROOT / 'src/cnn/cnn_axi_window.v'
    shutil.copy2(window, TARGET / 'src/cnn/cnn_axi_window.v')
    report = {
        'source': str(SOURCE), 'candidate': str(TARGET),
        'change': 'Normalize Sapphire 128-bit masked-store addresses to beat boundary; preserve WDATA/WSTRB',
        'window_sha256': hashlib.sha256(window.read_bytes()).hexdigest(),
        'board_verified': False,
    }
    (TARGET / 'experiment.json').write_text(json.dumps(report, indent=2) + '\n')
    print(TARGET)

if __name__ == '__main__':
    main()
