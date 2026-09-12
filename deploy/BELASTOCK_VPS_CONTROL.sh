#!/usr/bin/env bash
set -Eeuo pipefail

SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
APP_GROUP="lojabelastock"
DOMAIN="belastock.com.br"
VHOST="/etc/nginx/sites-enabled/belastock.com.br.conf"
APP_PORT="3210"
PM2_HOME_DIR="/home/${APP_USER}/.pm2"
BACKUP_BASE="/root/BELASTOCK_BRIDGE_BACKUPS"
CONTROL_URL="https://raw.githubusercontent.com/superamplitude/belastock/main/deploy/BELASTOCK_VPS_CONTROL.sh"
CONTROL_DST="/usr/local/sbin/belastock-vps-control"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }

[ "${EUID}" -eq 0 ] || fail "Este controle deve ser executado via sudo/root."
mkdir -p "$BACKUP_BASE"

pm2_bin(){ command -v pm2 2>/dev/null || true; }
pm2_user(){
  local p; p="$(pm2_bin)"; [ -n "$p" ] || fail "PM2 nao encontrado."
  sudo -u "$APP_USER" -H env PM2_HOME="$PM2_HOME_DIR" "$p" "$@"
}

health_local(){
  local code
  code="$(curl -sS --max-time 10 -o /tmp/belastock-bridge-health-local.json -w '%{http_code}' "http://127.0.0.1:${APP_PORT}/health" || true)"
  echo "LOCAL_HEALTH_HTTP=$code"
  cat /tmp/belastock-bridge-health-local.json 2>/dev/null || true
  echo
  [ "$code" = "200" ]
}

health_origin(){
  local code
  code="$(curl -ksS --resolve "${DOMAIN}:443:127.0.0.1" --max-time 15 -o /tmp/belastock-bridge-health-origin.json -w '%{http_code}' "https://${DOMAIN}/health?bridge=$(date +%s)" || true)"
  echo "ORIGIN_HEALTH_HTTP=$code"
  cat /tmp/belastock-bridge-health-origin.json 2>/dev/null || true
  echo
  [ "$code" = "200" ]
}

cmd="${1:-status}"
case "$cmd" in
  status)
    echo "BELASTOCK_SITE=$SITE"
    echo "BELASTOCK_DOMAIN=$DOMAIN"
    echo "BELASTOCK_PORT=$APP_PORT"
    echo "BELASTOCK_VHOST=$VHOST"
    echo "HOST=$(hostname)"
    echo "DATE=$(date -Is)"
    echo "NODE=$(node -v 2>/dev/null || echo ausente)"
    echo "NPM=$(npm -v 2>/dev/null || echo ausente)"
    echo "PM2=$(pm2_bin)"
    [ -f "$SITE/package.json" ] && node -e "const p=require('$SITE/package.json');console.log('APP_NAME='+(p.name||''));console.log('APP_VERSION='+(p.version||''))" || true
    nginx -t
    systemctl is-active nginx || true
    ss -lntp | grep -E ":(80|443|${APP_PORT})[[:space:]]" || true
    pm2_user status || true
    health_local || true
    health_origin || true
    ;;

  health)
    health_local
    health_origin
    ;;

  nginx-test)
    nginx -t
    ;;

  nginx-reload)
    nginx -t
    systemctl reload nginx
    systemctl is-active --quiet nginx || fail "Nginx nao ficou ativo."
    ok "Nginx recarregado."
    ;;

  pm2-status)
    pm2_user status
    ;;

  pm2-restart)
    pm2_user restart belastock --update-env
    pm2_user save
    sleep 2
    health_local
    ok "Bela Stock reiniciado e validado."
    ;;

  db-test)
    [ -f "$SITE/.env" ] || fail ".env ausente."
    DB_HOST="$(awk -F= '/^DB_HOST=/{sub(/^[^=]*=/,"");print;exit}' "$SITE/.env")"
    DB_PORT="$(awk -F= '/^DB_PORT=/{sub(/^[^=]*=/,"");print;exit}' "$SITE/.env")"
    DB_NAME="$(awk -F= '/^DB_NAME=/{sub(/^[^=]*=/,"");print;exit}' "$SITE/.env")"
    DB_USER="$(awk -F= '/^DB_USER=/{sub(/^[^=]*=/,"");print;exit}' "$SITE/.env")"
    DB_PASS="$(awk -F= '/^DB_PASSWORD=/{sub(/^[^=]*=/,"");print;exit}' "$SITE/.env")"
    DB_HOST="${DB_HOST:-127.0.0.1}"; DB_PORT="${DB_PORT:-3306}"
    echo "DB_HOST=$DB_HOST"
    echo "DB_PORT=$DB_PORT"
    echo "DB_NAME=$DB_NAME"
    echo "DB_USER=$DB_USER"
    MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -NBe 'SELECT 1' "$DB_NAME" >/dev/null
    echo "DB_AUTH=OK"
    ;;

  inventory)
    echo "=== SITE ==="
    ls -la "$SITE" | head -100
    echo "=== IMPORTANT FILES ==="
    find "$SITE" -maxdepth 2 -type f \( -name 'package.json' -o -name 'ecosystem.config.cjs' -o -name '.env' -o -name 'server.mjs' -o -name 'server.js' \) -printf '%p\n' 2>/dev/null || true
    echo "=== VHOST ==="
    grep -nE 'server_name|proxy_pass|root |return 301|listen ' "$VHOST" 2>/dev/null || true
    echo "=== PORTS ==="
    ss -lntup || true
    ;;

  backup-site)
    stamp="$(date +%Y%m%d_%H%M%S)"
    out="$BACKUP_BASE/site-${stamp}.tar.gz"
    tar -C "$(dirname "$SITE")" -czf "$out" "$(basename "$SITE")"
    chmod 600 "$out"
    echo "BACKUP=$out"
    ;;

  refresh-control)
    tmp="$(mktemp)"
    curl -fsSL --retry 3 --connect-timeout 15 "$CONTROL_URL" -o "$tmp"
    bash -n "$tmp"
    install -o root -g root -m 0755 "$tmp" "$CONTROL_DST"
    rm -f "$tmp"
    ok "Controlador Bela Stock atualizado do GitHub."
    ;;

  *)
    fail "Comando nao autorizado: $cmd"
    ;;
esac
