"""v1.3 / 3: Execute actual Jupyter cells with a project-local TensorFlow kernel."""
import os,argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
os.environ['JUPYTER_RUNTIME_DIR']=str(ROOT/'ml/tinyml/jupyter/runtime')
os.environ['JUPYTER_DATA_DIR']=str(ROOT/'ml/tinyml/jupyter')
os.environ['IPYTHONDIR']=str(ROOT/'ml/tinyml/jupyter/ipython')
os.environ['KERAS_HOME']=str(ROOT/'ml/tinyml/keras')
import nbformat
from nbclient import NotebookClient
from jupyter_client import KernelManager
from jupyter_client.kernelspec import KernelSpecManager
p=argparse.ArgumentParser();p.add_argument('notebook',type=Path);a=p.parse_args()
path=a.notebook.resolve();assert path.is_relative_to(ROOT)
nb=nbformat.read(path,as_version=4)
ksm=KernelSpecManager(kernel_dirs=[str(ROOT/'ml/tinyml/jupyter/kernels')])
km=KernelManager(kernel_name='cnn-tensorflow',kernel_spec_manager=ksm)
def started(cell,cell_index,**kw):print('CELL',cell_index,'START',flush=True)
def finished(cell,cell_index,**kw):
    nbformat.write(nb,path);print('CELL',cell_index,'FINISHED',flush=True)
client=NotebookClient(nb,km=km,timeout=7200,resources={'metadata':{'path':str(ROOT)}},
                      on_cell_start=started,on_cell_executed=finished)
try:client.execute()
finally:nbformat.write(nb,path)
print('NOTEBOOK COMPLETE',path,flush=True)
