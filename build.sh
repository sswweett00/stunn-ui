#!/usr/bin/env bash
# stunn-ui bağımsız derleme: kütüphane denetimi + test + standalone demo.
#
# Gereksinimler:
#   - odin (PATH'te)
#   - vmath kardeş dizinde (../vmath)  — gizmo ve testler için
#   - GLFW (demo için): apt install libglfw3-dev   veya GLFW_LIB_DIR ile -L dizini
#
set -euo pipefail
cd "$(dirname "$0")"

COL=""
if [[ -d ../vmath ]]; then
  COL="-collection:vmath=../vmath"
else
  echo "Uyarı: ../vmath bulunamadı — gizmo testleri atlanacak, yalnızca çekirdek kontrol edilecek."
fi

# İsteğe bağlı glfw_flags.sh (monorepo kurulumu)
if [[ -f ../glfw_flags.sh ]]; then
  # shellcheck source=/dev/null
  source ../glfw_flags.sh
else
  GLFW_EXTRA=()
  # Sistem GLFW'ini dene
  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists glfw3; then
    GLFW_EXTRA+=($(pkg-config --libs glfw3))
  fi
fi

mkdir -p build

echo "==> odin check src"
odin check src -no-entry-point -vet -strict-style $COL

echo "==> odin check backend_sw"
odin check backend_sw -no-entry-point -vet -strict-style $COL

if [[ -n "$COL" ]]; then
  echo "==> odin check gizmo + test"
  odin check gizmo -no-entry-point -vet -strict-style $COL
  echo "==> odin test gizmo"
  odin test gizmo -vet -strict-style $COL -out:build/stunn_test
fi

echo "==> odin check backend_gl"
odin check backend_gl -no-entry-point -vet -strict-style $COL

echo "==> odin build examples (standalone_demo)"
odin build examples -vet -strict-style $COL -out:build/standalone_demo "${GLFW_EXTRA[@]+"${GLFW_EXTRA[@]}"}"

echo "OK: build/standalone_demo"
