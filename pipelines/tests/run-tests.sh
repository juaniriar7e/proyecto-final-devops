#!/usr/bin/env bash
# Pruebas de deploy.sh, rollback.sh y smoke-test.sh con un `aws` falso y un servidor local.
# No usa AWS real. Uso: pipelines/tests/run-tests.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
WORK="$(mktemp -d)"
SERVER_PID=""
PASS=0; FAIL=0

stop_server() { [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null; SERVER_PID=""; }
trap 'stop_server; rm -rf "$WORK"' EXIT

export PATH="$HERE/bin:$PATH"
export AWS_REGION=us-east-1 PROJECT_PREFIX=triplepipe-demo
export FAKE_AWS_DIR="$WORK/aws" STATE_FILE="$WORK/state.tsv"
export SMOKE_RETRIES=2 SMOKE_DELAY=0

check() { # check "descripción" comando...
  local d="$1"; shift
  if "$@" >"$WORK/chk.out" 2>&1; then echo "  ok   - $d"; PASS=$((PASS + 1))
  else echo "  FALLA - $d"; sed 's/^/        /' "$WORK/chk.out"; FAIL=$((FAIL + 1)); fi
}
calls() { cat "$FAKE_AWS_DIR/calls.log"; }
current() { cat "$FAKE_AWS_DIR/current_$1"; }

# new_env <imagen_previa_backend> <imagen_previa_frontend>: estado inicial con la revisión 1
new_env() {
  rm -rf "$FAKE_AWS_DIR" "$STATE_FILE"; mkdir -p "$FAKE_AWS_DIR"; : >"$FAKE_AWS_DIR/calls.log"
  local s img
  for s in backend frontend; do
    [[ $s == backend ]] && img="$1" || img="$2"
    jq -n --arg s "$s" --arg img "$img" '{
      taskDefinitionArn: ("arn:aws:ecs:us-east-1:000000000000:task-definition/triplepipe-demo-" + $s + ":1"),
      family: ("triplepipe-demo-" + $s), revision: 1, status: "ACTIVE",
      requiresAttributes: [{name:"x"}], compatibilities: ["FARGATE"], registeredAt: "2026-01-01", registeredBy: "arn:x",
      cpu: "256", memory: "512", networkMode: "awsvpc", requiresCompatibilities: ["FARGATE"],
      containerDefinitions: [{name:$s, image:$img, essential:true, environment:[{name:"APP_VERSION", value:"old"},{name:"OTRA", value:"1"}]}]}' \
      >"$FAKE_AWS_DIR/td_triplepipe-demo-${s}_1.json"
    echo "arn:aws:ecs:us-east-1:000000000000:task-definition/triplepipe-demo-${s}:1" >"$FAKE_AWS_DIR/current_$s"
  done
}

start_server() { # start_server <version> [flags]
  stop_server
  rm -f "$WORK/port"
  python3 "$HERE/fake-app.py" "$WORK/port" "$@" &
  SERVER_PID=$!
  local n=0; while [[ ! -s "$WORK/port" && $n -lt 50 ]]; do sleep 0.1; n=$((n + 1)); done
  FAKE_ALB_DNS="127.0.0.1:$(cat "$WORK/port")"; export FAKE_ALB_DNS
  URL="http://$FAKE_ALB_DNS"
}
tasks_left() { curl -s "$URL/api/tasks" | jq 'length'; }

OLD_B="000000000000.dkr.ecr.us-east-1.amazonaws.com/triplepipe-demo-backend:sha-aaaaaaa"
OLD_F="000000000000.dkr.ecr.us-east-1.amazonaws.com/triplepipe-demo-frontend:sha-aaaaaaa"

echo "== Caso 1: éxito =="
new_env "$OLD_B" "$OLD_F"; start_server sha-bbbbbbb
export IMAGE_TAG=sha-bbbbbbb
check "deploy.sh termina bien" "$SCRIPTS/deploy.sh"
check "revisión nueva del backend en uso" grep -q 'triplepipe-demo-backend:2' "$FAKE_AWS_DIR/current_backend"
check "imagen nueva y APP_VERSION en la task definition" jq -e \
  '.containerDefinitions[0].image | endswith("triplepipe-demo-backend:sha-bbbbbbb")' "$FAKE_AWS_DIR/td_triplepipe-demo-backend_2.json"
check "APP_VERSION actualizado sin duplicar y se conserva OTRA" jq -e \
  '([.containerDefinitions[0].environment[] | select(.name=="APP_VERSION")] | length==1) and (.containerDefinitions[0].environment | map(select(.name=="APP_VERSION"))[0].value=="sha-bbbbbbb") and (.containerDefinitions[0].environment | map(.name) | index("OTRA") != null)' \
  "$FAKE_AWS_DIR/td_triplepipe-demo-backend_2.json"
