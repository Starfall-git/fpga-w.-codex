"""Adapt only absent EVSoC peripherals for the generated DDR3 BSP.
Preserve the official TinyML initialization, runtime, PLIC A handler and license.
"""
from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[1];project=R/'artifacts/evsoc-system-r1'
app=project/'embedded_sw/SapphireSoc/software/standalone/evsoc_tinyml_gesture'
manifest=project/'software_preparation.json';report=json.loads(manifest.read_text(encoding='utf-8'))
p=app/'src/main.cc';s=p.read_text(encoding='utf-8')
if 'CNN_DDR3_PERIPHERALS' in s:raise RuntimeError('Already adapted; preserve current edits')
assert hashlib.sha256(p.read_bytes()).hexdigest()==report['source_main_sha256']
a=s.index('u32 buf(u32 i)');b=s.index('// Replacement for the YOLO demo',a)
s=s[:a]+'// CNN_DDR3_PERIPHERALS: original PiCam/DSI DMA is absent.\n#ifdef IO_APB_SLAVE_0_INPUT\n'+s[a:b]+'#endif\n\n'+s[b:]
s=s.replace('   bsp_init();','   bsp_init();\n   dma_init(); // Official PLIC/custom-instruction IRQ setup; DMA B gated below.',1)
p.write_text(s,encoding='utf-8')
p=app/'src/platform/interrupt/intc.c';s=p.read_text(encoding='utf-8')
a=s.index('       case SYSTEM_PLIC_USER_INTERRUPT_B_INTERRUPT');b=s.index('       case SYSTEM_PLIC_USER_INTERRUPT_A_INTERRUPT',a)
s=s[:a]+'#ifdef IO_APB_SLAVE_0_INPUT\n'+s[a:b]+'#endif\n'+s[b:]
a=s.index('   plic_set_enable(BSP_PLIC, BSP_PLIC_CPU_0, SYSTEM_PLIC_USER_INTERRUPT_B_INTERRUPT');b=s.index('   \n',s.index('plic_set_priority(BSP_PLIC, SYSTEM_PLIC_USER_INTERRUPT_B_INTERRUPT',a))
s=s[:a]+'#ifdef IO_APB_SLAVE_0_INPUT\n'+s[a:b]+'#endif\n'+s[b:]
p.write_text(s,encoding='utf-8')
report['adapted_files']={str(p.relative_to(app)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [app/'src/main.cc',app/'src/platform/interrupt/intc.c']}
report['plic_accelerator_interrupt_initialized']=True
manifest.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('Adapted original camera-only functions and PLIC B for BSP without APB0; enabled official PLIC A setup')
