#!/usr/bin/env bash
set -Eeuo pipefail

SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
APP_GROUP="lojabelastock"
DOMAIN="belastock.com.br"
VHOST="/etc/nginx/sites-enabled/belastock.com.br.conf"
APP_PORT="3210"
PM2_HOME_DIR="/home/${APP_USER}/.pm2"
PM2_LOCAL="/home/${APP_USER}/.local/bin/pm2"
BACKUP_BASE="/root/BELASTOCK_BRIDGE_BACKUPS"
CONTROL_URL="https://raw.githubusercontent.com/superamplitude/belastock/main/deploy/BELASTOCK_VPS_CONTROL.sh"
CONTROL_DST="/usr/local/sbin/belastock-vps-control"
PM2_SERVICE="/etc/systemd/system/pm2-${APP_USER}.service"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }

[ "${EUID}" -eq 0 ] || fail "Este controle deve ser executado via sudo/root."
mkdir -p "$BACKUP_BASE"

pm2_bin(){
  if [ -x "$PM2_LOCAL" ]; then printf '%s\n' "$PM2_LOCAL"; return; fi
  local global="$(command -v pm2 2>/dev/null || true)"
  [ -n "$global" ] && [ -x "$global" ] && printf '%s\n' "$global" || true
}
pm2_user(){
  local p; p="$(pm2_bin)"; [ -n "$p" ] || fail "PM2 nao encontrado para $APP_USER."
  sudo -u "$APP_USER" -H env PM2_HOME="$PM2_HOME_DIR" PATH="$(dirname "$p"):/usr/local/bin:/usr/bin:/bin" "$p" "$@"
}

get_env(){ awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$SITE/.env"; }

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
    DB_HOST="$(get_env DB_HOST)"; DB_HOST="${DB_HOST:-127.0.0.1}"
    DB_PORT="$(get_env DB_PORT)"; DB_PORT="${DB_PORT:-3306}"
    DB_NAME="$(get_env DB_NAME)"
    DB_USER="$(get_env DB_USER)"
    DB_PASS="$(get_env DB_PASSWORD)"
    echo "DB_HOST=$DB_HOST"
    echo "DB_PORT=$DB_PORT"
    echo "DB_NAME=$DB_NAME"
    echo "DB_USER=$DB_USER"
    MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -NBe 'SELECT 1' "$DB_NAME" >/dev/null
    echo "DB_AUTH=OK"
    ;;

  runtime-repair)
    [ -f "$SITE/.env" ] || fail ".env ausente."
    [ -f "$SITE/package.json" ] || fail "package.json ausente."
    stamp="$(date +%Y%m%d_%H%M%S)"
    dir="$BACKUP_BASE/runtime-$stamp"
    mkdir -p "$dir"
    cp -a "$SITE/.env" "$dir/.env.before"
    chmod 600 "$dir/.env.before"

    echo "[1/7] Instalando PM2 isolado para $APP_USER"
    install -d -o "$APP_USER" -g "$APP_GROUP" -m 0750 "/home/$APP_USER/.local" "$PM2_HOME_DIR"
    sudo -u "$APP_USER" -H npm install -g pm2@7 --prefix "/home/$APP_USER/.local" >/dev/null
    [ -x "$PM2_LOCAL" ] || fail "PM2 local nao foi instalado."

    echo "[2/7] Validando/reparando banco existente sem recriar dados"
    DB_NAME="$(get_env DB_NAME)"; DB_USER="$(get_env DB_USER)"
    [[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || fail "DB_NAME invalido para reparo controlado."
    [[ "$DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || fail "DB_USER invalido para reparo controlado."
    DB_PASS="$(get_env DB_PASSWORD)"
    if ! MYSQL_PWD="$DB_PASS" mysql -h 127.0.0.1 -P 3306 -u "$DB_USER" -NBe 'SELECT 1' "$DB_NAME" >/dev/null 2>&1; then
      mysql -NBe 'SELECT 1' >/dev/null 2>&1 || fail "MySQL root via socket nao esta disponivel; nenhum dado foi alterado."
      if mysql -NBe "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}'" | grep -qx "$DB_NAME"; then
        mysqldump --single-transaction --routines --triggers "$DB_NAME" | gzip -9 > "$dir/${DB_NAME}.sql.gz"
        ok "Backup do banco existente criado: $dir/${DB_NAME}.sql.gz"
      else
        mysql -e "CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
      fi
      NEW_PASS="$(openssl rand -hex 24)"
      mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${NEW_PASS}'; ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${NEW_PASS}'; CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${NEW_PASS}'; ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${NEW_PASS}'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1'; FLUSH PRIVILEGES;"
      python3 - "$SITE/.env" "$NEW_PASS" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); password=sys.argv[2]
vals={'DB_HOST':'127.0.0.1','DB_PORT':'3306','DB_PASSWORD':password}
lines=p.read_text().splitlines(); out=[]; seen=set()
for line in lines:
    key=line.split('=',1)[0] if '=' in line else ''
    if key in vals:
        out.append(f'{key}={vals[key]}'); seen.add(key)
    else: out.append(line)
for k,v in vals.items():
    if k not in seen: out.append(f'{k}={v}')
p.write_text('\n'.join(out)+'\n')
PY
      chown "$APP_USER:$APP_GROUP" "$SITE/.env"; chmod 640 "$SITE/.env"
      DB_PASS="$NEW_PASS"
    fi
    MYSQL_PWD="$DB_PASS" mysql -h 127.0.0.1 -P 3306 -u "$DB_USER" -NBe 'SELECT 1' "$DB_NAME" >/dev/null || fail "Banco continua sem autenticar."
    echo "DB_AUTH=OK"

    echo "[3/7] Dependencias e migrations"
    chown -R "$APP_USER:$APP_GROUP" "$SITE"
    sudo -u "$APP_USER" -H bash -lc "cd '$SITE' && npm install --omit=dev && npm run migrate"

    echo "[4/7] Validacao de codigo"
    sudo -u "$APP_USER" -H bash -lc "cd '$SITE' && npm run check"

    echo "[5/7] Subindo processo Node na porta $APP_PORT"
    pm2_user delete belastock >/dev/null 2>&1 || true
    pm2_user start "$SITE/ecosystem.config.cjs" --update-env
    pm2_user save

    echo "[6/7] Persistencia no boot"
    cat > "$PM2_SERVICE" <<EOF
[Unit]
Description=PM2 Bela Stock
After=network.target mariadb.service mysql.service
Wants=network-online.target
[Service]
Type=forking
User=$APP_USER
Environment=PM2_HOME=$PM2_HOME_DIR
Environment=PATH=/home/$APP_USER/.local/bin:/usr/local/bin:/usr/bin:/bin
PIDFile=$PM2_HOME_DIR/pm2.pid
ExecStart=$PM2_LOCAL resurrect
ExecReload=$PM2_LOCAL reload all
ExecStop=$PM2_LOCAL kill
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "pm2-$APP_USER" >/dev/null

    echo "[7/7] Healthchecks"
    for i in {1..30}; do health_local >/dev/null 2>&1 && break; sleep 1; done
    health_local || fail "Aplicacao nao respondeu localmente."
    nginx -t
    systemctl reload nginx
    health_origin || fail "Origem HTTPS nao respondeu 200."
    ok "RUNTIME_BELASTOCK=100%_OK backup=$dir"
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
