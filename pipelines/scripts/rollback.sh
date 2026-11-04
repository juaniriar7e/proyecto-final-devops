#!/usr/bin/env bash
# Revierte los servicios a las revisiones guardadas por deploy.sh en STATE_FILE.
# Si la revisión previa usa la imagen ":bootstrap" (primer despliegue), no vuelve a ella:
# deja el servicio con desired-count 0.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd aws
require_vars AWS_REGION PROJECT_PREFIX
STATE_FILE="${STATE_FILE:-$(default_state_file)}"
CLUSTER="${PROJECT_PREFIX}-cluster"
export AWS_DEFAULT_REGION="$AWS_REGION"

if [[ ! -s "$STATE_FILE" ]]; then
  warn "No hay revisiones previas guardadas en $STATE_FILE: no hay nada que revertir."
  exit 0
fi

log "Iniciando rollback..."
services=()
while IFS=$'\t' read -r svc prev_arn prev_image; do
  [[ -n "$svc" ]] || continue
  service="${PROJECT_PREFIX}-${svc}"
  if [[ "$prev_image" == *:bootstrap ]]; then
    log "$service: la revisión previa usa la imagen bootstrap (primer despliegue); se deja con desired-count 0."
    aws ecs update-service --cluster "$CLUSTER" --service "$service" --desired-count 0 --output json >/dev/null \
      || die "Falló el rollback de $service (desired-count 0)."
  else
    log "$service: volviendo a $prev_arn"
    aws ecs update-service --cluster "$CLUSTER" --service "$service" --task-definition "$prev_arn" --output json >/dev/null \
      || die "Falló el rollback de $service a $prev_arn."
  fi
  services+=("$service")
done <"$STATE_FILE"

log "Esperando a que los servicios reviertan y se estabilicen..."
aws ecs wait services-stable --cluster "$CLUSTER" --services "${services[@]}" \
  || die "Los servicios no se estabilizaron tras el rollback."
log "Rollback completado."
summary "### Rollback ejecutado en \`$CLUSTER\`"
