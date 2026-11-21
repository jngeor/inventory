#!/usr/bin/env bash
# Lista, como arreglo JSON, los módulos Maven que hay que construir (ADR-0018).
#
# Uso: changed-modules.sh <base>
# Compara <base> con HEAD. Escribe en stdout, por ejemplo: ["catalog","orders"]
#
# * Sin pom.xml en la raíz no hay nada que construir: [].
# * Si cambió algo común (POM padre, wrapper, config/, este workflow),
#   se construyen todos los módulos.
# * Si no, solo los módulos con archivos cambiados. docs/ no construye nada.
#
# Un módulo es una carpeta de la raíz con pom.xml. e2e queda fuera: no se
# construye por módulo, sino con las imágenes del PR (testing.md 9).
set -euo pipefail

base=${1:?falta el commit base}

if [ ! -f pom.xml ]; then
  echo '[]'
  exit 0
fi

mapfile -t modules < <(
  for d in */; do
    d=${d%/}
    [ "$d" != e2e ] && [ -f "$d/pom.xml" ] && echo "$d"
  done
)

mapfile -t changed < <(git diff --name-only "$base" HEAD)

common='^(pom\.xml|mvnw(\.cmd)?|\.mvn/|config/|\.github/workflows/build\.yml|\.github/scripts/changed-modules\.sh)'

selected=()
if printf '%s\n' "${changed[@]}" | grep -Eq "$common"; then
  selected=("${modules[@]}")
else
  for m in "${modules[@]}"; do
    if printf '%s\n' "${changed[@]}" | grep -q "^$m/"; then
      selected+=("$m")
    fi
  done
fi

if [ ${#selected[@]} -eq 0 ]; then
  echo '[]'
  exit 0
fi

# Los nombres son carpetas simples (conventions.md 2): no hace falta escapar.
json=$(printf ',"%s"' "${selected[@]}")
echo "[${json:1}]"
