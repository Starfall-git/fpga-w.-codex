"""V0.14: exercise physical UART and the production DDR frame owner."""
from pathlib import Path
import os
import subprocess
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'tools/debug/snapshot_sim'
OUT.mkdir(parents=True,exist_ok=True)
BIN=Path(os.environ.get('MODELSIM_BIN','D:/intelfpga/modelsim_ase/win32aloem'))
sources=[*sorted((ROOT/'src/control').glob('*.v')),ROOT/'src/axi/ddr_frame_owner.v',ROOT/'testbench/snapshot_tb.sv']
logs=[]
for tool,args in [('vlib',['work']),('vlog',['-sv',*map(str,sources)]),
                  ('vsim',['-c','work.snapshot_tb','-do','onerror {quit -code 1}; run -all; quit -code 0'])]:
    p=subprocess.run([str(BIN/(tool+'.exe')),*args],cwd=OUT,capture_output=True,text=True,errors='replace')
    logs.append(p.stdout+p.stderr)
    (OUT/'simulation.log').write_text('\n'.join(logs),encoding='utf-8')
    if p.returncode or '** Error' in logs[-1] or '** Fatal' in logs[-1]:raise SystemExit(logs[-1])
assert 'PASS SNAPSHOT' in logs[-1],logs[-1]
print(logs[-1][-700:])
