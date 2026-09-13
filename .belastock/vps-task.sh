#!/usr/bin/env bash
set -Eeuo pipefail
SITE="/home/lojabelastock/htdocs/belastock.com.br"
echo "============================================================"
echo " BELA STOCK - INVENTARIO DE IMAGENS HERO SEM ALTERAR PRODUCAO"
echo " HOST=$(hostname) DATE=$(date -Is)"
echo "============================================================"
test -d "$SITE"
echo "--- IMAGENS NO SITE ---"
find "$SITE/public" -type f \( -iname '*.webp' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -printf '%p %s bytes\n' 2>/dev/null | sort | head -n 500 || true
echo "--- IMAGENS/BANNERS EM /home/lojabelastock ---"
find /home/lojabelastock -maxdepth 7 -type f \( -iname '*hero*' -o -iname '*banner*' -o -iname '*.webp' \) -printf '%p %s bytes\n' 2>/dev/null | sort | head -n 1000 || true
echo "BELA_STOCK_IMAGE_INVENTORY=100%_OK"
