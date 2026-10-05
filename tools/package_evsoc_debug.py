"""Package the verified candidate outputs; never programs or resets a board."""
import hashlib
import json
import re
from pathlib import Path
import shutil
import subprocess
import zipfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'artifacts/evsoc-system-r1'
TUTORIAL = ROOT.parent / 'CNN-Tutorial'
VERSION = 'v0.5-ti60-debug-r1'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    destination = ROOT / 'artifacts/releases' / VERSION
    archive = ROOT / 'deliverables' / (VERSION + '.zip')
    if destination.exists() or archive.exists():
        raise RuntimeError('Release already exists; use a new version rather than overwrite')
    for stage in ('map', 'interface', 'pnr', 'pgm'):
        if (PROJECT / (stage + '.exitcode')).read_text().strip() != '0':
            raise RuntimeError(f'{stage} did not succeed')
    hardware = json.loads((TUTORIAL / 'docs/05_experiments/v0.5/top_integration_report.json').read_text())
    # Do not label a subsequently modified top/constraints as this routed design.
    for name in ('example_top.v', 'Ti60_AR0135.xml', 'Ti60_AR0135.pt.sdc'):
        if sha(PROJECT / name) != hardware['files'][name]:
            raise RuntimeError(f'Hardware evidence changed: {name}; review before packaging')
    # Generated report hashes differ from the historical record. Re-audit the
    # current resource totals and all setup/hold relationships rather than reuse
    # stale report hashes or silently claim the files are identical.
    map_text = (PROJECT / 'outflow/Ti60_AR0135.map.out').read_text()
    for resource, count in hardware['resources'].items():
        matches = re.findall(r'EFX_' + resource + r'\s*:\s*(\d+)', map_text)
        if not matches or int(matches[-1]) != count:
            raise RuntimeError(f'Unexpected current resource count: {resource}')
    timing = (PROJECT / 'outflow/Ti60_AR0135.timing.rpt').read_text()
    setup_text, hold_text = timing.split('Setup (Max) Clock Relationship', 1)[1].split('Hold (Min) Clock Relationship', 1)
    hold_text = hold_text.split('NOTE:', 1)[0]
    def relationships(text):
        return [(a, b, float(c), float(s)) for a, b, c, s in
                re.findall(r'^\s*(\w+)\s+(\w+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+\(', text, re.M)]
    setup, hold = relationships(setup_text), relationships(hold_text)
    negative = [(a, b, s) for a, b, _, s in setup if s < 0]
    if (len(setup) != 17 or len(hold) != 17 or any(s < 0 for _, _, _, s in hold)
            or negative != [('clk_sys', 'jtag_inst1_TCK', -0.384), ('jtag_inst1_TCK', 'clk_sys', -1.307)]):
        raise RuntimeError('Current timing differs from the reviewed debug-release limitations')
    software = json.loads((PROJECT / 'official_build_report.json').read_text())
    app = PROJECT / 'embedded_sw/SapphireSoc/software/standalone/evsoc_tinyml_gesture'
    bsp = PROJECT / 'embedded_sw/SapphireSoc/bsp/efinix/EfxSapphireSoc'
    for path, key in ((app / 'build/evsoc_tinyml_gesture.elf', 'elf_sha256'), (app / 'src/main.cc', 'main_sha256')):
        if sha(path) != software[key]:
            raise RuntimeError(f'Software differs from the last successful build: {path}')
    pgm_log = (PROJECT / 'outflow/Ti60_AR0135.pgm.out').read_text()
    if str(PROJECT / 'work_pnr/Ti60_AR0135.lbf') not in pgm_log:
        raise RuntimeError('PGM log does not identify this candidate LBF')
    for suffix in ('bit', 'hex'):
        path = PROJECT / f'outflow/Ti60_AR0135.{suffix}'
        if not path.stat().st_size or path.stat().st_mtime < (PROJECT / 'work_pnr/Ti60_AR0135.lbf').stat().st_mtime:
            raise RuntimeError(f'Missing/stale programming file: {path}')

    sources = {
        'hardware/Ti60_AR0135.bit': PROJECT / 'outflow/Ti60_AR0135.bit',
        'hardware/Ti60_AR0135.hex': PROJECT / 'outflow/Ti60_AR0135.hex',
        'firmware/evsoc_tinyml_gesture.elf': app / 'build/evsoc_tinyml_gesture.elf',
        'source/main.cc': app / 'src/main.cc',
        'source/soc.h': bsp / 'include/soc.h',
        'source/default.ld': bsp / 'linker/default.ld',
        'source/cnn_gesture_data.h': app / 'src/cnn_gesture_data.h',
        'source/example_top.v': PROJECT / 'example_top.v',
        'cpu0.yaml': PROJECT / 'embedded_sw/SapphireSoc/cpu0.yaml',
        'README.md': TUTORIAL / 'docs/05_experiments/v0.5/debug_release.md',
        'LICENSE-TinyML.txt': TUTORIAL / 'refs/TinyML/upstream-2026.1/LICENSE.txt',
        'LICENSE-BSP.md': bsp / 'include/LICENSE.MD',
    }
    for name in ('ftdi_ti.cfg', 'cnn_ft232h_ti.cfg', 'debug_ti.cfg'):
        sources['debug/' + name] = bsp / 'openocd' / name
    for path in (ROOT / 'firmware/evsoc_gesture/debug_tools').iterdir():
        sources['debug/' + path.name if path.suffix == '.gdb' else path.name] = path
    for name in ('pgm-console.log', 'official_build_report.json', 'debug_firmware_preparation.json', 'debug_adapter_report.json'):
        sources['evidence/' + name] = PROJECT / name
    for name in ('Ti60_AR0135.pgm.out', 'Ti60_AR0135.timing.rpt', 'Ti60_AR0135.res.csv', 'Ti60_AR0135.map.out'):
        sources['evidence/' + name] = PROJECT / 'outflow' / name
    # Include the corresponding updated host UI as a runnable snapshot.
    for path in (ROOT / 'host').iterdir():
        if path.is_file() and path.suffix in ('.py', '.txt', '.md', '.bat'):
            sources['host/' + path.name] = path
    files = {}
    for relative, path in sources.items():
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        files[relative] = {'bytes': target.stat().st_size, 'sha256': sha(target)}
    manifest = {
        'version': VERSION, 'created_utc': datetime.now(timezone.utc).isoformat(),
        'base_fpga_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'source_note': 'Debug firmware and host changes are included as source snapshots; see release commit for packaging tools.',
        'device': 'Ti60F225 C4', 'cpu_hz': 96000000, 'tinyml_parallel': '2x2',
        'flows': {s: 'PASS' for s in ('map', 'interface', 'pnr', 'pgm', 'software_build')},
        'timing_signed_off': False, 'worst_reported_setup_slack_ns': -1.307,
        'current_report_audit': {'resources': hardware['resources'], 'setup_relationships': setup, 'hold_relationships': hold,
                                 'note': 'Current generated report files differ in hash from historical top_integration_report; source top/XML/SDC hashes match and the current reports were re-audited.'},
        'target_run_verified': False, 'live_camera_inference': False, 'soc_uart_connected': False,
        'user_board_report': 'User reports programming attempt; screenshot shows SPI Active using JTAG Bridge. COM8 opens but GET_STATUS timed out. Business bit/ELF execution not yet confirmed.',
        'expected_int8_outputs': [[11, 0, -2], [-1, 79, -60], [1, -75, 63]],
        'build_inputs': {p: sha(PROJECT / p) for p in ('work_pnr/Ti60_AR0135.lbf', 'outflow/Ti60_AR0135.lpf', 'Ti60_AR0135.xml', 'Ti60_AR0135.pt.sdc')},
        'files': files,
    }
    (destination / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    archive.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(destination.rglob('*')):
            if path.is_file():
                bundle.write(path, path.relative_to(destination).as_posix())
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise RuntimeError('Archive CRC verification failed')
        for name, entry in files.items():
            if hashlib.sha256(bundle.read(name)).hexdigest() != entry['sha256']:
                raise RuntimeError(f'Archive hash mismatch: {name}')
    result = {'version': VERSION, 'archive': str(archive), 'archive_bytes': archive.stat().st_size,
              'archive_sha256': sha(archive), 'bit_sha256': files['hardware/Ti60_AR0135.bit']['sha256'],
              'elf_sha256': software['elf_sha256'], 'payload_count': len(files),
              'archive_verified': True, 'timing_signed_off': False, 'target_run_verified': False}
    (ROOT / 'deliverables' / (VERSION + '.json')).write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
