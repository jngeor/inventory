#!/usr/bin/env bash
# Valida los commits de un rango con el formato de conventions.md 4:
#
#   tipo(alcance): KOAL-N descripción
#
# Uso: check-commits.sh <base> <head>
# Si PR_TITLE está definida, valida también el título del PR (conventions.md 5).
# Los merge commits se ignoran.
set -euo pipefail
export LC_ALL=C.UTF-8

base=${1:?falta el commit base}
head=${2:?falta el commit head}

types='feat|fix|docs|test|refactor|build|chore'
scopes='catalog|inventory|orders|notifications|gateway|e2e|deploy'
pattern="^($types)(\(($scopes)\))?: KOAL-[0-9]+ [[:lower:][:digit:]\`].*[^.[:space:]]$"
max_subject=71
max_body=72

errors=0

fail() {
  echo "::error::$1"
  errors=$((errors + 1))
}

check_subject() {
  local origin=$1 subject=$2
  if ! [[ $subject =~ $pattern ]]; then
    fail "$origin: '$subject' no sigue 'tipo(alcance): KOAL-N descripción' en minúscula y sin punto final"
  fi
  if (( ${#subject} > max_subject )); then
    fail "$origin: el título tiene ${#subject} caracteres; el máximo es $max_subject"
  fi
}

commits=$(git rev-list --no-merges --reverse "$base..$head")
if [[ -z $commits ]]; then
  fail "el PR no tiene commits propios"
fi

for sha in $commits; do
  short=${sha:0:7}
  subject=$(git log -1 --format=%s "$sha")
  check_subject "commit $short" "$subject"

  # Cuerpo: línea en blanco tras el título y líneas de hasta 72 caracteres.
  # Las líneas con una URL se aceptan aunque sean más largas.
  mapfile -t lines < <(git log -1 --format=%B "$sha")
  if (( ${#lines[@]} > 1 )) && [[ -n ${lines[1]} ]]; then
    fail "commit $short: falta la línea en blanco entre el título y el cuerpo"
  fi
  for line in "${lines[@]:1}"; do
    if (( ${#line} > max_body )) && [[ $line != *://* ]]; then
      fail "commit $short: una línea del cuerpo tiene ${#line} caracteres; el máximo es $max_body"
    fi
  done
done

if [[ -n ${PR_TITLE:-} ]]; then
  check_subject "título del PR" "$PR_TITLE"
fi

if (( errors > 0 )); then
  echo "$errors error(es). Formato en docs/conventions.md 4."
  exit 1
fi
echo "Commits y título con el formato correcto."
