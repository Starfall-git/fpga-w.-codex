"""Connect real SoC wrapper, official-derived AXI adapter and shared DDR.
Syntax compilation is not vendor-IP elaboration or board validation.
"""
from pathlib import Path
import re
r=Path(__file__).resolve().parents[1]
def ports(text):
 header=text[text.index(')(\n')+3:text.index('\n);')] if ')(\n' in text else text[text.index('(\n')+2:text.index('\n);')]
 result=[]
 for field in header.split(','):
  field=field.strip()
  m=re.match(r'(input|output)\s+wire\s*(\[[^\]]+\])?\s*(\w+)\s*$',field)
  if m: direction,width,name=m.groups();width=width or ''
  else:
   assert re.fullmatch(r'\w+',field),field
   name=field
  result.append((direction,width,name))
 return result
soc=ports((r/'src/cnn/cnn_soc_subsystem.v').read_text(encoding='utf-8'))
fabric=ports((r/'src/cnn/cnn_shared_ddr.v').read_text(encoding='utf-8'))
public=[p for p in soc if not p[2].startswith(('cpu_','tiny_'))]
public += [('input','','fabric_rst_n'),('output','[1:0]','ai_quiescent')]
widths={'avalid':1,'aready':1,'addr':32,'id':8,'len':8,'size':3,'burst':2,'write':1,'lock':1,'wvalid':1,'wready':1,'wdata':128,'wstrb':16,'wlast':1,'bvalid':1,'bready':1,'bid':8,'bresp':2,'rvalid':1,'rready':1,'rdata':128,'rid':8,'rresp':2,'rlast':1}
fmap={n:(d,w) for d,w,n in fabric}
for k,v in widths.items():public.append((fmap['s_'+k][0],'' if v==1 else f'[{v-1}:0]','video_'+k))
public += [p for p in fabric if p[2].startswith('m_') or p[2]=='idle_o']
lines=['// Real Sapphire/TinyML instance -> isolated shared DDR; all memory ports at clk_96.',
'// fabric_rst_n is GLOBAL; ai_reset may assert independently. Parent must wait',
'// for ai_quiescent before releasing a restarted CPU. No camera DMA is added here.',
'module cnn_evsoc_memory #(parameter IMAGE_WIDTH=1280,IMAGE_HEIGHT=720)(',
',\n'.join(d+' wire '+w+' '+n for d,w,n in public),');']
for _,w,n in soc:
 if n.startswith(('cpu_','tiny_')):lines.append('wire '+w+' '+n+';')
for k,v in widths.items():
 lines.append('wire '+('' if v==1 else f'[{v-1}:0]')+' accel_'+k+';')
 lines.append(f'wire [{v*3-1}:0] bus_{k};')
lines+=['wire [1:0] accel_lock_full;', 'wire [7:0] unused_wid,unused_bid,unused_rid;',
'cnn_soc_subsystem #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) soc(\n'+',\n'.join('.'+n+'('+n+')' for _,_,n in soc)+'\n);']
a=(r/'src/cnn/cnn_axi_full_to_half_duplex.v').read_text(encoding='utf-8');ah=a[a.index(')(\n')+3:a.index('\n);')]
ap=re.findall(r'^\s*(input|output)\s*(\[[^\]]+\])?\s*(\w+)\s*[,\n]',ah+'\n',re.M)
half={'arw_valid':'avalid','arw_ready':'aready','arw_payload_addr':'addr','arw_payload_id':'id','arw_payload_len':'len','arw_payload_size':'size','arw_payload_burst':'burst','arw_payload_write':'write','w_valid':'wvalid','w_ready':'wready','w_payload_data':'wdata','w_payload_strb':'wstrb','w_payload_last':'wlast','b_valid':'bvalid','b_ready':'bready','b_payload_id':'bid','b_payload_resp':'bresp','r_valid':'rvalid','r_ready':'rready','r_payload_data':'rdata','r_payload_id':'rid','r_payload_resp':'rresp','r_payload_last':'rlast'}
con=[]
for _,_,n in ap:
 if n=='clk':v='clk_96'
 elif n=='rst':v='ai_reset | system_reset'
 elif n=='io_ddr_arw_payload_lock':v='accel_lock_full'
 elif n=='io_ddr_w_payload_id':v='unused_wid'
 elif n.startswith('io_ddr_'):v='accel_'+half[n[7:]]
 elif n.startswith('s_axi_'):
  k=n[6:]
  if k in ('awqos','awregion','arqos','arregion'):v="4'b0"
  elif k in ('bid','rid'):v='unused_'+k
  else:v='tiny_'+k
 else:raise ValueError(n)
 con.append('.'+n+'('+v+')')
lines+=['cnn_axi_full_to_half_duplex #(.DATA_WIDTH(128)) accelerator_adapter(\n'+',\n'.join(con)+'\n);','assign accel_lock=|accel_lock_full;']
cpu={'avalid':'arw_valid','aready':'arw_ready','addr':'arw_payload_addr','id':'arw_payload_id','len':'arw_payload_len','size':'arw_payload_size','burst':'arw_payload_burst','write':'arw_payload_write','lock':'arw_payload_lock','wvalid':'w_valid','wready':'w_ready','wdata':'w_payload_data','wstrb':'w_payload_strb','wlast':'w_payload_last','bvalid':'b_valid','bready':'b_ready','bid':'b_payload_id','bresp':'b_payload_resp','rvalid':'r_valid','rready':'r_ready','rdata':'r_payload_data','rid':'r_payload_id','rresp':'r_payload_resp','rlast':'r_payload_last'}
for k in widths:
 sources='{accel_'+k+',cpu_'+cpu[k]+',video_'+k+'}'
 if fmap['s_'+k][0]=='input':lines.append('assign bus_'+k+'='+sources+';')
 else:lines.append('assign '+sources+'=bus_'+k+';')
fc=[]
for _,_,n in fabric:
 if n=='clk':v='clk_96'
 elif n=='rst_n':v='fabric_rst_n'
 elif n=='ai_abort':v='{2{ai_reset | system_reset | memory_reset | peripheral_reset}}'
 elif n.startswith('s_'):v='bus_'+n[2:]
 else:v=n
 fc.append('.'+n+'('+v+')')
lines+=['cnn_shared_ddr memory_fabric(\n'+',\n'.join(fc)+'\n);','endmodule','']
(r/'src/cnn/cnn_evsoc_memory.v').write_text('\n'.join(lines),encoding='utf-8')
print('Generated real SoC/memory wrapper:',len(soc),'SoC ports;',len(public),'external ports')
