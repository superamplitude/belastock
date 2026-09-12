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
  local p="$(command -v pm2 2>/dev/null || true)"
  [ -n "$p" ] && [ -x "$p" ] && printf '%s\n' "$p" || true
}
pm2_user(){
  local p; p="$(pm2_bin)"; [ -n "$p" ] || fail "PM2 nao encontrado para $APP_USER."
  sudo -u "$APP_USER" -H env PM2_HOME="$PM2_HOME_DIR" PATH="$(dirname "$p"):/usr/local/bin:/usr/bin:/bin" "$p" "$@"
}
get_env(){ awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$SITE/.env"; }
set_env(){
  local key="$1" value="$2"
  if grep -q "^${key}=" "$SITE/.env"; then sed -i "s#^${key}=.*#${key}=${value}#" "$SITE/.env"; else echo "${key}=${value}" >> "$SITE/.env"; fi
}
health_local(){
  local code
  code="$(curl -sS --max-time 10 -o /tmp/belastock-health-local.json -w '%{http_code}' "http://127.0.0.1:${APP_PORT}/health" || true)"
  echo "LOCAL_HEALTH_HTTP=$code"; cat /tmp/belastock-health-local.json 2>/dev/null || true; echo
  [ "$code" = "200" ]
}
health_origin(){
  local code
  code="$(curl -ksS --resolve "${DOMAIN}:443:127.0.0.1" --max-time 15 -o /tmp/belastock-health-origin.json -w '%{http_code}' "https://${DOMAIN}/health?bridge=$(date +%s)" || true)"
  echo "ORIGIN_HEALTH_HTTP=$code"; cat /tmp/belastock-health-origin.json 2>/dev/null || true; echo
  [ "$code" = "200" ]
}

MASTER_HOST=""; MASTER_PORT=""; MASTER_USER=""; MASTER_PASS=""
load_cloudpanel_master(){
  command -v clpctl >/dev/null 2>&1 || return 1
  local raw parsed passonly
  raw="$(clpctl db:show:master-credentials 2>/dev/null || clpctl db:show:credentials 2>/dev/null || true)"
  if [ -n "$raw" ]; then
    parsed="$(printf '%s\n' "$raw" | python3 -c '
import sys,re,shlex
text=sys.stdin.read()
text=re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", text)
lines=[re.sub(r"[│┃║|]", " ", x).strip() for x in text.splitlines() if x.strip()]
def field(patterns):
    for line in lines:
        for pat in patterns:
            m=re.search(pat+r"\s*[:=]?\s+(.+)$", line, re.I)
            if m:
                v=m.group(1).strip().strip("│| ")
                if v:
                    return v.split()[0].strip("\"\x27")
    return ""
host=field([r"\bHost\b"])
port=field([r"\bPort\b"])
user=field([r"\bUser\s*Name\b",r"\bUsername\b",r"\bUser\b"])
password=field([r"\bPassword\b"])
for line in lines:
    if "mysql " not in line.lower():
        continue
    cmd=line[line.lower().find("mysql "):]
    try: parts=shlex.split(cmd)
    except Exception: continue
    i=0
    while i<len(parts):
        t=parts[i]
        def nxt():
            return parts[i+1] if i+1<len(parts) else ""
        if t in ("-h","--host"): host=host or nxt(); i+=1
        elif t.startswith("--host="): host=host or t.split("=",1)[1]
        elif t.startswith("-h") and len(t)>2: host=host or t[2:]
        elif t in ("-P","--port"): port=port or nxt(); i+=1
        elif t.startswith("--port="): port=port or t.split("=",1)[1]
        elif t.startswith("-P") and len(t)>2: port=port or t[2:]
        elif t in ("-u","--user"): user=user or nxt(); i+=1
        elif t.startswith("--user="): user=user or t.split("=",1)[1]
        elif t.startswith("-u") and len(t)>2: user=user or t[2:]
        elif t in ("-p","--password"): password=password or nxt(); i+=1
        elif t.startswith("--password="): password=password or t.split("=",1)[1]
        elif t.startswith("-p") and len(t)>2: password=password or t[2:]
        i+=1
    break
host=host or "127.0.0.1"; port=port or "3306"; user=user or "root"
for k,v in [("MASTER_HOST",host),("MASTER_PORT",port),("MASTER_USER",user),("MASTER_PASS",password)]:
    print(f"{k}={shlex.quote(v)}")
')"
    eval "$parsed"
  fi
  if [ -z "$MASTER_PASS" ]; then
    passonly="$(clpctl db:show:master-password 2>/dev/null | tail -n 1 | tr -d '\r\n' || true)"
    if [ -n "$passonly" ] && [[ "$passonly" != *"Command"* ]] && [[ "$passonly" != *"Error"* ]]; then
      MASTER_HOST="${MASTER_HOST:-127.0.0.1}"; MASTER_PORT="${MASTER_PORT:-3306}"; MASTER_USER="${MASTER_USER:-root}"; MASTER_PASS="$passonly"
    fi
  fi
  [ -n "$MASTER_PASS" ] || return 1
  MYSQL_PWD="$MASTER_PASS" mysql --protocol=TCP -h "${MASTER_HOST:-127.0.0.1}" -P "${MASTER_PORT:-3306}" -u "${MASTER_USER:-root}" -NBe 'SELECT 1' >/dev/null 2>&1
}

cmd="${1:-status}"
case "$cmd" in
  status)
    echo "BELASTOCK_SITE=$SITE"; echo "BELASTOCK_DOMAIN=$DOMAIN"; echo "BELASTOCK_PORT=$APP_PORT"; echo "HOST=$(hostname)"; echo "DATE=$(date -Is)"
    echo "NODE=$(node -v 2>/dev/null || echo ausente)"; echo "NPM=$(npm -v 2>/dev/null || echo ausente)"; echo "PM2=$(pm2_bin)"
    [ -f "$SITE/package.json" ] && node -e "const p=require('$SITE/package.json');console.log('APP_NAME='+(p.name||''));console.log('APP_VERSION='+(p.version||''))" || true
    nginx -t; systemctl is-active nginx || true; ss -lntp | grep -E ":(80|443|${APP_PORT})[[:space:]]" || true; pm2_user status || true; health_local || true; health_origin || true
    ;;
  health) health_local; health_origin ;;
  nginx-test) nginx -t ;;
  nginx-reload) nginx -t; systemctl reload nginx; systemctl is-active --quiet nginx || fail "Nginx nao ficou ativo." ;;
  pm2-status) pm2_user status ;;
  pm2-restart) pm2_user restart belastock --update-env; pm2_user save; sleep 2; health_local ;;
  mysql-admin-diagnose)
    echo "CLPCTL=$(command -v clpctl 2>/dev/null || echo ausente)"
    if load_cloudpanel_master; then echo "MASTER_PARSE=OK"; echo "MASTER_HOST=$MASTER_HOST"; echo "MASTER_PORT=$MASTER_PORT"; echo "MASTER_USER=$MASTER_USER"; echo "MASTER_AUTH=OK"; else echo "MASTER_PARSE=FAIL"; fi
    unset MASTER_PASS
    ;;
  db-test)
    [ -f "$SITE/.env" ] || fail ".env ausente."
    DB_HOST="$(get_env DB_HOST)"; DB_HOST="${DB_HOST:-127.0.0.1}"; DB_PORT="$(get_env DB_PORT)"; DB_PORT="${DB_PORT:-3306}"; DB_NAME="$(get_env DB_NAME)"; DB_USER="$(get_env DB_USER)"; DB_PASS="$(get_env DB_PASSWORD)"
    echo "DB_HOST=$DB_HOST"; echo "DB_PORT=$DB_PORT"; echo "DB_NAME=$DB_NAME"; echo "DB_USER=$DB_USER"
    MYSQL_PWD="$DB_PASS" mysql --protocol=TCP -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -NBe 'SELECT 1' "$DB_NAME" >/dev/null; echo "DB_AUTH=OK"
    ;;
  runtime-repair)
    [ -f "$SITE/.env" ] || fail ".env ausente."; [ -f "$SITE/package.json" ] || fail "package.json ausente."
    stamp="$(date +%Y%m%d_%H%M%S)"; dir="$BACKUP_BASE/runtime-$stamp"; mkdir -p "$dir"; cp -a "$SITE/.env" "$dir/.env.before"; chmod 600 "$dir/.env.before"
    echo "[1/7] PM2 isolado para $APP_USER"
    install -d -o "$APP_USER" -g "$APP_GROUP" -m 0750 "/home/$APP_USER/.local" "$PM2_HOME_DIR"
    sudo -u "$APP_USER" -H npm install -g pm2@7 --prefix "/home/$APP_USER/.local" >/dev/null
    [ -x "$PM2_LOCAL" ] || fail "PM2 local nao foi instalado."

    echo "[2/7] Banco de dados"
    DB_HOST="$(get_env DB_HOST)"; DB_HOST="${DB_HOST:-127.0.0.1}"; DB_PORT="$(get_env DB_PORT)"; DB_PORT="${DB_PORT:-3306}"; DB_NAME="$(get_env DB_NAME)"; DB_USER="$(get_env DB_USER)"; DB_PASS="$(get_env DB_PASSWORD)"
    [[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || fail "DB_NAME invalido."; [[ "$DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || fail "DB_USER invalido."
    app_db_ok(){ MYSQL_PWD="$DB_PASS" mysql --protocol=TCP -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -NBe 'SELECT 1' "$DB_NAME" >/dev/null 2>&1; }
    if ! app_db_ok; then
      ADMIN_MODE=""
      if mysql -NBe 'SELECT 1' >/dev/null 2>&1; then ADMIN_MODE="socket-root"; else load_cloudpanel_master && ADMIN_MODE="cloudpanel" || true; fi
      [ -n "$ADMIN_MODE" ] || fail "Sem acesso administrativo seguro ao MySQL."
      echo "MYSQL_ADMIN_MODE=$ADMIN_MODE"
      mysql_admin(){ local sql="$1"; if [ "$ADMIN_MODE" = "socket-root" ]; then mysql -NBe "$sql"; else MYSQL_PWD="$MASTER_PASS" mysql --protocol=TCP -h "$MASTER_HOST" -P "$MASTER_PORT" -u "$MASTER_USER" -NBe "$sql"; fi; }
      dump_db(){ if [ "$ADMIN_MODE" = "socket-root" ]; then mysqldump --single-transaction --quick --routines --triggers "$DB_NAME"; else MYSQL_PWD="$MASTER_PASS" mysqldump --protocol=TCP -h "$MASTER_HOST" -P "$MASTER_PORT" -u "$MASTER_USER" --single-transaction --quick --routines --triggers "$DB_NAME"; fi; }
      EXISTS="$(mysql_admin "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='${DB_NAME}';" | tail -1)"
      if [ "$EXISTS" = "1" ]; then dump_db | gzip -9 > "$dir/${DB_NAME}.sql.gz" || true; ok "Backup DB: $dir/${DB_NAME}.sql.gz"; fi
      NEW_PASS="$(openssl rand -hex 24)"
      esc="${NEW_PASS//\\/\\\\}"; esc="${esc//\'/\\\'}"
      mysql_admin "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
      mysql_admin "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${esc}'; ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${esc}';"
      mysql_admin "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${esc}'; ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${esc}';"
      mysql_admin "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1'; FLUSH PRIVILEGES;"
      DB_HOST="127.0.0.1"; DB_PORT="3306"; DB_PASS="$NEW_PASS"; set_env DB_HOST "$DB_HOST"; set_env DB_PORT "$DB_PORT"; set_env DB_PASSWORD "$DB_PASS"; chown "$APP_USER:$APP_GROUP" "$SITE/.env"; chmod 640 "$SITE/.env"
      unset MASTER_PASS esc NEW_PASS
    fi
    app_db_ok || fail "Banco continua sem autenticar."; echo "DB_AUTH=OK"

    echo "[3/7] Dependencias e migrations"
    chown -R "$APP_USER:$APP_GROUP" "$SITE"
    sudo -u "$APP_USER" -H bash -lc "cd '$SITE' && npm install --omit=dev && npm run migrate"
    echo "[4/7] Testes"
    sudo -u "$APP_USER" -H bash -lc "cd '$SITE' && npm run check"
    echo "[5/7] PM2"
    pm2_user delete belastock >/dev/null 2>&1 || true; pm2_user start "$SITE/ecosystem.config.cjs" --update-env; pm2_user save
    echo "[6/7] Boot"
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
    systemctl daemon-reload; systemctl enable "pm2-$APP_USER" >/dev/null
    echo "[7/7] Health"
    for i in {1..40}; do health_local >/dev/null 2>&1 && break; sleep 1; done
    health_local || { pm2_user logs belastock --nostream --lines 120 || true; fail "Aplicacao nao respondeu localmente."; }
    nginx -t; systemctl reload nginx; health_origin || fail "Origem HTTPS nao respondeu 200."
    ok "RUNTIME_BELASTOCK=100%_OK backup=$dir"
    ;;
  inventory)
    echo "=== SITE ==="; ls -la "$SITE" | head -100
    echo "=== VHOST ==="; grep -nE 'server_name|proxy_pass|root |return 301|listen ' "$VHOST" 2>/dev/null || true
    echo "=== PORTS ==="; ss -lntup || true
    ;;
  backup-site)
    stamp="$(date +%Y%m%d_%H%M%S)"; out="$BACKUP_BASE/site-${stamp}.tar.gz"; tar -C "$(dirname "$SITE")" -czf "$out" "$(basename "$SITE")"; chmod 600 "$out"; echo "BACKUP=$out"
    ;;
  refresh-control)
    tmp="$(mktemp)"; curl -fsSL --retry 3 --connect-timeout 15 "${CONTROL_URL}?v=$(date +%s)" -o "$tmp"; bash -n "$tmp"; install -o root -g root -m 0755 "$tmp" "$CONTROL_DST"; rm -f "$tmp"; ok "Controlador Bela Stock atualizado do GitHub."
    ;;
  *) fail "Comando nao autorizado: $cmd" ;;
esac
