"""Inspect a running r5 ELF through GDB; never loads firmware or changes Flash."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
SDK=Path('C:/Users/SteLl1a/Desktop/Work/FPGA_Contest/env/RISCV-IDE')
FIELDS='magic abi_version stage error clint_hz arena_used completed published frame predicted_class invoke_ticks copy_ticks period_ticks input_checksum input_min input_max capture_errors publish_busy requested pause_after_completed'.split()

def inspect(work,name,pause=None,resume=False,dump=False):
    script='set pagination off\nset confirm off\nset print pretty on\nset remotetimeout 30\nfile firmware/evsoc_tinyml_gesture.elf\ntarget extended-remote localhost:3333\nmonitor halt\n'
    if pause is not None: script+=f'set variable cnn_live_status.pause_after_completed = {pause}\n'
    script+='print cnn_live_status\n'
    for field in FIELDS:
        script+=f'printf "LIVE_FIELD {field} %u\\n", cnn_live_status.{field}\n'
    script+='printf "LIVE_OUTPUT %d %d %d\\n", cnn_live_status.output[0], cnn_live_status.output[1], cnn_live_status.output[2]\n'
    script+='printf "LIVE_APB %u %u %u\\n", *(unsigned int*)0xf810001c, *(unsigned int*)0xf8100044, *(unsigned int*)0xf810004c\n'
    if dump:
        tensor='&cnn_live_input[0]'
        script+=f'if cnn_live_status.stage != 8\n  error "Input/output pair is not paused coherently"\nend\nset $input_begin = {tensor}\nset $input_end = $input_begin+4096\ndump binary memory {name}-input.bin $input_begin $input_end\n'
    if resume: script+='monitor resume\n'
    script+='disconnect\nquit\n'
    path=work/(name+'.gdb');path.write_text(script)
    result=subprocess.run([str(SDK/'toolchain/bin/riscv-none-elf-gdb.exe'),'-batch','-x',path.name],cwd=work,capture_output=True,text=True,errors='replace',timeout=60)
    text=result.stdout+result.stderr
    (work/(name+'.log')).write_text(text)
    result.check_returncode()
    values={k:int(v) for k,v in re.findall(r'LIVE_FIELD (\w+) (\d+)',text)}
    if set(values)!=set(FIELDS): raise RuntimeError('Incomplete live status')
    values['output']=list(map(int,re.search(r'LIVE_OUTPUT (-?\d+) (-?\d+) (-?\d+)',text).groups()))
    values['apb']=list(map(int,re.search(r'LIVE_APB (\d+) (\d+) (\d+)',text).groups()))
    (work/(name+'.json')).write_text(json.dumps(values,indent=2)+'\n')
    print(json.dumps(values,indent=2))
    return values

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('work',type=Path)
    parser.add_argument('name')
    parser.add_argument('--pause',type=int)
    parser.add_argument('--resume',action='store_true')
    parser.add_argument('--dump',action='store_true')
    args=parser.parse_args()
    inspect(args.work.resolve(),args.name,args.pause,args.resume,args.dump)
