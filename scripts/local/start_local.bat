@echo off
rem Starts the whole system on this computer (see docs/LOCAL_TEST.md). Needs the tool "uv" (one-time install).
cd /d "%~dp0\..\.."
where uv >NUL 2>NUL
if errorlevel 1 (
  echo The tool "uv" is not installed. Open PowerShell and run:
  echo   powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 ^| iex"
  echo Then close PowerShell and double-click this file again.
  pause
  exit /b 1
)
uv run --project backend --with pixeltable-pgserver==0.6.0 python scripts/local/run_local.py %*
pause
