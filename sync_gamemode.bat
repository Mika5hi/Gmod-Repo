@echo off
setlocal
rem (DEV) Green Flu: Reimagined - copy the gamemode from this repo into garrysmod\gamemodes\greenflu
rem Garry's Mod only finds gamemodes in garrysmod\gamemodes (not in a loose addons folder, not through a link), so
rem after every pull, run this. It expects the repo to be garrysmod\addons\greenflu.

set "SRC=%~dp0gamemodes\greenflu"
set "GAMEMODES=%~dp0..\..\gamemodes"
set "DEST=%GAMEMODES%\greenflu"

if not exist "%SRC%\greenflu.txt" (
	echo Can't find the gamemode in this repo: "%SRC%"
	goto :end
)
if not exist "%GAMEMODES%" (
	echo Can't find garrysmod\gamemodes next to this repo. The repo should be in garrysmod\addons\greenflu.
	goto :end
)
rem A link (junction) left in gamemodes\greenflu would point back into this repo: copying into it would wipe it. Stop.
dir /AL /B "%GAMEMODES%" 2>nul | findstr /I /X "greenflu" >nul
if not errorlevel 1 (
	echo garrysmod\gamemodes\greenflu is a link. Remove it first, in Command Prompt:
	echo     rmdir "%DEST%"
	echo then run this again.
	goto :end
)

robocopy "%SRC%" "%DEST%" /MIR /R:1 /W:1 /NJH /NJS /NDL /NP
if errorlevel 8 (
	echo.
	echo Copy FAILED. Is Garry's Mod holding a file open? Close it and run this again.
) else (
	echo.
	echo Done: the gamemode in garrysmod\gamemodes\greenflu matches the repo. Restart the map in Garry's Mod.
)

:end
echo.
pause
