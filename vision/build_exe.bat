@echo off
echo ========================================
echo  Cipherbound Vision - EXE Builder
echo ========================================
echo.

REM Navigate to the vision directory
cd /d "%~dp0"

REM Activate the virtual environment
echo [1/3] Activating virtual environment...
call venv\Scripts\activate.bat
if errorlevel 1 (
    echo ERROR: Could not activate venv. Make sure it exists at .\venv
    echo Run: python -m venv venv ^&^& venv\Scripts\pip install -r requirements.txt
    pause
    exit /b 1
)

REM Install PyInstaller if not already installed
echo [2/3] Ensuring PyInstaller is installed...
pip show pyinstaller >nul 2>&1
if errorlevel 1 (
    echo Installing PyInstaller...
    pip install pyinstaller
    if errorlevel 1 (
        echo ERROR: Failed to install PyInstaller
        pause
        exit /b 1
    )
)

REM Build the exe
echo [3/3] Building executable...
echo This may take a few minutes on first run.
echo.
pyinstaller --clean cipherbound_vision.spec

if errorlevel 1 (
    echo.
    echo ========================================
    echo  BUILD FAILED
    echo ========================================
    echo Check the output above for errors.
    pause
    exit /b 1
)

echo.
echo ========================================
echo  BUILD SUCCESSFUL!
echo ========================================
echo.
echo Output location:
echo   dist\CipherboundVision\CipherboundVision.exe
echo.
echo To run:
echo   dist\CipherboundVision\CipherboundVision.exe
echo.
echo To distribute, zip the entire dist\CipherboundVision folder.
echo ========================================
pause
