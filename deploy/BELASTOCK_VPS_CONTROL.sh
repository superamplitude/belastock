#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

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
[ "${EUID}" -eq 0 ] || fail "Este controle deve ser executado como root."
mkdir -p "$BACKUP_BASE"

get_env(){ awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$SITE/.env"; }
set_env(){
  local key="$1" value="$2"
  if grep -q "^${key}=" "$SITE/.env"; then
    sed -i "s#^${key}=.*#${key}=${value}#" "$SITE/.env"
  else
    printf '%s=%s\n' "$key" "$value" >> "$SITE/.env"
  fi
}
pm2_bin(){
  if [ -x "$PM2_LOCAL" ]; then printf '%s\n' "$PM2_LOCAL"; return; fi
  command -v pm2 2>/dev/null || true
}
pm2_user(){
  local p; p="$(pm2_bin)"; [ -n "$p" ] || fail "PM2 nao encontrado para $APP_USER."
  sudo -u "$APP_USER" -H env PM2_HOME="$PM2_HOME_DIR" PATH="$(dirname "$p"):/usr/local/bin:/usr/bin:/bin" "$p" "$@"
}
health_local(){
  local code
  code="$(curl -sS --max-time 10 -o /tmp/bs-health-local.json -w '%{http_code}' "http://127.0.0.1:${APP_PORT}/health" || true)"
  echo "LOCAL_HEALTH_HTTP=$code"
  cat /tmp/bs-health-local.json 2>/dev/null || true
  echo
  [ "$code" = "200" ]
}
health_origin(){
  local code
  code="$(curl -ksS --resolve "${DOMAIN}:443:127.0.0.1" --max-time 15 -o /tmp/bs-health-origin.json -w '%{http_code}' "https://${DOMAIN}/health?bridge=$(date +%s)" || true)"
  echo "ORIGIN_HEALTH_HTTP=$code"
  cat /tmp/bs-health-origin.json 2>/dev/null || true
  echo
  [ "$code" = "200" ]
}

MASTER_HOST=""; MASTER_PORT=""; MASTER_USER=""; MASTER_PASS=""
load_cloudpanel_master(){
  command -v clpctl >/dev/null 2>&1 || return 1
  local raw parsed passonly
  raw="$(clpctl db:show:master-credentials 2>&1 || true)"
  if [ -z "$raw" ]; then raw="$(clpctl db:show:credentials 2>&1 || true)"; fi

  if [ -n "$raw" ]; then
    parsed="$(printf '%s\n' "$raw" | python3 -c '
import sys,re,shlex
text=sys.stdin.read()
text=re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", text)
text=text.replace("│"," ").replace("┃"," ").replace("║"," ").replace("|"," ")
lines=[x.strip() for x in text.splitlines() if x.strip()]
host=port=user=password=""

def val_after(label,line):
    m=re.search(r"(?:^|\s)"+label+r"\s*(?::|=|\s)\s*(\S+)", line, re.I)
    return m.group(1).strip("\"\x27") if m else ""

for line in lines:
    host=host or val_after(r"Host",line)
    port=port or val_after(r"Port",line)
    user=user or val_after(r"User\s*Name",line) or val_after(r"Username",line)
    password=password or val_after(r"Password",line)

for line in lines:
    pos=line.lower().find("mysql ")
    if pos < 0: continue
    cmd=line[pos:]
    try: parts=shlex.split(cmd)
    except Exception: parts=cmd.split()
    i=0
    while i < len(parts):
        t=parts[i]
        nxt=parts[i+1] if i+1 < len(parts) else ""
        if t in ("-h","--host"): host=host or nxt; i+=1
        elif t.startswith("--host="): host=host or t.split("=",1)[1]
        elif t.startswith("-h") and len(t)>2: host=host or t[2:]
        elif t in ("-P","--port"): port=port or nxt; i+=1
        elif t.startswith("--port="): port=port or t.split("=",1)[1]
        elif t.startswith("-P") and len(t)>2: port=port or t[2:]
        elif t in ("-u","--user"): user=user or nxt; i+=1
        elif t.startswith("--user="): user=user or t.split("=",1)[1]
        elif t.startswith("-u") and len(t)>2: user=user or t[2:]
        elif t in ("-p","--password"): password=password or nxt; i+=1
        elif t.startswith("--password="): password=password or t.split("=",1)[1]
        elif t.startswith("-p") and len(t)>2: password=password or t[2:]
        i+=1
    break
host=(host or "127.0.0.1").strip("\"\x27")
port=(port or "3306").strip("\"\x27")
user=(user or "root").strip("\"\x27")
password=password.strip("\"\x27")
for k,v in (("MASTER_HOST",host),("MASTER_PORT",port),("MASTER_USER",user),("MASTER_PASS",password)):
    print(f"{k}={shlex.quote(v)}")
')"
    eval "$parsed"
  fi

  if [ -z "$MASTER_PASS" ]; then
    passonly="$(clpctl db:show:master-password 2>&1 || true)"
    passonly="$(printf '%s\n' "$passonly" | sed -r $'s/\x1B\[[0-9;?]*[ -\/]*[@-~]//g' | tail -n1 | tr -d '\r\n')"
    if [ -n "$passonly" ] && [[ ! "$passonly" =~ (Error|Command|not[[:space:]]found|Usage) ]]; then
      MASTER_HOST="${MASTER_HOST:-127.0.0.1}"
      MASTER_PORT="${MASTER_PORT:-3306}"
      MASTER_USER="${MASTER_USER:-root}"
      MASTER_PASS="$passonly"
    fi
  fi

  [ -n "$MASTER_PASS" ] || return 1
  MYSQL_PWD="$MASTER_PASS" mysql --protocol=TCP -h "${MASTER_HOST:-127.0.0.1}" -P "${MASTER_PORT:-3306}" -u "${MASTER_USER:-root}" -NBe 'SELECT 1' >/dev/null 2>&1
}

repair_runtime(){
  [ -f "$SITE/.env" ] || fail ".env ausente."
  [ -f "$SITE/package.json" ] || fail "package.json ausente."
  local stamp dir DB_HOST DB_PORT DB_NAME DB_USER DB_PASS ADMIN_MODE EXISTS NEW_PASS esc
  stamp="$(date +%Y%m%d_%H%M%S)"
  dir="$BACKUP_BASE/runtime-$stamp"
  mkdir -p "$dir"
  cp -a "$SITE/.env" "$dir/.env.before"
  chmod 600 "$dir/.env.before"

  echo "[1/7] PM2 isolado"
  install -d -o "$APP_USER" -g "$APP_GROUP" -m 0750 "/home/$APP_USER/.local" "$PM2_HOME_DIR"
  sudo -u "$APP_USER" -H npm install -g pm2@7 --prefix "/home/$APP_USER/.local" >/dev/null
  [ -x "$PM2_LOCAL" ] || fail "PM2 local nao foi instalado."

  echo "[2/7] Banco existente"
  DB_HOST="$(get_env DB_HOST)"; DB_HOST="${DB_HOST:-127.0.0.1}"
  DB_PORT="$(get_env DB_PORT)"; DB_PORT="${DB_PORT:-3306}"
  DB_NAME="$(get_env DB_NAME)"
  DB_USER="$(get_env DB_USER)"
  DB_PASS="$(get_env DB_PASSWORD)"
  [[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || fail "DB_NAME invalido."
  [[ "$DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || fail "DB_USER invalido."

  app_db_ok(){ MYSQL_PWD="$DB_PASS" mysql --protocol=TCP -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -NBe 'SELECT 1' "$DB_NAME" >/dev/null 2>&1; }

  if ! app_db_ok; then
    ADMIN_MODE=""
    if mysql -NBe 'SELECT 1' >/dev/null 2>&1; then
      ADMIN_MODE="socket-root"
    elif load_cloudpanel_master; then
      ADMIN_MODE="cloudpanel"
    fi
    [ -n "$ADMIN_MODE" ] || fail "Sem acesso administrativo seguro ao MySQL."
    echo "MYSQL_ADMIN_MODE=$ADMIN_MODE"

    mysql_admin(){
      local sql="$1"
      if [ "$ADMIN_MODE" = "socket-root" ]; then mysql -NBe "$sql"; else MYSQL_PWD="$MASTER_PASS" mysql --protocol=TCP -h "$MASTER_HOST" -P "$MASTER_PORT" -u "$MASTER_USER" -NBe "$sql"; fi
    }
    dump_db(){
      if [ "$ADMIN_MODE" = "socket-root" ]; then
        mysqldump --single-transaction --quick --routines --triggers "$DB_NAME"
      else
        MYSQL_PWD="$MASTER_PASS" mysqldump --protocol=TCP -h "$MASTER_HOST" -P "$MASTER_PORT" -u "$MASTER_USER" --single-transaction --quick --routines --triggers "$DB_NAME"
      fi
    }

    EXISTS="$(mysql_admin "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='${DB_NAME}';" | tail -1)"
    if [ "$EXISTS" = "1" ]; then
      dump_db | gzip -9 > "$dir/${DB_NAME}.sql.gz"
      ok "Backup do banco existente criado"
    else
      fail "Banco existente $DB_NAME nao foi localizado. Nada foi recriado."
    fi

    NEW_PASS="$(openssl rand -hex 24)"
    esc="${NEW_PASS//\\/\\\\}"; esc="${esc//\'/\\\'}"
    mysql_admin "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${esc}'; ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${esc}';"
    mysql_admin "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${esc}'; ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${esc}';"
    mysql_admin "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1'; FLUSH PRIVILEGES;"
    DB_HOST="127.0.0.1"; DB_PORT="3306"; DB_PASS="$NEW_PASS"
    set_env DB_HOST "$DB_HOST"; set_env DB_PORT "$DB_PORT"; set_env DB_PASSWORD "$DB_PASS"
    chown "$APP_USER:$APP_GROUP" "$SITE/.env"; chmod 640 "$SITE/.env"
    unset MASTER_PASS NEW_PASS esc
  fi
  app_db_ok || fail "Banco continua sem autenticar."
  echo "DB_AUTH=OK"

  echo "[3/7] Dependencias e migrations"
  chown -R "$APP_USER:$APP_GROUP" "$SITE"
  sudo -u "$APP_USER" -H bash -lc "cd '$SITE' && npm install --omit=dev && npm run migrate"

  echo "[4/7] Testes"
  sudo -u "$APP_USER" -H bash -lc "cd '$SITE' && npm run check"

  echo "[5/7] PM2"
  pm2_user delete belastock >/dev/null 2>&1 || true
  if [ -f "$SITE/ecosystem.config.cjs" ]; then
    pm2_user start "$SITE/ecosystem.config.cjs" --update-env
  else
    pm2_user start npm --name belastock --cwd "$SITE" -- start
  fi
  pm2_user save

  echo "[6/7] Persistencia"
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

  echo "[7/7] Health"
  for i in {1..40}; do health_local >/dev/null 2>&1 && break; sleep 1; done
  health_local || { pm2_user logs belastock --nostream --lines 160 || true; fail "Aplicacao nao respondeu na porta $APP_PORT."; }
  nginx -t
  systemctl reload nginx
  health_origin || fail "Origem HTTPS nao respondeu 200."
  ok "RUNTIME_BELASTOCK=100%_OK"
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
  db-test)
    DB_HOST="$(get_env DB_HOST)"; DB_HOST="${DB_HOST:-127.0.0.1}"; DB_PORT="$(get_env DB_PORT)"; DB_PORT="${DB_PORT:-3306}"; DB_NAME="$(get_env DB_NAME)"; DB_USER="$(get_env DB_USER)"; DB_PASS="$(get_env DB_PASSWORD)"
    echo "DB_HOST=$DB_HOST"; echo "DB_PORT=$DB_PORT"; echo "DB_NAME=$DB_NAME"; echo "DB_USER=$DB_USER"
    MYSQL_PWD="$DB_PASS" mysql --protocol=TCP -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -NBe 'SELECT 1' "$DB_NAME" >/dev/null
    echo "DB_AUTH=OK"
    ;;
  mysql-admin-diagnose)
    echo "CLPCTL=$(command -v clpctl 2>/dev/null || echo ausente)"
    if load_cloudpanel_master; then echo "MASTER_PARSE=OK"; echo "MASTER_HOST=$MASTER_HOST"; echo "MASTER_PORT=$MASTER_PORT"; echo "MASTER_USER=$MASTER_USER"; echo "MASTER_AUTH=OK"; else echo "MASTER_PARSE=FAIL"; fi
    unset MASTER_PASS
    ;;
  runtime-repair) repair_runtime ;;
  nginx-test) nginx -t ;;
  nginx-reload) nginx -t; systemctl reload nginx; systemctl is-active --quiet nginx || fail "Nginx nao ficou ativo." ;;
  pm2-status) pm2_user status ;;
  pm2-restart) pm2_user restart belastock --update-env; pm2_user save; sleep 2; health_local ;;
  inventory)
    echo "=== SITE ==="; ls -la "$SITE" | head -100
    echo "=== VHOST ==="; grep -nE 'server_name|proxy_pass|root |return 301|listen ' "$VHOST" 2>/dev/null || true
    echo "=== PORTS ==="; ss -lntup || true
    ;;
  backup-site)
    stamp="$(date +%Y%m%d_%H%M%S)"; out="$BACKUP_BASE/site-${stamp}.tar.gz"
    tar -C "$(dirname "$SITE")" -czf "$out" "$(basename "$SITE")"; chmod 600 "$out"; echo "BACKUP=$out"
    ;;
  refresh-control)
    tmp="$(mktemp)"; curl -fsSL --retry 3 --connect-timeout 15 "$CONTROL_URL" -o "$tmp"; bash -n "$tmp"; install -o root -g root -m 0755 "$tmp" "$CONTROL_DST"; rm -f "$tmp"; ok "Controlador Bela Stock atualizado do GitHub."
    ;;
  *) fail "Comando nao autorizado: $cmd" ;;
esac
