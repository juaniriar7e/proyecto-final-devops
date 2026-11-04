#!/usr/bin/env bash
# Copia pipelines/workflows/*.yml a .github/workflows/ (GitHub solo lee esa ruta).
# Uso: sync-workflows.sh          -> copia
#      sync-workflows.sh --check  -> falla si las copias difieren o sobran/faltan
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/pipelines/workflows"
DST="$ROOT/.github/workflows"
MODE="${1:-}"

[[ -d "$SRC" ]] || die "No existe el directorio canónico $SRC."
shopt -s nullglob
files=("$SRC"/*.yml)
[[ ${#files[@]} -gt 0 ]] || die "No hay workflows en $SRC."

if [[ "$MODE" == "--check" ]]; then
  rc=0
  for f in "${files[@]}"; do
    name="$(basename "$f")"
    if [[ ! -f "$DST/$name" ]]; then
      warn "Falta la copia .github/workflows/$name."; rc=1
    elif ! cmp -s "$f" "$DST/$name"; then
      warn ".github/workflows/$name difiere de pipelines/workflows/$name."; rc=1
    fi
  done
  for f in "$DST"/*.yml; do
    [[ -f "$SRC/$(basename "$f")" ]] || { warn "Sobra .github/workflows/$(basename "$f") (sin fuente canónica)."; rc=1; }
  done
  if [[ $rc -ne 0 ]]; then die "Workflows desincronizados. Ejecuta pipelines/scripts/sync-workflows.sh."; fi
  log "Workflows sincronizados (${#files[@]} archivos)."
elif [[ -z "$MODE" ]]; then
  mkdir -p "$DST"
  for f in "${files[@]}"; do
    cp "$f" "$DST/$(basename "$f")"
    log "Copiado $(basename "$f") -> .github/workflows/"
  done
else
  die "Argumento desconocido '$MODE'. Uso: sync-workflows.sh [--check]"
fi
