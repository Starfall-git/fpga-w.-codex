"""Generate the reviewed SoC/custom-instruction wiring from official public ports.
This only builds the subsystem shell; no functional model replaces vendor IP.
"""
from pathlib import Path
import re,json,hashlib
root=Path(__file__).resolve().parents[1];out=root/'src/cnn/cnn_soc_subsystem.v'
soc=root/'artifacts/evsoc-system-r1/ip/SapphireSoc/SapphireSoc.v'
tiny=root/'artifacts/evsoc-system-r1/official_source/tinyml/tinyml_accelerator_channels.v'
# Read the generated public module declaration only, not its implementation.
report_path=root/'artifacts/evsoc-system-r1/subsystem_ports.json'
if out.exists() and report_path.exists():
 previous=json.loads(report_path.read_text(encoding='utf-8'))
 if hashlib.sha256(out.read_bytes()).hexdigest()!=previous['wrapper_sha256']:
  raise RuntimeError('Subsystem edited since last generation; preserve and review changes first')
a=soc.read_text(encoding='utf-8');header=a[a.index('module SapphireSoc'):];header=header[:header.index(');')]
ports=re.findall(r'\b(input|output)\s+(?:wire\s+)?(\[[^\]]+\]\s*)?(\w+)\s*[,\n]',header+'\n')
assert len(ports)>70
fixed={'io_systemClk':'clk_96','io_peripheralClk':'clk_96','io_memoryClk':'clk_96',
'io_asyncReset':'ai_reset','io_systemReset':'system_reset','io_memoryReset':'memory_reset','io_peripheralReset':'peripheral_reset',
'userInterruptA':'custom_irq','userInterruptB':"1'b0"}
custom={'cmd_valid':'custom_cmd_valid','cmd_ready':'custom_cmd_ready','function_id':'custom_function',
'inputs_0':'custom_input0','inputs_1':'custom_input1','rsp_valid':'custom_rsp_valid',
'rsp_ready':'custom_rsp_ready','outputs_0':'custom_output'}
for k,v in custom.items():fixed['cpu0_customInstruction_'+k]=v
apb={'PADDR':'PADDR','PSEL':'PSEL','PENABLE':'PENABLE','PWRITE':'PWRITE','PWDATA':'PWDATA','PRDATA':'PRDATA','PREADY':'PREADY','PSLVERROR':'PSLVERROR'}
for k,v in apb.items():fixed['io_apbSlave_1_'+k]=v
public=['input wire clk_96, ai_reset, ai_online','input wire uart_clk,uart_rst_n',
'input wire [1:0] requested','output wire [1:0] applied','output wire available,inference_enable',
'output wire system_reset,memory_reset,peripheral_reset',
'input wire pixel_clk,pixel_rst_n','input wire [23:0] rgb_i','input wire hs_i,vs_i,de_i',
'output wire [23:0] rgb_o','output wire hs_o,vs_o,de_o','output wire [31:0] displayed_source_frame']
connections=[]
for direction,width,name in ports:
 if name not in fixed:
  if name.startswith('io_ddrA_'): mapped='cpu_'+name[len('io_ddrA_'):]
  elif name.startswith(('jtagCtrl_','system_spi_0_','system_uart_0_')):mapped=name
  else:raise ValueError('Unreviewed generated port '+name)
  fixed[name]=mapped;public.append(direction+' wire '+(width or '')+mapped)
 connections.append('        .'+name+'('+fixed[name]+')')
definitions=(tiny.parent/'tinyml_defines.v').read_text(encoding='utf-8')
assert re.findall(r'^`define NUM_TINYML_CHANNEL_(\d)',definitions,re.M)==['1']
t=tiny.read_text(encoding='utf-8');t=t[t.index('module tinyml_accelerator_channels'):];t=t[:t.index(');')]
axip=re.findall(r'\b(input|output)\s+(?:wire\s+)?(\[[^\]]+\]\s*)?(m_axi_\w+)\s*[,\n]',t+'\n')
assert len(axip)==35,len(axip)
tc=[]
for direction,width,name in axip:
 if name=='m_axi_clk':mapped='clk_96'
 elif name=='m_axi_rstn':mapped='!system_reset'
 else:
  mapped='tiny_'+name[6:];width=(width or '').replace('AXI_DW_M/8-1','15').replace('AXI_DW_M-1','127')
  public.append(direction+' wire '+width+mapped)
 tc.append('        .'+name+'('+mapped+')')
text='''// Integration derived from official Ti60F225 YOLO EVSoC Sapphire/custom-instruction wiring.
// Vendor implementations are unmodified in ignored artifacts; source hashes recorded there.
// CPU, peripheral, and memory ports use the same verified 96 MHz clock.
// Memory addresses are LOGICAL: both exported buses still need checked translation/arbitration.
module cnn_soc_subsystem #(parameter IMAGE_WIDTH=1280, IMAGE_HEIGHT=720)(
    '''+',\n    '.join(public)+'''
);
    wire custom_cmd_valid,custom_cmd_ready,custom_irq,custom_rsp_valid,custom_rsp_ready;
    wire [9:0] custom_function;
    wire [31:0] custom_input0,custom_input1,custom_output;
    wire [15:0] PADDR;
    wire PSEL,PENABLE,PWRITE,PREADY,PSLVERROR;
    wire [31:0] PWDATA,PRDATA;
    SapphireSoc u_risc_v(
'''+',\n'.join(connections)+'''
    );
    tinyml_accelerator_channels #(.AXI_DW_M(128)) u_tinyml_top_channels(
        .clk(clk_96),.reset(system_reset),
        .cmd_valid(custom_cmd_valid),.cmd_ready(custom_cmd_ready),.cmd_int(custom_irq),
        .cmd_function_id(custom_function),.cmd_inputs_0(custom_input0),.cmd_inputs_1(custom_input1),
        .rsp_valid(custom_rsp_valid),.rsp_ready(custom_rsp_ready),.rsp_outputs_0(custom_output),
'''+',\n'.join(tc)+'''
    );
    cnn_video_endpoint #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),.REQUIRE_FIRMWARE_READY(1)) u_video_endpoint(
        .uart_clk(uart_clk),.uart_rst_n(uart_rst_n),.requested(requested),.applied(applied),.available(available),
        .cpu_clk(clk_96),.cpu_rst_n(!peripheral_reset),.ai_online(ai_online && !system_reset),.inference_enable(inference_enable),
        .PADDR(PADDR),.PSEL(PSEL),.PENABLE(PENABLE),.PWRITE(PWRITE),.PWDATA(PWDATA),
        .PRDATA(PRDATA),.PREADY(PREADY),.PSLVERROR(PSLVERROR),
        .pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),.rgb_i(rgb_i),.hs_i(hs_i),.vs_i(vs_i),.de_i(de_i),
        .rgb_o(rgb_o),.hs_o(hs_o),.vs_o(vs_o),.de_o(de_o),.displayed_source_frame(displayed_source_frame));
endmodule
'''
out.write_text(text,encoding='utf-8')
report={'source_soc':str(soc),'soc_sha256':hashlib.sha256(soc.read_bytes()).hexdigest(),
'source_tinyml':str(tiny),'tinyml_sha256':hashlib.sha256(tiny.read_bytes()).hexdigest(),
'generated_soc_ports':len(ports),'accelerator_axi_ports':len(axip),'connections':fixed,
'wrapper_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'top_integrated':False,'hardware_verified':False}
report_path.write_text(json.dumps(report,indent=2)+'\n')
print('Generated',len(ports),'SoC port connections and',len(axip),'accelerator bus connections')

