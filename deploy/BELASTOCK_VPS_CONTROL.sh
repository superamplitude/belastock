#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
APP_GROUP="lojabelastock"
DOMAIN="belastock.com.br"
LOJA_DOMAIN="loja.belastock.com.br"
APP_PORT="3210"
ROOT_VHOST="/etc/nginx/sites-enabled/belastock.com.br.conf"
LOJA_VHOST="/etc/nginx/sites-enabled/loja.belastock.com.br.conf"
PM2_HOME_DIR="/home/${APP_USER}/.pm2"
PM2_LOCAL="/home/${APP_USER}/.local/bin/pm2"
PM2_UNIT="pm2-${APP_USER}"
BACKUP_BASE="/root/BELASTOCK_BRIDGE_BACKUPS"
CONTROL_URL="https://raw.githubusercontent.com/superamplitude/belastock/main/deploy/BELASTOCK_VPS_CONTROL.sh"
CONTROL_DST="/usr/local/sbin/belastock-vps-control"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }
[ "$EUID" -eq 0 ] || fail "Este controle deve ser executado como root."
mkdir -p "$BACKUP_BASE"

get_env(){ awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");gsub(/\r/,"");print;exit}' "$SITE/.env"; }
pm2_bin(){ [ -x "$PM2_LOCAL" ] && { echo "$PM2_LOCAL"; return; }; command -v pm2 2>/dev/null || true; }
pm2_user(){ local p; p="$(pm2_bin)"; [ -n "$p" ] || fail "PM2 nao encontrado."; sudo -u "$APP_USER" -H env PM2_HOME="$PM2_HOME_DIR" PATH="$(dirname "$p"):/usr/local/bin:/usr/bin:/bin" "$p" "$@"; }

health_local(){
  local c
  c="$(curl -sS --max-time 10 -o /tmp/bs-health-local.json -w '%{http_code}' "http://127.0.0.1:${APP_PORT}/health" || true)"
  echo "LOCAL_HEALTH_HTTP=$c"; cat /tmp/bs-health-local.json 2>/dev/null || true; echo
  [ "$c" = 200 ]
}
health_origin(){
  local c
  c="$(curl -ksS --resolve "${DOMAIN}:443:127.0.0.1" --max-time 15 -o /tmp/bs-health-origin.json -w '%{http_code}' "https://${DOMAIN}/health?bridge=$(date +%s)" || true)"
  echo "ORIGIN_HEALTH_HTTP=$c"; cat /tmp/bs-health-origin.json 2>/dev/null || true; echo
  [ "$c" = 200 ]
}
node_db_ok(){
  local h="$1" p="$2" u="$3" pass="$4" dbname="$5"
  sudo -u "$APP_USER" -H env DBT_HOST="$h" DBT_PORT="$p" DBT_USER="$u" DBT_PASS="$pass" DBT_NAME="$dbname" bash -lc "cd '$SITE' && node --input-type=module -e \"import mysql from 'mysql2/promise'; const c=await mysql.createConnection({host:process.env.DBT_HOST,port:Number(process.env.DBT_PORT),user:process.env.DBT_USER,password:process.env.DBT_PASS,database:process.env.DBT_NAME}); await c.query('SELECT 1'); await c.end();\"" >/dev/null 2>&1
}

restart_stable(){
  pm2_user restart belastock --update-env
  pm2_user save
  local stable=0
  for _ in $(seq 1 30); do
    if health_local >/dev/null 2>&1; then stable=$((stable+1)); [ "$stable" -ge 3 ] && break; else stable=0; fi
    sleep 1
  done
  [ "$stable" -ge 3 ] || { pm2_user logs belastock --nostream --lines 120 || true; fail "Aplicacao nao atingiu health estavel apos restart PM2."; }
  health_local
}

nginx_diagnose(){
  echo "BELA_STOCK_NGINX_DIAG_V3"
  echo "===== ROOT VHOST ====="; sed -n '1,260p' "$ROOT_VHOST" 2>&1 || true
  echo "===== LOJA VHOST ====="; sed -n '1,320p' "$LOJA_VHOST" 2>&1 || true
  echo "===== EFFECTIVE REFERENCES ====="; grep -RniE 'server_name[[:space:]].*(belastock\.com\.br)|proxy_pass[[:space:]]+http' /etc/nginx/sites-enabled 2>/dev/null || true
  echo "===== HEALTH ====="; health_local || true; health_origin || true
}

apply_loja_proxy(){
  [ -f "$LOJA_VHOST" ] || fail "Vhost da loja ausente: $LOJA_VHOST"
  [ -f "/etc/nginx/ssl-certificates/${LOJA_DOMAIN}.crt" ] || fail "Certificado da loja ausente."
  [ -f "/etc/nginx/ssl-certificates/${LOJA_DOMAIN}.key" ] || fail "Chave SSL da loja ausente."
  health_local || fail "Aplicacao local nao esta saudavel."

  local stamp backup
  stamp="$(date +%Y%m%d_%H%M%S)"
  backup="$BACKUP_BASE/loja-vhost-before-node-${stamp}.conf"
  cp -a "$LOJA_VHOST" "$backup"; chmod 600 "$backup"
  echo "LOJA_VHOST_BACKUP=$backup"

  cat > "$LOJA_VHOST" <<'EOF'
server {
  listen 80;
  listen [::]:80;
  server_name loja.belastock.com.br;
  return 301 https://loja.belastock.com.br$request_uri;
}

server {
  listen 443 quic;
  listen 443 ssl;
  listen [::]:443 quic;
  listen [::]:443 ssl;
  http2 on;
  http3 off;
  ssl_certificate_key /etc/nginx/ssl-certificates/loja.belastock.com.br.key;
  ssl_certificate /etc/nginx/ssl-certificates/loja.belastock.com.br.crt;
  server_name loja.belastock.com.br;

  access_log /home/lojabelastock/logs/nginx/loja-access.log main;
  error_log /home/lojabelastock/logs/nginx/loja-error.log;

  location ~ /.well-known {
    auth_basic off;
    allow all;
  }

  include /etc/nginx/global_settings;

  location / {
    proxy_pass http://127.0.0.1:3210/;
    proxy_http_version 1.1;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Host $host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_pass_request_headers on;
    proxy_max_temp_file_size 0;
    proxy_connect_timeout 120;
    proxy_send_timeout 120;
    proxy_read_timeout 120;
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;
    proxy_temp_file_write_size 256k;
  }
}
EOF

  if ! nginx -t; then cp -a "$backup" "$LOJA_VHOST"; nginx -t || true; fail "nginx -t falhou; rollback aplicado."; fi
  systemctl reload nginx
  systemctl is-active --quiet nginx || { cp -a "$backup" "$LOJA_VHOST"; nginx -t && systemctl reload nginx; fail "Nginx nao ficou ativo; rollback aplicado."; }

  local loja_health loja_root loja_api root_page public_loja
  loja_health="$(curl -ksS --resolve "${LOJA_DOMAIN}:443:127.0.0.1" --max-time 15 -o /tmp/loja-health.json -w '%{http_code}' "https://${LOJA_DOMAIN}/health?split=$(date +%s)" || true)"
  loja_root="$(curl -ksS --resolve "${LOJA_DOMAIN}:443:127.0.0.1" --max-time 20 -o /tmp/loja-root.html -w '%{http_code}' "https://${LOJA_DOMAIN}/?split=$(date +%s)" || true)"
  loja_api="$(curl -ksS --resolve "${LOJA_DOMAIN}:443:127.0.0.1" --max-time 20 -o /tmp/loja-store.json -w '%{http_code}' "https://${LOJA_DOMAIN}/api/public/store?split=$(date +%s)" || true)"
  root_page="$(curl -ksS --resolve "${DOMAIN}:443:127.0.0.1" --max-time 20 -o /tmp/root-portal.html -w '%{http_code}' "https://${DOMAIN}/?split=$(date +%s)" || true)"
  public_loja="$(curl -ksS --max-time 20 -o /tmp/loja-public.html -w '%{http_code}' "https://${LOJA_DOMAIN}/?public=$(date +%s)" || true)"

  echo "LOJA_ORIGIN_HEALTH_HTTP=$loja_health (informativo; readiness=storefront+store-api)"
  echo "LOJA_ORIGIN_ROOT_HTTP=$loja_root"
  echo "LOJA_ORIGIN_STORE_API_HTTP=$loja_api"
  echo "ROOT_PORTAL_HTTP=$root_page"
  echo "LOJA_PUBLIC_HTTP=$public_loja"

  if [ "$loja_root" != 200 ] || [ "$loja_api" != 200 ] || [ "$root_page" != 200 ]; then
    cp -a "$backup" "$LOJA_VHOST"; nginx -t && systemctl reload nginx
    fail "Validacao funcional do split falhou; vhost da loja restaurado."
  fi
  grep -q 'hero-slider' /tmp/loja-root.html || { cp -a "$backup" "$LOJA_VHOST"; nginx -t && systemctl reload nginx; fail "Loja Node nao exibiu storefront esperado; rollback aplicado."; }
  grep -q '"code":"belastock"' /tmp/loja-store.json || { cp -a "$backup" "$LOJA_VHOST"; nginx -t && systemctl reload nginx; fail "API da loja nao resolveu tenant Bela Stock; rollback aplicado."; }
  grep -q 'Um mega portal' /tmp/root-portal.html || { cp -a "$backup" "$LOJA_VHOST"; nginx -t && systemctl reload nginx; fail "Dominio raiz nao exibiu portal esperado; rollback aplicado."; }
  [ "$public_loja" = 200 ] || echo "[AVISO] Publico da loja ainda nao refletiu origem; origem esta validada."

  echo "LOJA_VHOST_UPSTREAM=$(grep -Eo 'proxy_pass[[:space:]]+http://127\.0\.0\.1:[0-9]+/' "$LOJA_VHOST" | head -1)"
  ok "DOMAIN_SPLIT_ROOT_PORTAL_LOJA_NODE=100%_OK"
}

cmd="${1:-status}"
case "$cmd" in
  health) health_local; health_origin ;;
  db-test)
    h="$(get_env DB_HOST)"; h="${h:-127.0.0.1}"; p="$(get_env DB_PORT)"; p="${p:-3306}"; u="$(get_env DB_USER)"; pass="$(get_env DB_PASSWORD)"; d="$(get_env DB_NAME)"
    echo "DB_HOST=$h DB_PORT=$p DB_NAME=$d DB_USER=$u"; node_db_ok "$h" "$p" "$u" "$pass" "$d"; echo "DB_AUTH_MYSQL2=OK"
    ;;
  status)
    echo "BELASTOCK_SITE=$SITE BELASTOCK_PORT=$APP_PORT HOST=$(hostname) DATE=$(date -Is)"
    echo "NODE=$(node -v 2>/dev/null || echo ausente) NPM=$(npm -v 2>/dev/null || echo ausente) PM2=$(pm2_bin)"
    nginx -t; systemctl is-active nginx || true; ss -lntp | grep -E ":(80|443|${APP_PORT})[[:space:]]" || true; pm2_user status || true; systemctl is-enabled "$PM2_UNIT" 2>/dev/null || true; systemctl is-active "$PM2_UNIT" 2>/dev/null || true; health_local || true; health_origin || true
    ;;
  inventory)
    echo "=== SITE ==="; ls -la "$SITE" | head -100; echo "=== ROOT VHOST ==="; grep -nE 'server_name|proxy_pass|root |listen ' "$ROOT_VHOST" 2>/dev/null || true; echo "=== LOJA VHOST ==="; grep -nE 'server_name|proxy_pass|root |listen ' "$LOJA_VHOST" 2>/dev/null || true; echo "=== PORTS ==="; ss -lntup || true
    ;;
  backup-site) stamp="$(date +%Y%m%d_%H%M%S)"; out="$BACKUP_BASE/site-${stamp}.tar.gz"; tar -C "$(dirname "$SITE")" -czf "$out" "$(basename "$SITE")"; chmod 600 "$out"; echo "BACKUP=$out" ;;
  refresh-control) tmp="$(mktemp)"; curl -fsSL --retry 3 --connect-timeout 15 "$CONTROL_URL" -o "$tmp"; bash -n "$tmp"; install -o root -g root -m 0755 "$tmp" "$CONTROL_DST"; rm -f "$tmp"; ok "Controlador Bela Stock atualizado do GitHub." ;;
  nginx-test) nginx -t ;;
  nginx-reload) nginx -t; systemctl reload nginx ;;
  nginx-diagnose) nginx_diagnose ;;
  apply-loja-proxy) apply_loja_proxy ;;
  pm2-status) pm2_user status ;;
  pm2-restart) restart_stable ;;
  *) fail "Comando nao autorizado: $cmd" ;;
esac
