@echo off
setlocal
CLS

::  Set working directory
SET WD=%~dp0
::  Strip the trailing backslash
SET WD=%WD:~0,-1%
::  Set to TRUE or FALSE (for troubleshooting)
SET DEV=False
::  Set DeploymentType
SET DEPLOYMENT_TYPE=Repair



REM use the below if there are spaces in %WD% path

:: Use the below for troubleshooting
IF /i "%DEV%"=="TRUE" (
	CALL :color 2 "====================================================================" $
	CALL :color 2 "== DEV MODE - Will keep window open to view errors and/or results ==" $
	CALL :color 2 "====================================================================" $
	CALL :color
	ECHO.
	
	START "" /B /WAIT Powershell.exe -ExecutionPolicy Bypass -Command " & '%WD%\Invoke-AppDeployToolkit.ps1' -DeploymentType '%DEPLOYMENT_TYPE%' "
	
	ECHO.
	CALL :color 2 "====================================================================" $
	CALL :color 2 "== FINISHED - Press ANY key to EXIT . . .                         ==" $
	CALL :color 2 "====================================================================" $
	CALL :color
	ECHO.
	pause >nul & Exit
) ELSE (
	START Powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -Command " & '%WD%\Invoke-AppDeployToolkit.ps1' -DeploymentType '%DEPLOYMENT_TYPE%' "
)

goto :eof




:: Displays a text without new line at the end (unlike echo)
:echo
@<nul set /p ="%*"
@goto :eof

:: Change color to the first parameter (same codes as for the color command) 
:: And display the other parameters (write $ at the end for new line)
:color
@echo off
IF [%ESC%] == [] for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
SET color=0%1
IF [%color%] == [0] SET color=07
SET fore=%color:~-1%
SET back=%color:~-2,1% 
SET color=%ESC%[
if %fore% LEQ 7 (
  if %fore% == 0 SET color=%ESC%[30
  if %fore% == 1 SET color=%ESC%[34
  if %fore% == 2 SET color=%ESC%[32
  if %fore% == 3 SET color=%ESC%[36
  if %fore% == 4 SET color=%ESC%[31
  if %fore% == 5 SET color=%ESC%[35
  if %fore% == 6 SET color=%ESC%[33
  if %fore% == 7 SET color=%ESC%[37
) ELSE (
  if %fore% == 8 SET color=%ESC%[90
  if %fore% == 9  SET color=%ESC%[94
  if /i %fore% == a SET color=%ESC%[92
  if /i %fore% == b SET color=%ESC%[96
  if /i %fore% == c SET color=%ESC%[91
  if /i %fore% == d SET color=%ESC%[95
  if /i %fore% == e SET color=%ESC%[93
  if /i %fore% == f SET color=%ESC%[97
)
if %back% == 0 (SET color=%color%;40) ELSE (
  if %back% == 1 SET color=%color%;44
  if %back% == 2 SET color=%color%;42
  if %back% == 3 SET color=%color%;46
  if %back% == 4 SET color=%color%;41
  if %back% == 5 SET color=%color%;45
  if %back% == 6 SET color=%color%;43
  if %back% == 7 SET color=%color%;47
  if %back% == 8 SET color=%color%;100
  if %back% == 9  SET color=%color%;104
  if /i %back% == a SET color=%color%;102
  if /i %back% == b SET color=%color%;106
  if /i %back% == c SET color=%color%;101
  if /i %back% == d SET color=%color%;105
  if /i %back% == e SET color=%color%;103
  if /i %back% == f SET color=%color%;107
)
SET color=%color%m
:repeatcolor
if [%2] NEQ [$] SET color=%color%%~2
shift
if [%2] NEQ [] if [%2] NEQ [$] SET color=%color% & goto :repeatcolor
if [%2] EQU [$] (echo %color%) else (<nul set /p ="%color%")
goto :eof

:: Color map
:: == FORECOLORS ==
:: 70 "Black"
:: 1 "Blue"
:: 2 "Green"
:: 3 "Aqua"
:: 4 "Red"
:: 5 "Purple"
:: 6 "Yellow"
:: 7 "White"
:: 8 "Gray"
:: 9 "LightBlue"
:: a "LightGreen"
:: b "LightAqua"
:: c "LightRed"
:: d "LightPurple"
:: e "LightYellow"
:: f "BrightWhite"

:: == BACKCOLORS ==
:: 1f "Blue back"
:: 2f "Green back"
:: 3f "Aqua back"
:: 4f "Red back"
:: 5f "Purple back"
:: 6f "Yellow back"
:: 7f "White back"
:: 8f "Gray back"
:: 9f "LightBlue back"
:: a0 "LightGreen back"
:: b0 "LightAqua back"
:: c0 "LightRed back"
:: d0 "LightPurple back"
:: e0 "LightYellow back"
:: f0 "LightWhite back"
