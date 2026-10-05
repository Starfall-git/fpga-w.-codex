"""Copy the derived official gesture app onto the newly generated DDR3 BSP.
Never copies the old HyperRAM BSP or build outputs. No FPGA download.
"""
from pathlib import Path
import hashlib,json,shutil
R=Path(__file__).resolve().parents[1]
source=R/'artifacts/evsoc-gesture-r1/embedded_sw/SapphireSoc/software/standalone'
project=R/'artifacts/evsoc-system-r1'
target=project/'embedded_sw/SapphireSoc/software/standalone'
app=target/'evsoc_tinyml_gesture'
if app.exists():raise FileExistsError(app)
bsp=project/'embedded_sw/SapphireSoc/bsp/efinix/EfxSapphireSoc'
soc=(bsp/'include/soc.h').read_text(encoding='utf-8')
for text in ['#define SYSTEM_CLINT_HZ 96000000','#define IO_APB_SLAVE_1_INPUT 0xf8100000','#define SYSTEM_DDR_BMB 0x1000','#define SYSTEM_DDR_BMB_SIZE 0x4000000']:
    assert text in soc,text
shutil.copytree(source/'evsoc_tinyml_gesture',app,ignore=shutil.ignore_patterns('build','Debug','Release','.metadata','*.o','*.elf','*.d'))
for name in ('tinyml_lib.a','tinyml_standalone.mk'):
    shutil.copy2(source/'common'/name,target/'common'/name)
shutil.copy2(R/'firmware/evsoc_gesture/gesture_result.h',app/'src/gesture_result.h')
report={'app':str(app),'mode':'static_accelerator_golden','bsp':'actual generated 96MHz DDR3 candidate',
        'source_main_sha256':hashlib.sha256((source/'evsoc_tinyml_gesture/src/main.cc').read_bytes()).hexdigest(),
        'soc_header_sha256':hashlib.sha256((bsp/'include/soc.h').read_bytes()).hexdigest(),
        'physical_ai_range':'0x04000000..0x08000000','firmware_ready_asserted':False,
        'note':'Static test does not enable live inference; requires matching integrated bitstream, not old video bitstream.'}
(project/'software_preparation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(app)
