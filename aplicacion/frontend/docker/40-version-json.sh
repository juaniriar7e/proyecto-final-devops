#!/bin/sh
# Se ejecuta al arrancar el contenedor (docker-entrypoint.d) y genera /version.json
# a partir de APP_VERSION. Asi la version no queda fijada en el build.
set -eu

version="${APP_VERSION:-dev}"
# Escapa barras invertidas y comillas para que el JSON siempre sea valido.
escaped=$(printf '%s' "$version" | sed 's/\\/\\\\/g; s/"/\\"/g')

printf '{"version": "%s", "service": "frontend"}\n' "$escaped" > /usr/share/nginx/html/version.json
echo "40-version-json: version.json generado con version=${version}"
