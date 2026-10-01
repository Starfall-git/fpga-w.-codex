"""v1.3 / 4: Invoke unmodified vendor generator methods without an interactive UI.

Run with Efinity's bundled Python (PyQt6). Produces comparison profiles, not
automatically installed FPGA settings. Source TinyML demos remain untouched.
"""
import os,sys,json,argparse,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('model',type=Path);ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
model=a.model.resolve();out=a.out.resolve()
assert model.is_relative_to(ROOT) and out.is_relative_to(ROOT)
os.environ['QT_QPA_PLATFORM']='offscreen'
vendor=ROOT/'tinyml-main/tools/tinyml_generator';sys.path.insert(0,str(vendor));os.chdir(vendor)
import tinyml_generator as generator
generator.app=generator.QApplication([])
w=generator.Widget()
generator.p2['CONV_DEPTHW_STD_IN_PARALLEL']['qval'].setValue(4)
generator.p2['CONV_DEPTHW_STD_OUT_PARALLEL']['qval'].setValue(4)
w.model_file=str(model);w.parse_model()
has_fc=generator.p2['FC_MODE']['val']!='DISABLE'
reports=[]
for parallel in (1,2,4):
    for key,val in {'AXI_DW':'128','CONV_DEPTHW_MODE':'LITE','CONV_DEPTHW_LITE_PARALLEL':parallel,
                    'FC_MODE':'LITE' if has_fc else 'DISABLE','ADD_MODE':'DISABLE','MUL_MODE':'DISABLE',
                    'MIN_MAX_MODE':'DISABLE','TINYML_CACHE':'DISABLE'}.items():generator.p2[key]['val']=val
    dest=out/f'lite_p{parallel}';dest.mkdir(parents=True,exist_ok=True)
    w.op_path=str(dest);w.dump_params(generator.params);w.dump_model();w.res_utilization()
    rows=[[w.res_model.item(r,c).text() for c in range(6)] for r in range(w.res_model.rowCount())]
    report=dict(version='v1.3',model_sha256=hashlib.sha256(model.read_bytes()).hexdigest(),parallel=parallel,
                parameters={k:v['val'] for k,v in generator.p2.items()},
                columns=['module','LUT','FF','ADD','RAM10','DSP'],accelerator_only_estimate=rows,
                synthesized=False,installed_in_top_level=False)
    (dest/'profile.json').write_text(json.dumps(report,indent=2));reports.append(report)
(out/'profiles.json').write_text(json.dumps(reports,indent=2))
print(json.dumps([dict(parallel=r['parallel'],estimate=r['accelerator_only_estimate'][-1]) for r in reports],indent=2))
