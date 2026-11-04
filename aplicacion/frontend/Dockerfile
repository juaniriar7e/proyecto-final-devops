# syntax=docker/dockerfile:1

# Etapa 1: compila la SPA. Las dependencias salen del package-lock.json (npm ci).
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY index.html vite.config.js ./
COPY src ./src
RUN npm run build

# Etapa 2: nginx sin privilegios (escucha en 8080 y corre como uid 101).
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/ /usr/share/nginx/html/
# Script que genera /version.json al arrancar el contenedor desde APP_VERSION.
COPY docker/40-version-json.sh /docker-entrypoint.d/40-version-json.sh

# El script escribe version.json en el directorio raiz: solo ese directorio pasa a ser del usuario 101.
USER root
RUN chmod 0755 /docker-entrypoint.d/40-version-json.sh \
 && chown 101:101 /usr/share/nginx/html
USER 101

ENV APP_VERSION=dev
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1
