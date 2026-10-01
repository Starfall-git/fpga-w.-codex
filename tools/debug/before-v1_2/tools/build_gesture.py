"""v1.1 / 17: Rebuild only this CNN copy, with separate generated output/logs.

Never invokes programmer or touches the sibling main checkout. Pass --flow to
run one stage. Full build = map, interface, pnr, pgm (bitstream generation only).
"""
import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--efinity',type=Path,default=Path('C:/Users/francis/Desktop/FPGA Contest/env/Efinity IDE/2026.1'))
parser.add_argument('--flow',choices=['all','map','interface','pnr','pgm'],default='all')
args=parser.parse_args()
if ROOT.name!='fpga-w.-codex-cnn':raise SystemExit('Unexpected workspace: refusing build')
project=ROOT/'Ti60_AR0135.xml'
for element in ET.parse(project).iter():
    if element.tag.endswith('design_file'):
        source=(ROOT/element.attrib['name']).resolve()
        if not source.is_relative_to(ROOT):raise SystemExit('Source escapes CNN checkout: '+str(source))
for name in ['weights.hex','biases.hex','shifts.hex','threshold.hex']:
    if not (ROOT/'src/cnn/rom'/name).is_file():raise SystemExit('Export trained model first: '+name)
env=os.environ.copy()
# v1.1 / 22: Match the vendor setup.bat user configuration lookup.
env['EFINITY_USER_DIR_INI']=(Path(env['LOCALAPPDATA'])/'efinity/user_dir.ini').as_posix()
env['EFINITY_HOME']=args.efinity.as_posix()
env['PYTHONHOME']=str(args.efinity/'python311')
env['PATH']=';'.join(str(args.efinity/p) for p in ['bin','python311/bin','pgm/bin','scripts'])+';'+env['PATH']
for key,sub in [('EFXPT_HOME','pt'),('EFXPGM_HOME','pgm'),('EFXDBG_HOME','debugger'),('EFXIPM_HOME','ipm')]:
    env[key]=(args.efinity/sub).as_posix()
env['QT_PLUGIN_PATH']=str(args.efinity/'python311')
out=ROOT/'outflow_v1_1';out.mkdir(exist_ok=True)
# v1.1 / 26: Bind successful full builds to source/ROM hashes and timing checks.
def input_hashes():
    paths={project, *ROOT.glob('*.sdc'), *ROOT.glob('*.peri.xml')}
    for element in ET.parse(project).iter():
        if element.tag.endswith('design_file'):paths.add((ROOT/element.attrib['name']).resolve())
    paths.update((ROOT/'src/cnn/rom').glob('*.hex'))
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}
initial_hashes=input_hashes()
started=datetime.now(timezone.utc).isoformat()
for flow in (['map','interface','pnr','pgm'] if args.flow=='all' else [args.flow]):
    command=[str(args.efinity/'python311/bin/python.exe'),str(args.efinity/'scripts/efx_run.py'),
             project.name,'--prj','-f',flow,'--output_dir',str(out)]
    print('Starting',flow,flush=True)
    with (out/(flow+'.log')).open('w',encoding='utf-8') as log:
        result=subprocess.run(command,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    if result.returncode:raise SystemExit(f'{flow} failed; see {out/flow}.log')
    print('PASS',flow,flush=True)

if args.flow=='all':
    if input_hashes()!=initial_hashes:raise SystemExit('Inputs changed during build; rebuild required')
    timing=(out/'Ti60_AR0135.timing.rpt').read_text(errors='replace')
    sections=timing.split('Setup (Max) Clock Relationship',1)[1].split('NOTE:',1)[0]
    setup,hold=sections.split('Hold (Min) Clock Relationship',1)
    def slacks(part):
        values=[float(m[1]) for m in re.findall(r'^\s*\S+\s+\S+\s+(-?[\d.]+)\s+(-?[\d.]+)\s+\(',part,re.M)]
        if not values:raise ValueError('No timing relationships found')
        return min(values)
    timing_summary={'minimum_setup_slack_ns':slacks(setup),'minimum_hold_slack_ns':slacks(hold)}
    if min(timing_summary.values())<0:raise SystemExit('Timing failed: '+str(timing_summary))
    files=['Ti60_AR0135.bit','Ti60_AR0135.timing.rpt','Ti60_AR0135.place.rpt','Ti60_AR0135.hier_util.rpt']
    result=dict(version='v1.1',started_utc=started,finished_utc=datetime.now(timezone.utc).isoformat(),
                source_sha256=initial_hashes,timing=timing_summary,hardware_tested=False,
                outputs_sha256={f:hashlib.sha256((out/f).read_bytes()).hexdigest() for f in files})
    (out/'build_manifest.json').write_text(json.dumps(result,indent=2))
    print('Timing PASS',timing_summary,flush=True)
