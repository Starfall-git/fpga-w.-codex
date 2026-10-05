"""Package the r3 hardware and unchanged ELF with truthful board-run evidence."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'artifacts/evsoc-debug-lanes-r3'
VERSION = 'v0.5-ti60-debug-r3'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    out = ROOT / 'deliverables' / VERSION
    archive = ROOT / 'deliverables' / (VERSION + '.zip')
    if out.exists() or archive.exists():
        raise RuntimeError('Refusing to overwrite a debug release')
    run = PROJECT / 'board-run'
    result = json.loads((run / 'static-result.json').read_text())
    if not result['elf_execution_verified']:
        raise RuntimeError('No completed board run')
    for stage in ('map','interface','pnr','pgm'):
        if (PROJECT / (stage + '.exitcode')).read_text().strip() != '0':
            raise RuntimeError(f'{stage} failed')
    if result['elf_sha256'] != sha(run / 'firmware/evsoc_tinyml_gesture.elf'):
        raise RuntimeError('ELF differs from board-run evidence')
    files = {'hardware/Ti60_AR0135.bit': PROJECT / 'outflow/Ti60_AR0135.bit',
             'firmware/evsoc_tinyml_gesture.elf': run / 'firmware/evsoc_tinyml_gesture.elf',
             'cpu0.yaml': run / 'cpu0.yaml', 'README.md': ROOT / 'docs/CNN_ELF_RUN_R3.md',
             'CNN_ELF_RUN_R2.md': ROOT / 'docs/CNN_ELF_RUN_R2.md',
             'source/example_top.v': PROJECT / 'example_top.v',
             'source/cnn_soc_subsystem.v': PROJECT / 'src/cnn/cnn_soc_subsystem.v',
             'source/cnn_axi_window.v': PROJECT / 'src/cnn/cnn_axi_window.v'}
    for name in ('cnn_ft232h_ti.cfg','debug_ti.cfg','load-verify.gdb','run-static.gdb'):
        files['debug/' + name] = run / 'debug' / name
    for name in ('program-jtag.log','openocd.log','load-verify.log','run-static.log','run-after-reset.log','static-result.json','release-launcher.log','release-launcher.exitcode'):
        files['evidence/' + name] = run / name
    for name in ('Ti60_AR0135.map.out','Ti60_AR0135.timing.rpt','Ti60_AR0135.pgm.out','Ti60_AR0135.res.csv'):
        files['evidence/' + name] = PROJECT / 'outflow' / name
    prior = ROOT / 'artifacts/releases/v0.5-ti60-debug-r1'
    for name in ('source/main.cc','source/soc.h','source/default.ld','source/cnn_gesture_data.h','LICENSE-TinyML.txt','LICENSE-BSP.md'):
        files[name] = prior / name
    files['start-openocd.ps1'] = ROOT / 'firmware/evsoc_gesture/debug_tools/start-openocd.ps1'
    for src in (ROOT / 'host').iterdir():
        if src.is_file() and src.suffix in ('.py','.txt','.md','.bat'):
            files['host/' + src.name] = src
    for name, src in files.items():
        dest = out / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src,dest)
    (out / 'start-gdb.ps1').write_text('''param([string]$Sdk = 'C:\\Users\\SteLl1a\\Desktop\\Work\\FPGA_Contest\\env\\RISCV-IDE')
$ErrorActionPreference = 'Stop'
$exe = Join-Path $Sdk 'toolchain/bin/riscv-none-elf-gdb.exe'
if (!(Test-Path -LiteralPath $exe)) { throw "GDB not found: $exe" }
Push-Location $PSScriptRoot
try {
    $ErrorActionPreference = 'Continue'
    $verify = & $exe -batch -x debug/load-verify.gdb 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $verify | Tee-Object -FilePath load-verify.log
    $sections = @($verify | Where-Object { "$_" -match '^Section ' })
    if ($code -ne 0 -or $sections.Count -ne 5 -or @($sections | Where-Object { "$_" -notmatch ': matched\\.$' }).Count -ne 0) {
        throw 'ELF readback failed; execution was not started.'
    }
    $ErrorActionPreference = 'Continue'
    $run = & $exe -batch -x debug/run-static.gdb 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $run | Tee-Object -FilePath run-static.log
    if ($code -ne 0) { throw "GDB exited with $code" }
    if (($run -join "`n") -notmatch 'CNN_RESULT 1195655729 9 0 3 3') {
        Write-Warning 'Read CNN_RESULT above. completed=3 means ELF ran all vectors. This r3 baseline reports stage=255,error=5,passed=1: two outputs differ by one INT8 unit.'
        exit 2
    }
    Write-Output 'PASS: all three INT8 vectors match.'
} finally { Pop-Location }
''', encoding='utf-8-sig')
    payload = {p.relative_to(out).as_posix(): {'bytes': p.stat().st_size, 'sha256': sha(p)} for p in sorted(out.rglob('*')) if p.is_file()}
    manifest = dict(version=VERSION, elf_execution_verified=True,
                    int8_exact_match_verified=result['target_run_verified'],
                    timing_signed_off=False, live_camera_inference=False,
                    worst_setup_slack_ns=-1.297, result=result, files=payload)
    (out / 'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for p in sorted(out.rglob('*')):
            if p.is_file(): z.write(p,p.relative_to(out).as_posix())
    with zipfile.ZipFile(archive) as z:
        if z.testzip(): raise RuntimeError('ZIP CRC error')
        for name, entry in payload.items():
            if hashlib.sha256(z.read(name)).hexdigest()!=entry['sha256']:
                raise RuntimeError(f'ZIP hash error: {name}')
    summary = dict(version=VERSION, archive_sha256=sha(archive), archive_bytes=archive.stat().st_size,
                   bit_sha256=sha(out/'hardware/Ti60_AR0135.bit'), elf_sha256=result['elf_sha256'],
                   payload_count=len(payload), archive_verified=True, elf_execution_verified=True,
                   int8_exact_match_verified=False, completed=3, passed=1, timing_signed_off=False)
    (ROOT/'deliverables'/ (VERSION+'.json')).write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2))

if __name__=='__main__':
    main()
