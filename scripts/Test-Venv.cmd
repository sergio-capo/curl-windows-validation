@echo off
setlocal
set "VENV_CHECK_DIR=%RUNNER_TEMP%\venv-cmd-%RANDOM%-%RANDOM%"
if exist "%VENV_CHECK_DIR%" exit /b 1
mkdir "%VENV_CHECK_DIR%"
cd /d "%VENV_CHECK_DIR%"
ver
py --version
if errorlevel 1 exit /b 1
py -m venv .venv
if errorlevel 1 exit /b 1
call .venv\Scripts\activate.bat
python -c "import sys; print(sys.executable); assert sys.prefix != sys.base_prefix"
if errorlevel 1 exit /b 1
python -m pip --version
if errorlevel 1 exit /b 1
python -m pip install requests
if errorlevel 1 exit /b 1
python -c "import requests; print(requests.__version__)"
if errorlevel 1 exit /b 1
python -m pip check
if errorlevel 1 exit /b 1
python -m pip freeze > requirements.txt
if errorlevel 1 exit /b 1
call deactivate
if defined VIRTUAL_ENV exit /b 1
.venv\Scripts\python.exe -c "import sys,requests; assert sys.prefix != sys.base_prefix; print(requests.__version__)"
if errorlevel 1 exit /b 1
py -m venv .venv-rebuild
if errorlevel 1 exit /b 1
call .venv-rebuild\Scripts\activate.bat
python -m pip install -r requirements.txt
if errorlevel 1 exit /b 1
python -m pip check
if errorlevel 1 exit /b 1
python -c "import requests; print(requests.__version__)"
if errorlevel 1 exit /b 1
call deactivate
if defined VIRTUAL_ENV exit /b 1
echo VALIDATION PASSED: cmd create/activate/install/deactivate/direct/freeze/rebuild
if defined GITHUB_STEP_SUMMARY echo Command Prompt: create, activate.bat, install, pip check, deactivate, direct execution, freeze and requirements rebuild PASS. >> "%GITHUB_STEP_SUMMARY%"
exit /b 0
