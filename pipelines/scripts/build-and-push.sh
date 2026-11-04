#!/usr/bin/env bash
# Construye las imágenes de aplicacion/backend y aplicacion/frontend y las sube a ECR
# con la etiqueta sha-<7>. ECR es inmutable: si la etiqueta ya existe se omite el push.
# Variables: AWS_REGION, PROJECT_PREFIX, y GITHUB_SHA (o IMAGE_TAG para forzar la etiqueta).
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
require_cmd aws docker jq
require_vars AWS_REGION PROJECT_PREFIX

if [[ -z "${IMAGE_TAG:-}" ]]; then
  sha="${GITHUB_SHA:-$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)}"
  [[ -n "$sha" ]] || die "No se pudo determinar el commit: define GITHUB_SHA o IMAGE_TAG."
  IMAGE_TAG="sha-${sha:0:7}"
fi
[[ "$IMAGE_TAG" =~ ^[A-Za-z0-9_.-]{1,128}$ ]] || die "Etiqueta de imagen no válida: '$IMAGE_TAG'."

account="$(aws sts get-caller-identity --output json | jq -r '.Account')" \
  || die "No se pudo consultar la identidad de AWS (¿credenciales/OIDC configurados?)."
registry="${account}.dkr.ecr.${AWS_REGION}.amazonaws.com"
log "Etiqueta: $IMAGE_TAG | registro: $registry"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$registry" >/dev/null \
  || die "Falló el login en ECR."

summary "### Imágenes construidas (etiqueta \`$IMAGE_TAG\`)"
summary ""
summary "| Servicio | URI | Resultado | Hallazgos del escaneo |"
summary "|---|---|---|---|"

SCAN_MAX_INTENTOS="${SCAN_MAX_INTENTOS:-18}"
SCAN_ESPERA="${SCAN_ESPERA:-10}"

for svc in backend frontend; do
  repo="${PROJECT_PREFIX}-${svc}"
  uri="${registry}/${repo}:${IMAGE_TAG}"
  ctx="$ROOT/aplicacion/$svc"
  [[ -f "$ctx/Dockerfile" ]] || die "No existe $ctx/Dockerfile."

  if aws ecr describe-images --region "$AWS_REGION" --repository-name "$repo" \
       --image-ids "imageTag=$IMAGE_TAG" --output json >/dev/null 2>&1; then
    log "La etiqueta $IMAGE_TAG ya existe en $repo: se omite el push (ECR es inmutable)."
    summary "| $svc | \`$uri\` | omitida (ya existía) | - |"
    continue
  fi

  log "Construyendo $svc..."
  docker build --pull --provenance=false --sbom=false -t "$uri" "$ctx" || die "Falló docker build de $svc."
  log "Subiendo $uri ..."
  docker push "$uri" >/dev/null || die "Falló docker push de $svc (¿repositorio $repo existe y el rol tiene permisos?)."

  # El escaneo de ECR puede tardar en existir: `aws ecr wait` falla de inmediato con
  # ScanNotFoundException, así que se sondea hasta ~3 min (no bloquea el pipeline si no llega).
  findings="n/d"
  critical=0
  scan_json=""
  for ((i = 1; i <= SCAN_MAX_INTENTOS; i++)); do
    scan_json="$(aws ecr describe-image-scan-findings --region "$AWS_REGION" --repository-name "$repo" \
      --image-id "imageTag=$IMAGE_TAG" --output json 2>/dev/null || true)"
    if [[ "$(jq -r '.imageScanStatus.status // empty' <<<"$scan_json" 2>/dev/null || true)" == "COMPLETE" ]]; then
      break
    fi
    scan_json=""
    sleep "$SCAN_ESPERA"
  done
  if [[ -n "$scan_json" ]]; then
    findings="$(jq -r '.imageScanFindings.findingSeverityCounts // {} | to_entries | map("\(.key): \(.value)") | join(", ")' <<<"$scan_json" 2>/dev/null || true)"
    findings="${findings:-sin hallazgos}"
    critical="$(jq -r '.imageScanFindings.findingSeverityCounts.CRITICAL // 0' <<<"$scan_json" 2>/dev/null || echo 0)"
  else
    warn "No se obtuvo el resultado del escaneo de $repo tras $((SCAN_MAX_INTENTOS * SCAN_ESPERA))s (no bloquea el pipeline)."
  fi
  if [[ "$critical" =~ ^[0-9]+$ && "$critical" -gt 0 ]]; then
    warn "$svc tiene $critical vulnerabilidad(es) CRITICAL en el escaneo de ECR."
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then printf '::warning::%s: %s vulnerabilidades CRITICAL en ECR\n' "$svc" "$critical"; fi
    findings="**CRITICAL: $critical** ($findings)"
  fi
  log "Escaneo de $svc: $findings"
  summary "| $svc | \`$uri\` | subida | $findings |"
done

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'image_tag=%s\n' "$IMAGE_TAG" >>"$GITHUB_OUTPUT"
fi
log "Listo."
