@echo off
setlocal
cd /d "%~dp0"
if not exist build mkdir build

set COL=
if exist ..\vmath set COL=-collection:vmath=..\vmath

echo ==^> odin check src
odin check src -no-entry-point -vet -strict-style %COL% || exit /b 1

if defined COL (
  echo ==^> odin test src
  odin test src -vet -strict-style %COL% -out:build\stunn_test || exit /b 1
)

echo ==^> odin check backend_gl
odin check backend_gl -no-entry-point -vet -strict-style %COL% || exit /b 1

echo ==^> odin build examples
odin build examples -vet -strict-style %COL% -out:build\standalone_demo.exe || exit /b 1

echo OK: build\standalone_demo.exe
