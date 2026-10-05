"""Wire real EVSoC into the isolated candidate; never downloads or edits the original."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import xml.etree.ElementTree as ET

R = Path(__file__).resolve().parents[1]
O = R / 'artifacts/evsoc-system-r1'


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--tinyml-defines', type=Path, default=R/'config/cnn/tinyml_core0_define.v')
args=parser.parse_args()
report = O / 'top_integration.json'
if report.exists():
    old = json.loads(report.read_text(encoding='utf-8'))
    if digest(O / 'example_top.v') != old['top_sha256']:
        raise RuntimeError('Candidate top edited; preserve changes before regenerating')
s = (R / 'example_top.v').read_text(encoding='utf-8')
marker = re.search(r'(output\s+spi_ssn_o\s*)\n\);', s)
assert marker
jports = ',\n' + ',\n'.join(
    ('output' if k == 'TDO' else 'input') + ' wire jtag_inst1_' + k
    for k in ['TCK', 'TDI', 'TDO', 'SEL', 'CAPTURE', 'SHIFT', 'UPDATE', 'RESET']) + '\n);'
s = s[:marker.start()] + marker.group(1) + jports + s[marker.end():]
a = s.index('DdrCtrl ddr3_ctl_axi')
b = s.index('\n\t);', a) + 5
block = s[a:b]
mp = {'avalid':'avalid','aready':'aready','aaddr':'addr','aid':'id','alen':'len',
      'asize':'size','aburst':'burst','alock':'lock2','atype':'write','wid':'wid',
      'wvalid':'wvalid','wready':'wready','wdata':'wdata','wstrb':'wstrb','wlast':'wlast',
      'bvalid':'bvalid','bready':'bready','bid':'unused_bid','bresp':'bresp',
      'rvalid':'rvalid','rready':'rready','rdata':'rdata','rid':'unused_rid',
      'rresp':'rresp','rlast':'rlast'}
for k, v in mp.items():
    assert block.count('w_ddr3_' + k) == 1, k
    block = block.replace('w_ddr3_' + k, 'cnn_mem_' + v)
s = s[:a] + block + s[b:]
s = s.replace('.SNAPSHOT_ENABLE(1),.CAMERA_ENABLE(1),',
              '.SNAPSHOT_ENABLE(1),.CAMERA_ENABLE(1),.CNN_ENABLE(1),', 1)
s = s.replace('.key_data(key_data), .pixel_clk(clk_pixel)',
              '.cnn_requested_o(cnn_requested),.cnn_applied_i(cnn_applied),'
              '.cnn_available_i(cnn_available),\n        .key_data(key_data), .pixel_clk(clk_pixel)', 1)
for sig, port in [('vs','vid_pVSync'),('hs','vid_pHSync'),('de','vid_pVDE')]:
    s = s.replace('.'+port+'(processed_'+sig+')', '.'+port+'(cnn_display_'+sig+')')
s = s.replace(".vid_pData(HDMI_TEST_PATTERN ? 24'hFF00FF : processed_rgb)",
              ".vid_pData(HDMI_TEST_PATTERN ? 24'hFF00FF : cnn_display_rgb)")
h = (R / 'src/cnn/cnn_evsoc_memory.v').read_text(encoding='utf-8').split('\n);')[0]
ports = re.findall(r'^(input|output) wire\s*(\[[^\]]+\])?\s*(\w+),?$', h, re.M)
c = {'clk_96':'w_ddr3_ui_clk','ai_reset':'cnn_ai_reset','ai_online':'cnn_hardware_ready',
     'fabric_rst_n':'w_ddr3_ui_aresetn','ai_quiescent':'cnn_quiescent',
     'uart_clk':'clk_sys','uart_rst_n':'rstn_sys','requested':'cnn_requested',
     'applied':'cnn_applied','available':'cnn_available','inference_enable':'cnn_inference_enable',
     'system_reset':'cnn_system_reset','memory_reset':'cnn_memory_reset',
     'peripheral_reset':'cnn_peripheral_reset','pixel_clk':'clk_pixel','pixel_rst_n':'rstn_pixel',
     'rgb_i':'processed_rgb','hs_i':'processed_hs','vs_i':'processed_vs','de_i':'processed_de',
     'rgb_o':'cnn_display_rgb','hs_o':'cnn_display_hs','vs_o':'cnn_display_vs',
     'de_o':'cnn_display_de','displayed_source_frame':'cnn_display_frame','idle_o':'cnn_fabric_idle'}
for k, v in {'enable':'SEL','tdi':'TDI','tdo':'TDO','tck':'TCK','capture':'CAPTURE',
             'shift':'SHIFT','update':'UPDATE','reset':'RESET'}.items():
    c['jtagCtrl_'+k] = 'jtag_inst1_'+v
for d, w, n in ports:
    if n.startswith('system_') and n not in c:
        # JTAG software load/debug only until physical SPI/UART ownership is verified.
        c[n] = "1'b1" if d == 'input' else ''
    if n.startswith('video_'):
        k = n[6:]
        v = {'addr':'aaddr','id':'aid','len':'alen','size':'asize','burst':'aburst',
             'write':'atype','lock':'alock'}.get(k, k)
        c[n] = 'w_ddr3_'+v
        if k == 'id': c[n] = "{4'b0,w_ddr3_aid}"
        if k in ('bid','rid'): c[n] = 'cnn_video_'+k
        if k == 'lock': c[n] = '|w_ddr3_alock'
    if n.startswith('m_'): c[n] = 'cnn_mem_'+n[2:]
assert set(c) == {n for _, _, n in ports}
lines = ['// CNN: original video reset remains independent of AI reset.',
         'wire [1:0] cnn_requested,cnn_applied,cnn_quiescent;',
         'wire cnn_available,cnn_inference_enable,cnn_ai_reset,cnn_hardware_ready;',
         'wire cnn_system_reset,cnn_memory_reset,cnn_peripheral_reset,cnn_fabric_idle;',
         'wire [23:0] cnn_display_rgb;wire cnn_display_hs,cnn_display_vs,cnn_display_de;',
         'wire [31:0] cnn_display_frame;wire [7:0] cnn_video_bid,cnn_video_rid;',
         'assign w_ddr3_bid=cnn_video_bid[3:0];assign w_ddr3_rid=cnn_video_rid[3:0];',
         'wire [3:0] cnn_mem_unused_bid,cnn_mem_unused_rid;wire [1:0] cnn_mem_lock2;',
         "assign cnn_mem_lock2={1'b0,cnn_mem_lock};"]
for d, w, n in ports:
    if n.startswith('m_'): lines.append('wire '+(w or '')+' cnn_mem_'+n[2:]+';')
lines += ["""cnn_ai_reset u_cnn_reset(.clk(w_ddr3_ui_clk),.rst_n(w_ddr3_ui_aresetn),
 .memory_ready(r_ddr_unlock && w_ddr3_cal_pass),.reset_request(1'b0),
 .soc_reset(cnn_system_reset | cnn_memory_reset | cnn_peripheral_reset),
 .quiescent(cnn_quiescent),.ai_reset(cnn_ai_reset),.hardware_ready(cnn_hardware_ready));""",
          'cnn_evsoc_memory u_cnn_system(\n'+',\n'.join(' .'+n+'('+c[n]+')' for _,_,n in ports)+'\n);\n']
# Place wiring after existing declarations and processing instances, before HDMI.
idx = s.index('    // HDMI Interface.')
s = s[:idx] + '\n'.join(lines) + s[idx:]
(O / 'example_top.v').write_text(s, encoding='utf-8')
shutil.copytree(R / 'src/cnn', O / 'src/cnn', dirs_exist_ok=True)
shutil.copy2(R / 'src/control/uart_image_control.v', O / 'src/control/uart_image_control.v')
ns = 'http://www.efinixinc.com/enf_proj'
ET.register_namespace('efx', ns)
ET.register_namespace('xsi', 'http://www.w3.org/2001/XMLSchema-instance')
# Official generator calls reshape RESHAPE_MODE; official RTL consumes RS_MODE.
# Preserve its generated value with an alias in this derived configuration only.
defs = O / 'official_source/tinyml/tinyml_core0_define.v'
if args.tinyml_defines:
    shutil.copy2(args.tinyml_defines, defs)
d = defs.read_text(encoding='utf-8')
if '`define TML_C0_RS_MODE' not in d:
    assert '`define TML_C0_RESHAPE_MODE' in d
    d += '\n// Generator/RTL 2026.1 naming compatibility; same reshape setting.\n`define TML_C0_RS_MODE `TML_C0_RESHAPE_MODE\n'
    defs.write_text(d, encoding='utf-8')
xt = ET.parse(O / 'Ti60_AR0135.xml')
di = xt.getroot().find('{'+ns+'}design_info')
existing = {e.get('name') for e in di.findall('{'+ns+'}design_file')}
files = [p.relative_to(O).as_posix() for p in sorted((O / 'src/cnn').glob('*.v'))]
files += ['official_source/tinyml/'+n for n in ['tinyml_defines.v','tinyml_core0_define.v',
           'tinyml_accelerator.v','tinyml_accelerator_channels.v','tinyml_top.v']]
# Use the official source manifest, including helpers referenced inside protected RTL.
files += ['official_source/'+n.strip() for n in (O/'official_source/source.f').read_text(encoding='utf-8').splitlines() if n.strip() and not n.lstrip().startswith('//')]
files=list(dict.fromkeys(files))
for name in files:
    if name not in existing:
        ET.SubElement(di, '{'+ns+'}design_file', name=name, version='default', library='default')
mapopts = next(e for e in xt.iter() if any(c.get('name')=='include' for c in e))
if not any(e.get('name')=='include' and e.get('value')=='official_source/tinyml' for e in mapopts):
    ET.SubElement(mapopts, '{'+ns+'}param', name='include', value='official_source/tinyml', value_type='e_string')
for e in di.findall('{'+ns+'}design_file'):
    if e.get('name') in files: e.set('version', 'sv_09')
# XSD requires every design_file before top_vhdl_arch/options.
entries=sorted(di.findall('{'+ns+'}design_file'), key=lambda e:e.get('name'))
for e in entries: di.remove(e)
for index,e in enumerate(entries,1): di.insert(index,e)
ET.indent(xt, space='    ')
xt.write(O / 'Ti60_AR0135.xml', encoding='utf-8', xml_declaration=True)
base = (R / 'Ti60_AR0135.peri.xml').read_text(encoding='utf-8')
off = (R / 'artifacts/evsoc-gesture-r1/edge_vision_soc.peri.xml').read_text(encoding='utf-8')
jtag = re.search(r'<efxpt:jtag_info>.*?</efxpt:jtag_info>', off, re.S).group()
assert '<efxpt:jtag_info/>' in base
(O / 'Ti60_AR0135.peri.xml').write_text(base.replace('<efxpt:jtag_info/>', jtag), encoding='utf-8')
# Preserve original video timing; add official 10MHz USER1 clock and delays.
sdc=(R/'Ti60_AR0135.pt.sdc').read_text(encoding='utf-8')
sdc+='\n# Official EVSoC USER1 debug clock; no AI data-path false paths added.\ncreate_clock -period 100 -name jtag_inst1_TCK [get_ports {jtag_inst1_TCK}]\n'
interface_sdc=O/'outflow/Ti60_AR0135.pt.sdc'
# On a clean preparation, run interface generation and this script again for delays.
for line in (interface_sdc.read_text(encoding='utf-8').splitlines() if interface_sdc.exists() else []):
    if line.startswith(('set_input_delay','set_output_delay')) and 'jtag_inst1_' in line:
        if any('{jtag_inst1_'+k+'}' in line for k in ('TCK','TDI','TDO','SEL','CAPTURE','SHIFT','UPDATE','RESET')): sdc+=line+'\n'
(O/'Ti60_AR0135.pt.sdc').write_text(sdc,encoding='utf-8')
report.write_text(json.dumps({'source_top_sha256':digest(R/'example_top.v'),
    'top_sha256':digest(O/'example_top.v'),'connections':c,'top_integrated':True,
    'synthesized':False,'programmed':False,'firmware_ready_required':True,
    'spi_and_soc_uart_physical_connections':'pending; JTAG download/debug only',
    'sources':{n:digest(O/n) for n in files}}, indent=2)+'\n', encoding='utf-8')
print('Candidate integrated:', O, 'with', len(ports), 'wrapper connections')
