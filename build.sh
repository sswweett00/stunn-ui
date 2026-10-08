#!/usr/bin/env bash
# stunn_ui bağımsız derleme: kütüphane denetimi + standalone demo.
# Sistemde libglfw yoksa: apt install libglfw3-dev  (veya GLFW_LIB_DIR ile -L dizini ver)
set -euo pipefail
cd "$(dirname "$0")"
source ../glfw_flags.sh
mkdir -p build
COL="-collection:vmath=../vmath"
odin check src -no-entry-point -vet -strict-style $COL
odin test src -vet -strict-style $COL -out:build/stunn_test
odin check backend_gl -no-entry-point -vet -strict-style $COL
odin build examples -vet -strict-style $COL -out:build/standalone_demo "${GLFW_EXTRA[@]}"
echo "OK: build/standalone_demo"