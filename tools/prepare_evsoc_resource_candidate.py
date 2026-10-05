"""Copy the validated r3 project and install official Generator output.

--verify-existing audits a previously prepared candidate without replacing files.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fc-mode', choices=['lite','disable'], required=True)
    parser.add_argument('--verify-existing', action='store_true')
    args = parser.parse_args()
    base = ROOT/'artifacts/evsoc-debug-lanes-r3'
    output = ROOT/f'artifacts/evsoc-4x4-fc-{args.fc_mode}-map'
    generated = ROOT.parent/f'CNN-Tutorial/artifacts/official-4x4-fc-{args.fc_mode}'
    report = json.loads((generated/'generation_report.json').read_text())
    if not report['model_array_byte_exact'] or report['parameters']['FC_MODE'] != args.fc_mode.upper():
        raise RuntimeError('Generator report does not match requested candidate')
    header = generated/'output/gesture_int8_core0/tinyml_core0_define.v'
    alias = '\n`define TML_C0_RS_MODE `TML_C0_RESHAPE_MODE\n'
    if not args.verify_existing:
        output.mkdir(exist_ok=False)
        for directory in ('ip','src','official_source'):
            shutil.copytree(base/directory, output/directory)
        for name in ('example_top.v','Ti60_AR0135.xml','Ti60_AR0135.peri.xml','Ti60_AR0135.pt.sdc'):
            shutil.copy2(base/name, output/name)
        (output/'official_source/tinyml/tinyml_core0_define.v').write_text(header.read_text()+alias)
    actual = (output/'official_source/tinyml/tinyml_core0_define.v').read_text()
    if [line for line in actual.splitlines() if line.strip()] != [line for line in (header.read_text()+alias).splitlines() if line.strip()]:
        raise RuntimeError('Candidate define differs from official output plus compatibility alias')
    checked = 0
    for folder in ('src','official_source'):
        for source in (base/folder).rglob('*'):
            if source.is_file() and source.name != 'tinyml_core0_define.v':
                if sha(source) != sha(output/source.relative_to(base)):
                    raise RuntimeError(f'Unexpected source change: {source}')
                checked += 1
    for name in ('example_top.v','Ti60_AR0135.xml','Ti60_AR0135.peri.xml','Ti60_AR0135.pt.sdc'):
        if sha(base/name) != sha(output/name):
            raise RuntimeError(f'Unexpected project change: {name}')
    result = dict(base=str(base), output=str(output), checked_source_files=checked,
                  define_sha256=sha(output/'official_source/tinyml/tinyml_core0_define.v'),
                  generator_report_sha256=sha(generated/'generation_report.json'),
                  verified_existing=args.verify_existing)
    (output/'preparation.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))

if __name__ == '__main__':
    main()
