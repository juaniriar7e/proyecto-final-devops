#!/usr/bin/env bash
# Despliega IMAGE_TAG en los servicios ECS (backend primero, luego frontend).
# Variables: AWS_REGION, PROJECT_PREFIX, IMAGE_TAG; opcionales DESIRED_COUNT (1), STATE_FILE.
# Guarda en STATE_FILE las revisiones previas (servicio<TAB>arn<TAB>imagen) para rollback.sh.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd aws jq
require_vars AWS_REGION PROJECT_PREFIX IMAGE_TAG
DESIRED_COUNT="${DESIRED_COUNT:-1}"
STATE_FILE="${STATE_FILE:-$(default_state_file)}"
CLUSTER="${PROJECT_PREFIX}-cluster"
SERVICES=(backend frontend)   # el orden importa: backend primero
export AWS_DEFAULT_REGION="$AWS_REGION"
[[ "$DESIRED_COUNT" =~ ^[0-9]+$ ]] || die "DESIRED_COUNT debe ser un entero (recibido '$DESIRED_COUNT')."

account="$(aws sts get-caller-identity --output json | jq -r '.Account')" \
  || die "No se pudo consultar la identidad de AWS."
registry="${account}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# 1. Verificar que la imagen existe en ambos repositorios antes de tocar nada.
for svc in "${SERVICES[@]}"; do
  repo="${PROJECT_PREFIX}-${svc}"
  aws ecr describe-images --repository-name "$repo" --image-ids "imageTag=$IMAGE_TAG" --output json >/dev/null 2>&1 \
    || die "La imagen $repo:$IMAGE_TAG no existe en ECR. Ejecuta primero el pipeline 2-build (o indica otra etiqueta)."
  log "Imagen verificada: $repo:$IMAGE_TAG"
done

# 2. Leer revisiones actuales y preparar las nuevas task definitions.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
: >"$tmp/state"
for svc in "${SERVICES[@]}"; do
  service="${PROJECT_PREFIX}-${svc}"
  current_arn="$(aws ecs describe-services --cluster "$CLUSTER" --services "$service" --output json \
    | jq -r '.services[0].taskDefinition // empty')" || die "No se pudo describir el servicio $service."
  [[ -n "$current_arn" ]] || die "El servicio $service no existe en el cluster $CLUSTER. ¿Se aplicó la infraestructura?"
  aws ecs describe-task-definition --task-definition "$current_arn" --output json \
    | jq '.taskDefinition' >"$tmp/$svc.current.json" || die "No se pudo leer la task definition $current_arn."
  prev_image="$(jq -r --arg n "$svc" '.containerDefinitions[] | select(.name==$n) | .image' "$tmp/$svc.current.json")"
  [[ -n "$prev_image" ]] || die "La task definition $current_arn no tiene un contenedor llamado '$svc'."
  printf '%s\t%s\t%s\n' "$svc" "$current_arn" "$prev_image" >>"$tmp/state"

  new_image="${registry}/${PROJECT_PREFIX}-${svc}:${IMAGE_TAG}"
  jq --arg n "$svc" --arg img "$new_image" --arg ver "$IMAGE_TAG" '
      .containerDefinitions |= map(
        if .name == $n then
          .image = $img
          | .environment = ((.environment // []) | map(select(.name != "APP_VERSION")) + [{name:"APP_VERSION", value:$ver}])
        else . end)
      | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
    ' "$tmp/$svc.current.json" >"$tmp/$svc.new.json" || die "Falló la transformación de la task definition de $svc."
done

# Guardar el estado previo antes de cambiar nada: así rollback.sh funciona ante fallos parciales.
mkdir -p "$(dirname "$STATE_FILE")"
cp "$tmp/state" "$STATE_FILE"
log "Revisiones previas guardadas en $STATE_FILE"

# 3. Registrar nuevas revisiones.
declare -A NEW_ARN
for svc in "${SERVICES[@]}"; do
  NEW_ARN[$svc]="$(aws ecs register-task-definition --cli-input-json "file://$tmp/$svc.new.json" --output json \
    | jq -r '.taskDefinition.taskDefinitionArn')" || die "Falló el registro de la task definition de $svc."
  log "Registrada ${NEW_ARN[$svc]}"
done

# 4. Actualizar servicios, backend primero.
for svc in "${SERVICES[@]}"; do
  aws ecs update-service --cluster "$CLUSTER" --service "${PROJECT_PREFIX}-${svc}" \
    --task-definition "${NEW_ARN[$svc]}" --desired-count "$DESIRED_COUNT" --output json >/dev/null \
    || die "Falló update-service de $svc."
  log "Servicio ${PROJECT_PREFIX}-${svc} actualizado (desired-count=$DESIRED_COUNT)."
done

# 5. Esperar estabilidad (el circuit breaker de ECS puede revertir por su cuenta).
log "Esperando a que los servicios estén estables..."
aws ecs wait services-stable --cluster "$CLUSTER" \
  --services "${PROJECT_PREFIX}-backend" "${PROJECT_PREFIX}-frontend" \
  || die "Los servicios no se estabilizaron a tiempo (revisa eventos de ECS y logs en CloudWatch)."
log "Despliegue de $IMAGE_TAG estable."
summary "### Despliegue: \`$IMAGE_TAG\` en \`$CLUSTER\` (desired-count=$DESIRED_COUNT)"
