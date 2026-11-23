@echo off
rem ============================================================================
rem Bandit Bash
rem Copyright (c) 2026 Derc Development
rem Licensed under the MIT License. See LICENSE.
rem
rem File:     run_enet_pair.cmd
rem Author:
rem Created:  November 23, 2026
rem Modified: November 23, 2026
rem ============================================================================
rem Double-click to open two windows of the game, a host and a joiner, for trying co-op over the
rem ENet dev transport on this machine, each with its own throwaway user folder. Runs
rem tools/run_enet_pair.sh through Git Bash with any arguments given (a port, as for the script),
rem then waits for a key so the folders' and logs' paths stay on screen. The script's header
rem says what to do in the windows.
rem Git Bash is found from Git for Windows' InstallPath in the registry, then in
rem %ProgramFiles%\Git, then in %LOCALAPPDATA%\Programs\Git. A bare bash on PATH is never used: on
rem Windows it can be WSL's. No labels or goto, so the file runs the same with LF line endings.
setlocal

set "GIT_ROOT="
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\GitForWindows" /v InstallPath 2^>nul ^| find "InstallPath"') do set "GIT_ROOT=%%B"
if not defined GIT_ROOT for /f "tokens=2,*" %%A in ('reg query "HKCU\SOFTWARE\GitForWindows" /v InstallPath 2^>nul ^| find "InstallPath"') do set "GIT_ROOT=%%B"
if defined GIT_ROOT if not exist "%GIT_ROOT%\bin\bash.exe" set "GIT_ROOT="
if not defined GIT_ROOT if exist "%ProgramFiles%\Git\bin\bash.exe" set "GIT_ROOT=%ProgramFiles%\Git"
if not defined GIT_ROOT if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "GIT_ROOT=%LOCALAPPDATA%\Programs\Git"

if not defined GIT_ROOT (
	echo Git Bash not found: install Git for Windows, or run tools/run_enet_pair.sh from a Git Bash shell.
	pause
	exit /b 2
)

rem Forward slashes, so the script's dirname finds the tools folder.
set "SCRIPT=%~dp0run_enet_pair.sh"
set "SCRIPT=%SCRIPT:\=/%"
"%GIT_ROOT%\bin\bash.exe" "%SCRIPT%" %*
set "CODE=%ERRORLEVEL%"
echo.
pause
exit /b %CODE%
