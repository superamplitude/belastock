#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

APP_DIR="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
APP_PORT="3210"
REPAIR_URL="https://raw.githubusercontent.com/superamplitude/belastock/main/deploy/CORRIGIR_502_BELASTOCK.sh"
REPAIR_LOCAL="/root/CORRIGIR_502_BELASTOCK.sh"

[[ $EUID -eq 0 ]] || { echo "Execute como root"; exit 1; }

echo "============================================================"
echo " BELA STOCK - RECOVERY TOTAL / UMA EXECUCAO"
echo " $(date -Is)"
echo "============================================================"

# 1. Remove somente instancia antiga do Bela Stock eventualmente criada no PM2 do root.
if command -v pm2 >/dev/null 2>&1 && [[ -d /root/.pm2 ]]; then
  ROOT_PID="$(PM2_HOME=/root/.pm2 pm2 pid belastock 2>/dev/null | head -1 | tr -dc '0-9' || true)"
  if [[ -n "$ROOT_PID" && "$ROOT_PID" != "0" ]]; then
    echo "Removendo instancia antiga 'belastock' do PM2 root (PID $ROOT_PID)..."
    PM2_HOME=/root/.pm2 pm2 delete belastock >/dev/null 2>&1 || true
    PM2_HOME=/root/.pm2 pm2 save --force >/dev/null 2>&1 || true
    sleep 2
  fi
fi

# 2. Se ainda houver listener na porta oficial, so encerra se pertencer ao diretorio do Bela Stock.
if command -v lsof >/dev/null 2>&1; then
  PID="$(lsof -t -iTCP:$APP_PORT -sTCP:LISTEN 2>/dev/null | head -1 || true)"
  if [[ -n "$PID" ]]; then
    CWD="$(readlink -f "/proc/$PID/cwd" 2>/dev/null || true)"
    CMD="$(tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null || true)"
    if [[ "$CWD" == "$APP_DIR"* ]]; then
      echo "Encerrando processo antigo do Bela Stock na porta $APP_PORT: PID=$PID"
      kill "$PID" >/dev/null 2>&1 || true
      sleep 2
    else
      echo "ERRO: porta $APP_PORT esta ocupada por processo externo ao Bela Stock."
      echo "PID=$PID CWD=$CWD CMD=$CMD"
      exit 10
    fi
  fi
fi

# 3. Baixa sempre a auditoria/correcao mais atual e executa tudo de ponta a ponta.
curl -fsSL --retry 3 --connect-timeout 15 "$REPAIR_URL" -o "$REPAIR_LOCAL"
chmod 700 "$REPAIR_LOCAL"
exec bash "$REPAIR_LOCAL"
