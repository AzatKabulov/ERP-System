@echo off
rem Windows: double-click this file. (First time, Windows may say "protected your PC": More info > Run anyway.)
cd /d "%~dp0"
tools\win\uv.exe run --project backend --with pixeltable-pgserver==0.6.0 python scripts\local\run_local.py --web app\erp-system-test-web.zip --apk app\erp-system-test-debug.apk %*
pause
