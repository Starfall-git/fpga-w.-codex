"""Package the measured live candidate without overwriting a prior release."""
from pathlib import Path
import hashlib,json,shutil,zipfile
R=Path(__file__).resolve().parents[1]
P=R/'artifacts/evsoc-live-r5'; W=P/'board-live-r1'
VERSION='v0.5-ti60-live-r5'
OUT=R/'deliverables'/VERSION; ZIP=OUT.parent/(VERSION+'.zip')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
for stage in ('map','interface','pnr','pgm'):
    assert (P/(stage+'-live.exit')).read_text(encoding='utf-8-sig').strip()=='0'
ref=json.loads((W/'final-sample-reference.json').read_text())
control=json.loads((W/'uart-controls.json').read_text())
assert ref['exact_match'] and ref['checksum_verified'] and control['disable_stops_new_inference'] and control['overlay_independent']
assert not OUT.exists() and not ZIP.exists()
app=R/'artifacts/evsoc-system-r1/embedded_sw/SapphireSoc/software/standalone/evsoc_tinyml_gesture_live'
files={'README.md':R/'docs/CNN_LIVE_R5.md','hardware/Ti60_AR0135.bit':P/'outflow/Ti60_AR0135.bit',
       'firmware/evsoc_tinyml_gesture.elf':W/'firmware/evsoc_tinyml_gesture.elf','cpu0.yaml':W/'cpu0.yaml',
       'start-openocd.ps1':R/'firmware/evsoc_gesture/debug_tools/start-openocd.ps1',
       'start-gdb.ps1':R/'firmware/evsoc_gesture/debug_tools/start-gdb-live.ps1',
       'source/main.cc':app/'src/main.cc','source/gesture_result.h':app/'src/gesture_result.h',
       'source/example_top.v':P/'example_top.v','source/tinyml_core0_define.v':P/'official_source/tinyml/tinyml_core0_define.v'}
assert sha(files['firmware/evsoc_tinyml_gesture.elf'])==sha(app/'build/evsoc_tinyml_gesture.elf')
for n in ('cnn_ft232h_ti.cfg','debug_ti.cfg','load-verify.gdb','run-live.gdb'): files['debug/'+n]=W/'debug'/n
for n in ('cnn_gray_snapshot.v','cnn_live_endpoint.v','cnn_soc_subsystem.v','cnn_evsoc_memory.v'): files['source/'+n]=P/'src/cnn'/n
for n in ('final-sample.json','final-sample-reference.json','final-sample-input.bin','continuous-check.json','uart-controls.json','disabled-a.json','disabled-b.json','overlay-off.json','load-verify-final.log','run-live-final.log','program-jtag.log'):
    files['evidence/'+n]=W/n
for n in ('Ti60_AR0135.timing.rpt','Ti60_AR0135.hier_util.rpt'): files['evidence/'+n]=P/'outflow'/n
for n in ('LICENSE-TinyML.txt','LICENSE-BSP.md'): files[n]=R/'artifacts/releases/v0.5-ti60-debug-r1'/n
for f in (R/'host').iterdir():
    if f.is_file() and f.suffix in ('.py','.txt','.md','.bat'): files['host/'+f.name]=f
for name,src in files.items():
    dest=OUT/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
payload={str(p.relative_to(OUT)).replace('\\','/'):{'sha256':sha(p),'bytes':p.stat().st_size} for p in OUT.rglob('*') if p.is_file()}
manifest={'version':VERSION,'files':payload,'live_camera_input_reference_match':True,'uart_controls_verified':True,
          'hdmi_visual_verified':False,'timing_signed_off':False,'stage6_complete':False}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
with zipfile.ZipFile(ZIP,'x',zipfile.ZIP_DEFLATED) as z:
    for f in OUT.rglob('*'):
        if f.is_file(): z.write(f,f.relative_to(OUT).as_posix())
with zipfile.ZipFile(ZIP) as z:
    assert z.testzip() is None
    for name,info in payload.items(): assert hashlib.sha256(z.read(name)).hexdigest()==info['sha256']
summary={k:v for k,v in manifest.items() if k!='files'}
summary.update(archive_sha256=sha(ZIP),bit_sha256=sha(files['hardware/Ti60_AR0135.bit']),elf_sha256=sha(files['firmware/evsoc_tinyml_gesture.elf']),payload_count=len(payload))
(R/'deliverables'/(VERSION+'.json')).write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
