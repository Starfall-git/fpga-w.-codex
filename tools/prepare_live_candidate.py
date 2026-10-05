"""Derive live snapshot hardware from the verified r4 project, preserving r4."""
from pathlib import Path
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'artifacts/evsoc-4x4-fc-disable-map'
target = ROOT / 'artifacts/evsoc-live-r5'
if target.exists():
    raise RuntimeError('Candidate exists; preserve it rather than overwriting')
target.mkdir()
for name in ('ip', 'src', 'official_source'):
    shutil.copytree(source/name, target/name)
for name in ('example_top.v', 'Ti60_AR0135.xml', 'Ti60_AR0135.peri.xml', 'Ti60_AR0135.pt.sdc'):
    shutil.copy2(source/name, target/name)
for name in ('cnn_gray_snapshot.v', 'cnn_live_endpoint.v', 'cnn_soc_subsystem.v', 'cnn_evsoc_memory.v'):
    shutil.copy2(ROOT/'src/cnn'/name, target/'src/cnn'/name)
top = target/'example_top.v'
text = top.read_text(encoding='utf-8')
marker = 'cnn_evsoc_memory u_cnn_system('
assert text.count(marker) == 1
text = text.replace(marker, marker + '\n .cam_clk(w_cmos_pclk),.cam_rst_n(rstn_sys),\n'
    ' .cam_frame_valid(cmos_frame_vsync),.cam_pixel_valid(cmos_frame_href),.cam_gray(cnn_raw_gray8),')
top.write_text(text, encoding='utf-8')
ns = 'http://www.efinixinc.com/enf_proj'
ET.register_namespace('efx', ns)
ET.register_namespace('xsi', 'http://www.w3.org/2001/XMLSchema-instance')
tree = ET.parse(target/'Ti60_AR0135.xml')
info = tree.getroot().find('{'+ns+'}design_info')
for name in ('cnn_gray_snapshot.v', 'cnn_live_endpoint.v'):
    info.insert(1, ET.Element('{'+ns+'}design_file', name='src/cnn/'+name, version='sv_09', library='default'))
ET.indent(tree, space='    ')
tree.write(target/'Ti60_AR0135.xml', encoding='utf-8', xml_declaration=True)
report = {'source': str(source), 'candidate': str(target), 'purpose': 'Live RAW8 snapshot and inference',
          'files': {str(p.relative_to(target)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in target.rglob('*') if p.is_file()}}
(target/'preparation.json').write_text(json.dumps(report, indent=2)+'\n')
print(target)
