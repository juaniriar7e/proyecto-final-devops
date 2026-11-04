#!/usr/bin/env bash
# Prueba de humo contra el ALB. Uso: smoke-test.sh <url> <version>
# Reintenta mientras el ALB propaga los targets (SMOKE_RETRIES=30, SMOKE_DELAY=10 s).
# Las tareas creadas se borran siempre (trap), incluso si algo falla.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd curl jq
[[ $# -eq 2 ]] || die "Uso: smoke-test.sh <url> <version>"
URL="${1%/}"; VERSION="$2"
RETRIES="${SMOKE_RETRIES:-30}"; DELAY="${SMOKE_DELAY:-10}"
TMP="$(mktemp -d)"
CREATED_ID=""

cleanup() {
  local rc=$?
  if [[ -n "$CREATED_ID" ]]; then
    if curl -sS --max-time 10 -o /dev/null -X DELETE "$URL/api/tasks/$CREATED_ID" 2>/dev/null; then
      log "Limpieza: tarea $CREATED_ID eliminada."
    else
      warn "No se pudo eliminar la tarea de prueba $CREATED_ID."
    fi
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap cleanup EXIT

# req METHOD PATH [JSON] -> imprime el código HTTP; el cuerpo queda en $TMP/body
req() {
  local path="$2" data="${3:-}" args=(-sS --max-time 10 -o "$TMP/body" -w '%{http_code}' -X "$1")
  [[ -n "$data" ]] && args+=(-H 'Content-Type: application/json' -d "$data")
  curl "${args[@]}" "$URL$path" 2>"$TMP/err" || { echo "000"; return 0; }
}

expect() { # expect "descripción" código_esperado METHOD PATH [JSON]
  local desc="$1" want="$2" got; shift 2
  got="$(req "$@")"
  [[ "$got" == "$want" ]] || { SMOKE_ERR="$desc: se esperaba HTTP $want y se recibió $got"; return 1; }
}

readiness_checks() {
  expect "GET /" 200 GET / || return 1
  expect "GET /api/health" 200 GET /api/health || return 1
  [[ "$(jq -r '.status // empty' "$TMP/body" 2>/dev/null)" == "ok" ]] || { SMOKE_ERR="/api/health no devolvió status=ok"; return 1; }
  expect "GET /api/version" 200 GET /api/version || return 1
  local got; got="$(jq -r '.version // empty' "$TMP/body" 2>/dev/null)"
  [[ "$got" == "$VERSION" ]] || { SMOKE_ERR="/api/version devuelve '$got', se esperaba '$VERSION'"; return 1; }
  expect "GET /version.json" 200 GET /version.json || return 1
  got="$(jq -r '.version // empty' "$TMP/body" 2>/dev/null)"
  [[ "$got" == "$VERSION" ]] || { SMOKE_ERR="/version.json devuelve '$got', se esperaba '$VERSION'"; return 1; }
}

SMOKE_ERR=""
log "Smoke test contra $URL (versión esperada: $VERSION)"
ok=0
for ((i = 1; i <= RETRIES; i++)); do
  if readiness_checks; then ok=1; break; fi
  log "Intento $i/$RETRIES: $SMOKE_ERR"
  ((i < RETRIES)) && sleep "$DELAY"
done
[[ $ok -eq 1 ]] || die "El smoke test falló tras $RETRIES intentos. Último error: $SMOKE_ERR"
log "Salud y versión correctas."

# CRUD completo; el trap elimina la tarea si algo falla a mitad.
title="smoke-$(date +%s)"
expect "POST /api/tasks" 201 POST /api/tasks "{\"title\":\"$title\"}" || die "$SMOKE_ERR"
CREATED_ID="$(jq -r '.id // empty' "$TMP/body")"
[[ -n "$CREATED_ID" ]] || die "POST /api/tasks no devolvió un id."
expect "GET /api/tasks" 200 GET /api/tasks || die "$SMOKE_ERR"
jq -e --arg id "$CREATED_ID" 'map(select(.id == $id)) | length == 1' "$TMP/body" >/dev/null \
  || die "La tarea creada ($CREATED_ID) no aparece en GET /api/tasks."
expect "PATCH /api/tasks/$CREATED_ID" 200 PATCH "/api/tasks/$CREATED_ID" '{"done":true}' || die "$SMOKE_ERR"
[[ "$(jq -r '.done' "$TMP/body")" == "true" ]] || die "PATCH no marcó la tarea como completada."
expect "DELETE /api/tasks/$CREATED_ID" 204 DELETE "/api/tasks/$CREATED_ID" || die "$SMOKE_ERR"
deleted="$CREATED_ID"; CREATED_ID=""
expect "GET /api/tasks (tras borrar)" 200 GET /api/tasks || die "$SMOKE_ERR"
jq -e --arg id "$deleted" 'map(select(.id == $id)) | length == 0' "$TMP/body" >/dev/null \
  || die "La tarea $deleted sigue existiendo tras DELETE."
log "Smoke test superado."
summary "### Smoke test superado en $URL (versión \`$VERSION\`)"
