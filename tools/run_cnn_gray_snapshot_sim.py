"""Check RAW8 sampling, RAM ownership and APB reads on asynchronous clocks."""
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/cnn-gray-snapshot-sim'
BIN=Path(os.environ.get('MODELSIM_BIN','D:/WORK/modelsim/win64'))
OUT.mkdir(parents=True,exist_ok=True)
def run(name,*args):
    result=subprocess.run([str(BIN/(name+'.exe')),*map(str,args)],cwd=OUT,
                          capture_output=True,text=True,timeout=180)
    text=result.stdout+result.stderr
    (OUT/(name+'.log')).write_text(text,encoding='utf-8')
    print(text)
    if result.returncode or '** Error' in text or '** Fatal' in text:
        raise RuntimeError(name+' failed')
    return text
if not (OUT/'work').exists(): run('vlib','work')
run('vlog','-sv',ROOT/'src/cnn/cnn_gray_snapshot.v',ROOT/'testbench/cnn_gray_snapshot_tb.sv')
if 'PASS CNN gray snapshot:' not in run('vsim','-c','work.cnn_gray_snapshot_tb','-do','run -all; quit -f'):
    raise RuntimeError('Simulation did not finish')
