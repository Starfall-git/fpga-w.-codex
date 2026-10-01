"""v1.1 / 14: Isolated ModelSim regression; paths anchored to the CNN workspace."""
# v1.1 / 24: Include real camera-ROI-CNN integration regression.
import argparse
from pathlib import Path
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('target',choices=['roi','cnn','uart','pipeline','integration'])
args=parser.parse_args()
out=ROOT/'tmp'/('gesture_'+args.target);out.mkdir(exist_ok=True,parents=True)
for relative in ['src/cnn/rom','ml/gesture/artifacts/vectors']:
    source=ROOT/relative
    if source.exists():shutil.copytree(source,out/relative,dirs_exist_ok=True)
tool=Path('D:/intelfpga/modelsim_ase/win32aloem')
sources=list((ROOT/'src/cnn').glob('*.v'))
if args.target=='uart':sources+=list((ROOT/'src/control').glob('*.v'))
sources+=[ROOT/f'testbench/gesture_{args.target}_tb.sv']
logs=[]
for executable,parameters in [('vlib',['work']),('vlog',['-sv',*map(str,sources)]),
 ('vsim',['-c',f'work.gesture_{args.target}_tb','-do','onerror {quit -code 1}; run -all; quit -code 0'])]:
    result=subprocess.run([str(tool/(executable+'.exe')),*parameters],cwd=out,capture_output=True,text=True,errors='replace')
    logs.append(result.stdout+result.stderr)
    (out/'simulation.log').write_text('\n'.join(logs),encoding='utf-8')
    if result.returncode or '** Error' in logs[-1] or '** Fatal' in logs[-1]:raise SystemExit(logs[-1])
if 'PASS GESTURE' not in logs[-1]:raise SystemExit(logs[-1])
print(logs[-1][-1400:])
