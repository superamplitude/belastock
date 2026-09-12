#!/usr/bin/env bash
set -Eeuo pipefail
SITE="/home/lojabelastock/htdocs/belastock.com.br"

echo '===== BELA STOCK INVENTARIO TECNICO PRE-IMPLEMENTACAO ====='
echo "HOST=$(hostname)"
echo "DATE=$(date -Is)"
echo

echo '===== ARQUIVOS ====='
find "$SITE" -maxdepth 4 -type f \
  ! -name '.env' ! -path '*/node_modules/*' \
  -printf '%P\n' 2>/dev/null | sort | head -n 500

echo
echo '===== PACKAGE.JSON ====='
cat "$SITE/package.json" 2>/dev/null || true

echo
echo '===== ECOSYSTEM ====='
cat "$SITE/ecosystem.config.cjs" 2>/dev/null || true

echo
echo '===== ENV KEYS (SEM VALORES) ====='
sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1=[OCULTO]/p' "$SITE/.env" 2>/dev/null | sort || true

echo
echo '===== SERVER ====='
sed -n '1,320p' "$SITE/src/server.mjs" 2>/dev/null || true

echo
echo '===== SUPPLIERS ====='
for f in "$SITE"/src/suppliers/*; do
  [ -f "$f" ] || continue
  echo "--- ${f#$SITE/} ---"
  sed -n '1,320p' "$f"
done

echo
echo '===== AI ORCHESTRATOR ====='
sed -n '1,320p' "$SITE/src/ai/orchestrator.mjs" 2>/dev/null || true

echo
echo '===== DB/MIGRATIONS FILES ====='
find "$SITE" -maxdepth 5 -type f \( -iname '*.sql' -o -iname '*migrat*' -o -iname '*schema*' -o -iname '*database*' \) ! -path '*/node_modules/*' -printf '%P\n' 2>/dev/null | sort | head -n 300

echo
echo '===== PM2 PERMISSOES ====='
command -v pm2 || true
ls -l /usr/local/bin/pm2 2>/dev/null || true
readlink -f /usr/local/bin/pm2 2>/dev/null || true
namei -l /usr/local/bin/pm2 2>/dev/null || true
sudo -n -u lojabelastock -H bash -lc 'echo USER=$(id -un); echo PATH=$PATH; command -v node || true; command -v npm || true; command -v pm2 || true; test -x /usr/local/bin/pm2 && echo PM2_EXECUTABLE=YES || echo PM2_EXECUTABLE=NO' || true

echo
echo '===== PORTAS/PROCESSOS ====='
ss -lntp | grep -E ':(80|443|3210)[[:space:]]' || true
ps -eo pid,user,cmd | grep -Ei '[n]ode|[p]m2' | head -n 80 || true

echo '===== FIM INVENTARIO ====='
