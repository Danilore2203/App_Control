#!/usr/bin/env bash
# Genera la version web de la app y la deja en backend/web_app, que el backend
# sirve en https://centinela-dwh-api.onrender.com/app/ (ver backend/app/main.py).
# Despues: commit + PR a master; Render la publica al desplegar.
#
#   cd mobile && ./publicar_web.sh
#
# CanvasKit no se copia: Flutter lo baja de gstatic (useLocalCanvasKit=false),
# asi el repo no carga ~37 MB por cada version.
set -euo pipefail
cd "$(dirname "$0")"

# MSYS_NO_PATHCONV: en Git Bash de Windows, sin esto «/app/» se convierte en una ruta de disco.
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /app/

destino=../backend/web_app
rm -rf "$destino"
mkdir -p "$destino"
cp -r build/web/. "$destino"/
rm -rf "$destino/canvaskit" "$destino/.last_build_id"
echo "Listo: $(du -sh "$destino" | cut -f1) en backend/web_app"
