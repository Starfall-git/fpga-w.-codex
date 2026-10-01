@echo off
rem v1.3 / 6: Use only the project TensorFlow kernel; preserve conda PyTorch.
cd /d "%~dp0..\.."
set "JUPYTER_DATA_DIR=%CD%\ml\tinyml\jupyter"
set "JUPYTER_CONFIG_DIR=%CD%\ml\tinyml\jupyter\config"
set "JUPYTER_RUNTIME_DIR=%CD%\ml\tinyml\jupyter\runtime"
set "IPYTHONDIR=%CD%\ml\tinyml\jupyter\ipython"
set "KERAS_HOME=%CD%\ml\tinyml\keras"
"%CD%\ml\.venv\Scripts\python.exe" -m notebook --ServerApp.root_dir="%CD%\ml\tinyml\notebooks" --ServerApp.ip=127.0.0.1
