"""v1.3 / 12: Verify notebooks, model bytes, unified parameters and target package."""
from pathlib import Path
import os,json,re,hashlib
import nbformat
ROOT=Path(__file__).resolve().parents[1];os.chdir(ROOT)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
reports=[]
for p in sorted(Path('ml/tinyml/notebooks').glob('*.ipynb')):
    nb=nbformat.read(p,as_version=4);nbformat.validate(nb)
    errors=[o.get('ename') for c in nb.cells for o in c.get('outputs',[]) if o.output_type=='error']
    assert not errors,(p,errors)
    codes=[c for c in nb.cells if c.cell_type=='code']
    reports.append(dict(path=p.as_posix(),code_cells=len(codes),executed=sum(c.execution_count is not None for c in codes),errors=errors))
for folder,filename in [('classifier','gesture_classifier_int8'),('detector','hand_detector_int8'),('detector_conv','hand_detector_int8')]:
    base=Path('ml/tinyml/artifacts')/folder;model=base/(filename+'.tflite')
    contract=json.loads((base/'tflite_contract.json').read_text())
    assert sha(model)==contract['sha256'] and contract['full_int8'] and contract['vendor_analyzer_returncode']==0
    for mode in ['lite_p1','lite_p2','lite_p4']:
        p=base/'generator'/mode/(filename+'_model_data.cc')
        binary=bytes(int(x,16) for x in re.findall(r'0x([0-9a-fA-F]{2})',p.read_text()))
        assert binary==model.read_bytes(),p
shared=Path('ml/tinyml/artifacts/shared_generator/lite_p2')
profile=json.loads((shared/'profile.json').read_text())['parameters']
assert profile['FC_MODE']=='LITE' and profile['CONV_DEPTHW_MODE']=='LITE'
individual=[json.loads((Path('ml/tinyml/artifacts')/name/'generator/lite_p2/profile.json').read_text())['parameters'] for name in ['classifier','detector_conv']]
for key in ['FC_MAX_IN_NODE','FC_MAX_OUT_NODE','CONV_DEPTHW_STD_FILTER_FIFO_A','CONV_DEPTHW_STD_OUT_CH_FIFO_A','CONV_DEPTHW_STD_CNT_DTH']:
    assert profile[key]==max(p[key] for p in individual),(key,profile[key])
manifest=json.loads(Path('firmware/tinyml_gesture_v1_3/manifest.json').read_text())
for name,digest in manifest['files_sha256'].items():assert sha(Path('firmware/tinyml_gesture_v1_3')/name)==digest,name
files={}
for directory in ['ml/tinyml','firmware/tinyml_gesture_v1_3']:
    for p in Path(directory).rglob('*'):
        if not p.is_file() or any(x in p.parts for x in ['jupyter','__pycache__','keras']):continue
        if p.name=='audit.json':continue
        files[p.as_posix()]=sha(p)
summary=dict(version='v1.3',notebooks=reports,tflite_and_generated_cpp_bytes_match=True,
             shared_configuration_checked=True,firmware_manifest_checked=True,hardware_verified=False,
             source_and_artifact_sha256=files)
Path('ml/tinyml/artifacts/audit.json').write_text(json.dumps(summary,indent=2))
print(json.dumps({k:v for k,v in summary.items() if k!='source_and_artifact_sha256'},indent=2))
