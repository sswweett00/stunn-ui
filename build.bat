@echo off
cd /d "%~dp0"
if not exist build mkdir build
odin check src -no-entry-point -vet -strict-style -collection:vmath=../vmath || exit /b 1
odin check backend_gl -no-entry-point -vet -strict-style -collection:vmath=../vmath || exit /b 1
odin build examples -vet -strict-style -collection:vmath=../vmath -out:build\standalone_demo.exe
