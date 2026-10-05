"""Package the measured 4x4/FC-disabled debug candidate and reference fixtures."""
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = 'v0.5-ti60-debug-r4'
PROJECT = ROOT / 'artifacts/evsoc-4x4-fc-disable-map'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    work = PROJECT/'board-reference-r1'
    result = json.loads((work/'result.json').read_text())
    if not result['exact_match_verified']:
        raise RuntimeError('Reference comparison was not verified on the board')
    launcher_log = (work/'launcher.log').read_text(encoding='utf-8-sig', errors='replace')
    if (work/'launcher.exitcode').read_text().strip() != '0' or 'PASS: all three INT8 vectors' not in launcher_log:
        raise RuntimeError('Release launcher was not verified')
    if sha(work/'start-gdb.ps1') != sha(ROOT/'firmware/evsoc_gesture/debug_tools/start-gdb-verified.ps1'):
        raise RuntimeError('Launcher differs from tested source')
    for stage in ('map','interface','pnr','pgm'):
        if (PROJECT/f'{stage}.exitcode').read_text().strip() != '0':
            raise RuntimeError(f'{stage} failed')
    out = ROOT/'deliverables'/VERSION
    archive = out.parent/(VERSION+'.zip')
    if out.exists() or archive.exists():
        raise RuntimeError('Refusing to overwrite release')
    app = ROOT/'artifacts/evsoc-system-r1/embedded_sw/SapphireSoc/software/standalone/evsoc_tinyml_gesture_reference'
    audit = ROOT.parent/'CNN-Tutorial/artifacts/v0.5-backend-audit'
    files = {'README.md': ROOT/'docs/CNN_RESOURCE_R4.md',
             'hardware/Ti60_AR0135.bit': PROJECT/'outflow/Ti60_AR0135.bit',
             'hardware/tinyml_core0_define.v': PROJECT/'official_source/tinyml/tinyml_core0_define.v',
             'firmware/evsoc_tinyml_gesture.elf': work/'firmware/evsoc_tinyml_gesture.elf',
             'cpu0.yaml': work/'cpu0.yaml',
             'start-openocd.ps1': ROOT/'firmware/evsoc_gesture/debug_tools/start-openocd.ps1',
             'start-gdb.ps1': ROOT/'firmware/evsoc_gesture/debug_tools/start-gdb-verified.ps1',
             'reference/report.json': audit/'report.json',
             'reference/reference_validation.json': app/'reference_validation.json',
             'source/main.cc': app/'src/main.cc',
             'source/cnn_gesture_data.cc': app/'src/cnn_gesture_data.cc',
             'source/cnn_gesture_data.h': app/'src/cnn_gesture_data.h',
             'source/makefile': app/'makefile'}
    for name in ('cnn_ft232h_ti.cfg','debug_ti.cfg','load-verify.gdb','run-static.gdb'):
        files['debug/'+name] = work/'debug'/name
    for name in ('openocd.log','load-verify.log','run-static.log','result.json','launcher.log','launcher.exitcode'):
        files['evidence/reference-'+name] = work/name
    for label, project in [('baseline','evsoc-debug-lanes-r3'), ('lite','evsoc-4x4-fc-lite-map'), ('disabled','evsoc-4x4-fc-disable-map')]:
        files[f'evidence/{label}-same-elf-result.json'] = ROOT/'artifacts'/project/'board-comparison-r1/result.json'
    for name in ('Ti60_AR0135.hier_util.rpt','Ti60_AR0135.timing.rpt','Ti60_AR0135.pgm.out'):
        files['evidence/'+name] = PROJECT/'outflow'/name
    for file in audit.glob('*_*.bin'):
        files['reference/'+file.name] = file
    for file in (ROOT/'host').iterdir():
        if file.is_file() and file.suffix in ('.py','.txt','.md','.bat'):
            files['host/'+file.name] = file
    for name in ('LICENSE-TinyML.txt','LICENSE-BSP.md'):
        files[name] = ROOT/'artifacts/releases/v0.5-ti60-debug-r1'/name
    for name, src in files.items():
        dest = out/name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src,dest)
    if sha(out/'hardware/Ti60_AR0135.bit') != result['bit_sha256'] or sha(out/'firmware/evsoc_tinyml_gesture.elf') != result['elf_sha256']:
        raise RuntimeError('Packaged image differs from measured image')
    payload = {p.relative_to(out).as_posix(): dict(bytes=p.stat().st_size,sha256=sha(p))
               for p in sorted(out.rglob('*')) if p.is_file()}
    manifest = dict(version=VERSION, backend='TensorFlow 2.15.1 BUILTIN_REF',
                    exact_match_verified=True, measured_vectors=3, live_camera_verified=False,
                    timing_signed_off=False, launcher_board_verified=True,
                    result=result, files=payload)
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for p in sorted(out.rglob('*')):
            if p.is_file(): z.write(p,p.relative_to(out).as_posix())
    with zipfile.ZipFile(archive) as z:
        if z.testzip(): raise RuntimeError('ZIP CRC failed')
        for name, entry in payload.items():
            if hashlib.sha256(z.read(name)).hexdigest() != entry['sha256']:
                raise RuntimeError(f'ZIP payload hash mismatch: {name}')
    summary = dict(version=VERSION, archive_sha256=sha(archive), archive_bytes=archive.stat().st_size,
                   bit_sha256=result['bit_sha256'], elf_sha256=result['elf_sha256'],
                   archive_verified=True, exact_match_verified=True, payload_count=len(payload),
                   backend=manifest['backend'], live_camera_verified=False, timing_signed_off=False)
    (ROOT/'deliverables'/f'{VERSION}.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2))

if __name__ == '__main__':
    main()
