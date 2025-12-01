@echo off
REM Build script for Well.. Simple interpreter (Windows)
REM Compiles for Windows platform

echo Building wpm v2.0.0
echo ==============================
echo.

REM Create build directory
if not exist build mkdir build

echo Detected platform: Windows
echo.

REM Build for Windows
echo Restoring dependencies...
dart pub get
if %errorlevel% neq 0 (
    echo.
    echo X Failed to restore dependencies
    exit /b 1
)

echo Building executable...
dart compile exe wpm.dart -o build\wpm.exe

if %errorlevel% equ 0 (
    echo.
    echo ==============================
    echo + Build successful!
    echo.
    echo Executable: build\wpm.exe
    echo.
    echo To run:
    echo   build\wpm.exe install <package>
    echo   build\wpm.exe remove <package>
    echo   build\wpm.exe list
    echo.
    echo Note: Cross-compilation requires building on each platform.
    echo Run build.sh on Linux/macOS to build for those platforms.
) else (
    echo.
    echo X Build failed
    exit /b 1
)
