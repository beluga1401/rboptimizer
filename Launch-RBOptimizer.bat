@echo off
title RB Optimizer PRO - Windows Gaming & Hardware Tuning
echo.
echo  ======================================================
echo   RB OPTIMIZER PRO - GAMING & HARDWARE TUNING
echo  ======================================================
echo   Launching with Administrator privileges...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RB_Optimizer.ps1" %*
if %errorlevel% NEQ 0 (
    echo.
    echo  Error launching script. Make sure PowerShell 5.1+ is installed.
    pause
)
