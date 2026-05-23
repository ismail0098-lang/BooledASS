@echo off
REM Z3 Build Script

echo Initializing MSVC x64 Environment...
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"

echo Prepending CMake path...
set "PATH=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;%PATH%"

set "CMAKE_ARGS="
if "%1"=="cpu" (
    echo CPU-only build requested. Disabling CUDA support...
    set "CMAKE_ARGS=-DZ3_GPU=OFF"
)

echo Checking for build directory...
if not exist "%~dp0build" (
    echo Creating build directory...
    mkdir "%~dp0build"
) else (
    echo Build directory already exists
)

echo Changing to build directory...
cd /d "%~dp0build"

echo Running CMake configuration...
cmake %CMAKE_ARGS% ..
if errorlevel 1 (
    echo CMake configuration failed!
    exit /b 1
)

echo Building Z3 with parallel 8...
cmake --build . --config Release --parallel 8
if errorlevel 1 (
    echo Build failed!
    exit /b 1
)

echo Build completed successfully!
exit /b 0
