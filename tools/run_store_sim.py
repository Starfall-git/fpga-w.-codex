"""V0.15: control UART plus full-resolution DDR comparison scanline regression."""
from pathlib import Path
import subprocess
import os
import argparse
ROOT=Path(__file__).resolve().parents[1]
BIN=Path(os.environ.get('MODELSIM_BIN','D:/intelfpga/modelsim_ase/win32aloem'))
parser=argparse.ArgumentParser();parser.add_argument('--only',choices=('store_uart','compare_reader'));args=parser.parse_args()
for name in ((args.only,) if args.only else ('store_uart','compare_reader')):
 out=ROOT/'tools/debug'/('v015_'+name);out.mkdir(parents=True,exist_ok=True)
 sources=[*sorted((ROOT/'src/control').glob('*.v')),ROOT/'src/axi/ddr_frame_store.v',ROOT/'src/isp/unsigned_divider.v',ROOT/'src/isp/axi_transform_reader.v',ROOT/('testbench/'+name+'_tb.sv')]
 logs=[]
 for tool,args in [('vlib',['work']),('vlog',['-sv',*map(str,sources)]),('vsim',['-c','work.'+name+'_tb','-do','onerror {quit -code 1}; run -all; quit -code 0'])]:
  p=subprocess.run([str(BIN/(tool+'.exe')),*args],cwd=out,capture_output=True,text=True,errors='replace')
  logs.append(p.stdout+p.stderr);(out/'simulation.log').write_text('\n'.join(logs),encoding='utf-8')
  if p.returncode or '** Error' in logs[-1] or '** Fatal' in logs[-1]:raise SystemExit(logs[-1])
 if 'PASS' not in logs[-1]:raise SystemExit(logs[-1])
 print(logs[-1][-1200:],flush=True)
