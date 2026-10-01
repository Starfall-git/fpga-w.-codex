"""v1.1 / 17: Rebuild only this CNN copy, with separate generated output/logs.

Never invokes programmer or touches the sibling main checkout. Pass --flow to
run one stage. Full build = map, interface, pnr, pgm (bitstream generation only).
"""
import argparse
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
env['EFINITY_HOME']=args.efinity.as_posix()
env['PYTHONHOME']=str(args.efinity/'python311')
env['PATH']=';'.join(str(args.efinity/p) for p in ['bin','python311/bin','pgm/bin','scripts'])+';'+env['PATH']
for key,sub in [('EFXPT_HOME','pt'),('EFXPGM_HOME','pgm'),('EFXDBG_HOME','debugger'),('EFXIPM_HOME','ipm')]:
    env[key]=(args.efinity/sub).as_posix()
env['QT_PLUGIN_PATH']=str(args.efinity/'python311')
out=ROOT/'outflow_v1_1';out.mkdir(exist_ok=True)
for flow in (['map','interface','pnr','pgm'] if args.flow=='all' else [args.flow]):
    command=[str(args.efinity/'python311/bin/python.exe'),str(args.efinity/'scripts/efx_run.py'),
             project.name,'--prj','-f',flow,'--output_dir',str(out)]
    print('Starting',flow,flush=True)
    with (out/(flow+'.log')).open('w',encoding='utf-8') as log:
        result=subprocess.run(command,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    if result.returncode:raise SystemExit(f'{flow} failed; see {out/flow}.log')
    print('PASS',flow,flush=True)
