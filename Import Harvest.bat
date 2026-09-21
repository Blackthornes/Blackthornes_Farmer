@echo off
rem Blackthornes Farmer -- double-click to pull your harvest out of WoW.
rem
rem This is the desktop-shortcut end of tools/harvest_import.py: it finds a
rem Python, makes sure lupa is there, runs the import, and then stays open so
rem you can read what it said. Run tools\make_shortcut.ps1 once to put it on
rem the desktop.
rem
rem Written with goto rather than parenthesised if-blocks on purpose: %errorlevel%
rem inside a block is expanded when the block is parsed, not when it runs, which
rem silently reads the wrong value. "if errorlevel 1" has no such trap.

setlocal
title Blackthornes Farmer - import harvest

rem Run from this file's own folder, whatever the shortcut's "Start in" says.
cd /d "%~dp0"

echo.
echo  Blackthornes Farmer -- importing your harvest
echo  ---------------------------------------------
echo.

rem -- Find a Python -----------------------------------------------------------

set "PY="

where py >nul 2>&1
if errorlevel 1 goto try_python
set "PY=py -3"
goto have_python

:try_python
where python >nul 2>&1
if errorlevel 1 goto try_python3
set "PY=python"
goto have_python

:try_python3
where python3 >nul 2>&1
if errorlevel 1 goto no_python
set "PY=python3"

:have_python

rem -- Make sure lupa is installed ---------------------------------------------

%PY% -c "import lupa" >nul 2>&1
if errorlevel 1 goto install_lupa
goto run_import

:install_lupa
echo  First run: installing the one package this needs (lupa).
echo.
%PY% -m pip install --user lupa
if errorlevel 1 goto lupa_failed
echo.

rem -- Do the thing ------------------------------------------------------------

:run_import
%PY% "tools\harvest_import.py" %*
if errorlevel 1 goto import_failed

echo.
echo  ---------------------------------------------
echo  Done. Open GitHub Desktop, then Commit and Push
echo  so the data is saved to the repository.
echo.
goto finish

rem -- Things that went wrong --------------------------------------------------

:no_python
echo  Could not find Python on this machine.
echo.
echo  Install it from https://www.python.org/downloads/ and tick
echo  "Add python.exe to PATH" on the first screen of the installer.
echo  Then double-click this again.
echo.
goto finish

:lupa_failed
echo.
echo  Could not install lupa. Try running this by hand to see why:
echo.
echo      %PY% -m pip install --user lupa
echo.
goto finish

:import_failed
echo.
echo  The import did not finish. What it printed above says why --
echo  send that text to Claude if it is not obvious.
echo.
goto finish

:finish
pause
endlocal
