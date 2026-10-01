"""v1.2 / 7: Isolated spatial-detection RTL tests with final ROM/vector copies."""
import argparse,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('target',choices=['capture','shared','box','auto','uart','compat']);p.add_argument('--model-bundle',type=Path);a=p.parse_args()
out=ROOT/'tmp'/('detector_'+a.target);out.mkdir(parents=True,exist_ok=True)
for rel in ['src/cnn/rom','src/cnn/rom_v1_2','ml/gesture/artifacts/vectors','ml/detector/artifacts/vectors']:
 if (ROOT/rel).exists():shutil.copytree(ROOT/rel,out/rel,dirs_exist_ok=True)
if a.target=='box':(out/'test_threshold.hex').write_text('0200\n')
# v1.2 / 26: Isolated candidate weights never replace deployment ROMs.
if a.model_bundle:
 bundle=a.model_bundle.resolve()
 if not bundle.is_relative_to(ROOT):raise SystemExit('Bundle must remain in CNN workspace')
 for rel in ['src/cnn/rom_v1_2','ml/detector/artifacts/vectors']:
  shutil.copytree(bundle/rel,out/rel,dirs_exist_ok=True)
sources=list((ROOT/'src/cnn').glob('*.v'))+[ROOT/f'testbench/detector_{a.target}_tb.sv']
if a.target=='uart':sources+=list((ROOT/'src/control').glob('*.v'))
logs=[];tool=Path('D:/intelfpga/modelsim_ase/win32aloem')
for exe,args in [('vlib',['work']),('vlog',['-sv',*map(str,sources)]),('vsim',['-c',f'work.detector_{a.target}_tb','-do','onerror {quit -code 1}; run -all; quit -code 0'])]:
 r=subprocess.run([str(tool/(exe+'.exe')),*args],cwd=out,capture_output=True,text=True,errors='replace')
 logs.append(r.stdout+r.stderr);(out/'simulation.log').write_text('\n'.join(logs),encoding='utf-8')
 if r.returncode or '** Error' in logs[-1] or '** Fatal' in logs[-1] or 'Failed to open readmem' in logs[-1]:raise SystemExit(logs[-1])
if 'PASS DETECTOR' not in logs[-1]:raise SystemExit(logs[-1])
print(logs[-1][-1600:])
