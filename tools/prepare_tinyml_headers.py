"""v1.3 / 11: Recover missing integer headers into an isolated SDK overlay.

Require every common TensorFlow source file in the two bundled demos to match.
Do not modify either vendor demo or silently mix different runtime versions.
"""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[1]
base=ROOT/'tinyml-main/tinyml_hello_world/Ti60F225_tinyml_helloworld/embedded_sw/sapphire_soc_tinyml/software/standalone'
target=base/'tinyml_imgc/src/tensorflow';donor=base/'tinyml_kws/src/tensorflow'
matched=0
for p in donor.rglob('*'):
    if not p.is_file():continue
    q=target/p.relative_to(donor)
    if q.is_file():
        if p.read_bytes()!=q.read_bytes():raise RuntimeError('Runtime versions differ: '+str(q))
        matched+=1
overlay=ROOT/'firmware/tinyml_gesture_v1_3/vendor_overlay/tensorflow'
copied=[]
for p in (donor/'lite/kernels/internal/reference/integer_ops').glob('*.h'):
    rel=p.relative_to(donor)
    if (target/rel).exists():continue
    q=overlay/rel;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
    copied.append(dict(source=p.relative_to(ROOT).as_posix(),destination=q.relative_to(ROOT).as_posix(),sha256=hashlib.sha256(q.read_bytes()).hexdigest()))
report=dict(version='v1.3',matched_common_files=matched,modified_vendor_files=False,overlay_headers=copied,
            target_compilation_verified=False)
(overlay.parent/'provenance.json').write_text(json.dumps(report,indent=2))
print('Matched',matched,'common files; recovered',len(copied),'integer headers into isolated overlay.')