check "backend se actualiza antes que el frontend" bash -c \
  "calls() { cat '$FAKE_AWS_DIR/calls.log'; }; b=\$(calls | grep -n 'update-service.*-backend' | head -1 | cut -d: -f1); f=\$(calls | grep -n 'update-service.*-frontend' | head -1 | cut -d: -f1); [ \"\$b\" -lt \"\$f\" ]"
check "desired-count 1 por defecto" bash -c "grep -q 'desired-count 1' '$FAKE_AWS_DIR/calls.log'"
check "se guardó el estado previo" test -s "$STATE_FILE"
check "alb-url.sh devuelve la URL" test "$("$SCRIPTS/alb-url.sh")" = "$URL"
check "smoke-test.sh pasa" "$SCRIPTS/smoke-test.sh" "$URL" sha-bbbbbbb
check "smoke no deja tareas" test "$(tasks_left)" = 0

echo "== Caso 2: imagen inexistente =="
new_env "$OLD_B" "$OLD_F"
export IMAGE_TAG=sha-ddddddd FAKE_MISSING_TAGS="sha-ddddddd"
"$SCRIPTS/deploy.sh" >"$WORK/out" 2>&1; rc=$?
check "deploy.sh falla" test $rc -ne 0
check "mensaje claro en español" grep -q 'no existe en ECR' "$WORK/out"
check "no se registró nada" bash -c "! grep -q register-task-definition '$FAKE_AWS_DIR/calls.log'"
check "no se creó estado" test ! -e "$STATE_FILE"
"$SCRIPTS/rollback.sh" >"$WORK/out" 2>&1; rc=$?
check "rollback sin estado no falla y avisa" bash -c "[ $rc -eq 0 ] && grep -q 'nada que revertir' '$WORK/out'"
unset FAKE_MISSING_TAGS

echo "== Caso 3: smoke test fallido seguido de rollback =="
new_env "$OLD_B" "$OLD_F"; start_server sha-OTRA   # el servidor responde otra versión
export IMAGE_TAG=sha-eeeeeee
"$SCRIPTS/deploy.sh" >"$WORK/out" 2>&1 || { cat "$WORK/out"; }
"$SCRIPTS/smoke-test.sh" "$URL" sha-eeeeeee >"$WORK/out" 2>&1; rc=$?
check "smoke-test.sh falla por versión distinta" bash -c "[ $rc -ne 0 ] && grep -q 'se esperaba' '$WORK/out'"
"$SCRIPTS/rollback.sh" >"$WORK/out" 2>&1; rc=$?
check "rollback.sh termina bien" test $rc -eq 0
check "backend vuelve a la revisión 1" grep -q 'backend:1$' "$FAKE_AWS_DIR/current_backend"
check "frontend vuelve a la revisión 1" grep -q 'frontend:1$' "$FAKE_AWS_DIR/current_frontend"
# Fallo a mitad del CRUD: la tarea creada debe limpiarse
start_server sha-eeeeeee --fail-patch
"$SCRIPTS/smoke-test.sh" "$URL" sha-eeeeeee >"$WORK/out" 2>&1; rc=$?
check "smoke falla si PATCH falla" test $rc -ne 0
check "trap eliminó la tarea creada" test "$(tasks_left)" = 0

echo "== Caso 4: primer despliegue (imagen bootstrap) =="
BOOT_B="000000000000.dkr.ecr.us-east-1.amazonaws.com/triplepipe-demo-backend:bootstrap"
BOOT_F="000000000000.dkr.ecr.us-east-1.amazonaws.com/triplepipe-demo-frontend:bootstrap"
new_env "$BOOT_B" "$BOOT_F"; export IMAGE_TAG=sha-fffffff
"$SCRIPTS/deploy.sh" >"$WORK/out" 2>&1 || cat "$WORK/out"
check "estado previo registra bootstrap" grep -q 'bootstrap' "$STATE_FILE"
: >"$FAKE_AWS_DIR/calls.log"
"$SCRIPTS/rollback.sh" >"$WORK/out" 2>&1; rc=$?
check "rollback.sh termina bien" test $rc -eq 0
check "pone desired-count 0 en ambos servicios" bash -c "[ \$(grep -c 'update-service.*desired-count 0' '$FAKE_AWS_DIR/calls.log') -eq 2 ]"
check "no vuelve a la revisión bootstrap" bash -c "! grep -q -- '--task-definition' '$FAKE_AWS_DIR/calls.log'"
check "la salida no contiene credenciales" bash -c "! grep -qiE 'secret|AKIA|token' '$WORK/out'"

echo
echo "Resultado: $PASS correctas, $FAIL con fallo."
[[ $FAIL -eq 0 ]]
