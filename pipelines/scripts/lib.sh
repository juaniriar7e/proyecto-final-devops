#!/usr/bin/env bash
# Funciones comunes de los scripts de pipeline. Se carga con `source`; no se ejecuta solo.
# No imprime nunca credenciales ni variables de entorno completas.

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] AVISO: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# require_cmd cmd...: falla si falta alguna herramienta.
require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "Falta la herramienta requerida '$c' en el PATH."
  done
}

# require_vars VAR...: falla si alguna variable de entorno esta vacia o sin definir.
require_vars() {
  local v
  for v in "$@"; do
    [[ -n "${!v:-}" ]] || die "Falta la variable de entorno obligatoria '$v'."
  done
}

# Archivo donde deploy.sh guarda las revisiones previas para rollback.sh.
default_state_file() {
  printf '%s/previous-taskdefs.tsv' "${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
}

# Escribe en el resumen de GitHub Actions si existe; si no, no hace nada.
summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY"
  fi
}
