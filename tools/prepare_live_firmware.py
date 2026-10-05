"""Build a separate live application from the verified official-derived r4 app."""
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[1]
standalone=ROOT/'artifacts/evsoc-system-r1/embedded_sw/SapphireSoc/software/standalone'
source=standalone/'evsoc_tinyml_gesture_reference'
target=standalone/'evsoc_tinyml_gesture_live'
if target.exists():
    raise RuntimeError('Live app already exists; preserve local changes')
shutil.copytree(source,target,ignore=shutil.ignore_patterns('build','.git'))
main=target/'src/main.cc'
text=main.read_text(encoding='utf-8')
marker="// Replacement for the YOLO demo's main() during static accelerator validation."
assert text.count(marker)==1
main.write_text(text.split(marker)[0]+(ROOT/'firmware/evsoc_gesture/live_main.inc').read_text(),encoding='utf-8')
shutil.copy2(ROOT/'firmware/evsoc_gesture/gesture_result.h',target/'src/gesture_result.h')
print(target)
