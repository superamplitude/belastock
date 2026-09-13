#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
APP_GROUP="lojabelastock"
DOMAIN="belastock.com.br"
APP_PORT="3210"
VHOST="/etc/nginx/sites-enabled/belastock.com.br.conf"
PM2_HOME_DIR="/home/${APP_USER}/.pm2"
PM2_LOCAL="/home/${APP_USER}/.local/bin/pm2"
PM2_SERVICE="/etc/systemd/system/pm2-${APP_USER}.service"
PM2_UNIT="pm2-${APP_USER}"
BACKUP_BASE="/root/BELASTOCK_BRIDGE_BACKUPS"
CONTROL_URL="https://raw.githubusercontent.com/superamplitude/belastock/main/deploy/BELASTOCK_VPS_CONTROL.sh"
CONTROL_DST="/usr/local/sbin/belastock-vps-control"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }
[ "$EUID" -eq 0 ] || fail "Este controle deve ser executado como root."
mkdir -p "$BACKUP_BASE"

get_env(){ awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");gsub(/\r/,"");print;exit}' "$SITE/.env"; }
set_env(){ local k="$1" v="$2"; if grep -q "^${k}=" "$SITE/.env"; then sed -i "s#^${k}=.*#${k}=${v}#" "$SITE/.env"; else printf '%s=%s\n' "$k" "$v" >> "$SITE/.env"; fi; }
pm2_bin(){ [ -x "$PM2_LOCAL" ] && { echo "$PM2_LOCAL"; return; }; command -v pm2 2>/dev/null || true; }
pm2_user(){ local p; p="$(pm2_bin)"; [ -n "$p" ] || fail "PM2 nao encontrado."; sudo -u "$APP_USER" -H env PM2_HOME="$PM2_HOME_DIR" PATH="$(dirname "$p"):/usr/local/bin:/usr/bin:/bin" "$p" "$@"; }

health_local(){ local c; c="$(curl -sS --max-time 10 -o /tmp/bs-health-local.json -w '%{http_code}' "http://127.0.0.1:${APP_PORT}/health" || true)"; echo "LOCAL_HEALTH_HTTP=$c"; cat /tmp/bs-health-local.json 2>/dev/null || true; echo; [ "$c" = 200 ]; }
health_origin(){ local c; c="$(curl -ksS --resolve "${DOMAIN}:443:127.0.0.1" --max-time 15 -o /tmp/bs-health-origin.json -w '%{http_code}' "https://${DOMAIN}/health?bridge=$(date +%s)" || true)"; echo "ORIGIN_HEALTH_HTTP=$c"; cat /tmp/bs-health-origin.json 2>/dev/null || true; echo; [ "$c" = 200 ]; }

node_db_ok(){
  local h="$1" p="$2" u="$3" pass="$4" dbname="$5"
  sudo -u "$APP_USER" -H env DBT_HOST="$h" DBT_PORT="$p" DBT_USER="$u" DBT_PASS="$pass" DBT_NAME="$dbname" bash -lc "cd '$SITE' && node --input-type=module -e \"import mysql from 'mysql2/promise'; const c=await mysql.createConnection({host:process.env.DBT_HOST,port:Number(process.env.DBT_PORT),user:process.env.DBT_USER,password:process.env.DBT_PASS,database:process.env.DBT_NAME}); await c.query('SELECT 1'); await c.end();\"" >/dev/null 2>&1
}

write_pm2_service(){
  cat > "$PM2_SERVICE" <<EOF
[Unit]
Description=PM2 Bela Stock
After=network-online.target
Wants=network-online.target
[Service]
Type=forking
User=$APP_USER
Environment=HOME=/home/$APP_USER
Environment=PM2_HOME=$PM2_HOME_DIR
Environment=PATH=/home/$APP_USER/.local/bin:/usr/local/bin:/usr/bin:/bin
PIDFile=$PM2_HOME_DIR/pm2.pid
ExecStart=$PM2_LOCAL resurrect
ExecReload=$PM2_LOCAL reload all
ExecStop=$PM2_LOCAL kill
Restart=on-failure
RestartSec=3
TimeoutStartSec=60
TimeoutStopSec=30
[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$PM2_SERVICE"
  systemctl daemon-reload
}

pm2_service_ensure(){
  [ -x "$PM2_LOCAL" ] || fail "PM2 local ausente: $PM2_LOCAL"
  local stamp backup
  stamp="$(date +%Y%m%d_%H%M%S)"
  if [ -f "$PM2_SERVICE" ]; then
    backup="$BACKUP_BASE/pm2-service-${stamp}.service"
    cp -a "$PM2_SERVICE" "$backup"
    chmod 600 "$backup"
    echo "PM2_SERVICE_BACKUP=$backup"
  fi
  pm2_user save >/dev/null
  write_pm2_service
  systemctl enable "$PM2_UNIT" >/dev/null
  if ! systemctl is-active --quiet "$PM2_UNIT"; then
    systemctl reset-failed "$PM2_UNIT" >/dev/null 2>&1 || true
    if ! systemctl start "$PM2_UNIT"; then
      echo "PM2_SYSTEMD_FIRST_START=FAILED"
      systemctl status "$PM2_UNIT" --no-pager -l || true
      echo "PM2_SYSTEMD_REOWN=BEGIN"
      pm2_user save >/dev/null || true
      pm2_user kill >/dev/null 2>&1 || true
      systemctl reset-failed "$PM2_UNIT" >/dev/null 2>&1 || true
      systemctl start "$PM2_UNIT"
    fi
  fi
  systemctl is-enabled --quiet "$PM2_UNIT" || fail "Servico PM2 nao ficou habilitado."
  systemctl is-active --quiet "$PM2_UNIT" || { systemctl status "$PM2_UNIT" --no-pager -l || true; fail "Servico PM2 nao ficou ativo."; }
  echo "PM2_SYSTEMD_ENABLED=YES"
  echo "PM2_SYSTEMD_ACTIVE=YES"
  pm2_user status
  for i in {1..30}; do health_local >/dev/null 2>&1 && break; sleep 1; done
  health_local || fail "Aplicacao nao recuperou health apos ownership pelo systemd."
  ok "PM2_SYSTEMD_PERSISTENCE=100%_OK"
}

MASTER_HOST=""; MASTER_PORT=""; MASTER_USER=""; MASTER_PASS=""
load_cloudpanel_master(){
  command -v clpctl >/dev/null 2>&1 || return 1
  local raw parsed
  raw="$(clpctl db:show:master-credentials 2>&1 || true)"; [ -n "$raw" ] || return 1
  parsed="$(printf '%s\n' "$raw" | python3 -c '
import sys,re,shlex
text=sys.stdin.read(); text=re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", text)
text=text.replace("│"," ").replace("┃"," ").replace("║"," ").replace("|"," ")
lines=[x.strip() for x in text.splitlines() if x.strip()]
host=port=user=password=""
def pick(label,line):
    m=re.search(r"(?:^|\s)"+label+r"\s*(?::|=|\s)\s*(\S+)",line,re.I)
    return m.group(1).strip("\"\x27") if m else ""
for line in lines:
    host=host or pick(r"Host",line); port=port or pick(r"Port",line)
    user=user or pick(r"User\s*Name",line) or pick(r"Username",line); password=password or pick(r"Password",line)
for line in lines:
    pos=line.lower().find("mysql ")
    if pos<0: continue
    try: a=shlex.split(line[pos:])
    except Exception: a=line[pos:].split()
    i=0
    while i<len(a):
        t=a[i]; n=a[i+1] if i+1<len(a) else ""
        if t in ("-h","--host"): host=host or n; i+=1
        elif t.startswith("--host="): host=host or t.split("=",1)[1]
        elif t.startswith("-h") and len(t)>2: host=host or t[2:]
        elif t in ("-P","--port"): port=port or n; i+=1
        elif t.startswith("--port="): port=port or t.split("=",1)[1]
        elif t.startswith("-P") and len(t)>2: port=port or t[2:]
        elif t in ("-u","--user"): user=user or n; i+=1
        elif t.startswith("--user="): user=user or t.split("=",1)[1]
        elif t.startswith("-u") and len(t)>2: user=user or t[2:]
        elif t in ("-p","--password"): password=password or n; i+=1
        elif t.startswith("--password="): password=password or t.split("=",1)[1]
        elif t.startswith("-p") and len(t)>2: password=password or t[2:]
        i+=1
    break
host=(host or "127.0.0.1").strip("\"\x27"); port=(port or "3306").strip("\"\x27")
user=(user or "root").strip("\"\x27"); password=password.strip("\"\x27")
for k,v in (("MASTER_HOST",host),("MASTER_PORT",port),("MASTER_USER",user),("MASTER_PASS",password)): print(f"{k}={shlex.quote(v)}")
')"
  eval "$parsed"; [ -n "$MASTER_PASS" ] || return 1
  MYSQL_PWD="$MASTER_PASS" mysql --protocol=TCP -h "$MASTER_HOST" -P "$MASTER_PORT" -u "$MASTER_USER" -NBe 'SELECT 1' >/dev/null 2>&1
}

runtime_repair(){
  [ -f "$SITE/.env" ] || fail ".env ausente."; [ -f "$SITE/package.json" ] || fail "package.json ausente."
  local stamp dir DB_HOST DB_PORT DB_NAME DB_USER DB_PASS ADMIN_MODE EXISTS NEW_PASS ALT_USER ALT_PASS
  stamp="$(date +%Y%m%d_%H%M%S)"; dir="$BACKUP_BASE/runtime-$stamp"; mkdir -p "$dir"; cp -a "$SITE/.env" "$dir/.env.before"; chmod 600 "$dir/.env.before"

  echo "[1/7] PM2 isolado"
  install -d -o "$APP_USER" -g "$APP_GROUP" -m 0750 "/home/$APP_USER/.local" "$PM2_HOME_DIR"
  sudo -u "$APP_USER" -H npm install -g pm2@7 --prefix "/home/$APP_USER/.local" >/dev/null
  [ -x "$PM2_LOCAL" ] || fail "PM2 local nao instalado."

  echo "[2/7] Banco Node canonical / validacao mysql2 runtime"
  DB_HOST="$(get_env DB_HOST)"; DB_HOST="${DB_HOST:-127.0.0.1}"; DB_PORT="$(get_env DB_PORT)"; DB_PORT="${DB_PORT:-3306}"
  DB_NAME="$(get_env DB_NAME)"; DB_USER="$(get_env DB_USER)"; DB_PASS="$(get_env DB_PASSWORD)"
  [[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || fail "DB_NAME invalido."; [[ "$DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || fail "DB_USER invalido."

  if ! node_db_ok "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME"; then
    ADMIN_MODE=""; if mysql -NBe 'SELECT 1' >/dev/null 2>&1; then ADMIN_MODE="socket-root"; elif load_cloudpanel_master; then ADMIN_MODE="cloudpanel"; fi
    [ -n "$ADMIN_MODE" ] || fail "Sem acesso administrativo seguro ao MySQL."; echo "MYSQL_ADMIN_MODE=$ADMIN_MODE"
    mysql_admin(){ local q="$1"; if [ "$ADMIN_MODE" = socket-root ]; then mysql -NBe "$q"; else MYSQL_PWD="$MASTER_PASS" mysql --protocol=TCP -h "$MASTER_HOST" -P "$MASTER_PORT" -u "$MASTER_USER" -NBe "$q"; fi; }
    dump_db(){ if [ "$ADMIN_MODE" = socket-root ]; then mysqldump --single-transaction --quick --routines --triggers "$DB_NAME"; else MYSQL_PWD="$MASTER_PASS" mysqldump --protocol=TCP -h "$MASTER_HOST" -P "$MASTER_PORT" -u "$MASTER_USER" --single-transaction --quick --routines --triggers "$DB_NAME"; fi; }

    EXISTS="$(mysql_admin "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='${DB_NAME}';" | tail -1)"
    if [ "$EXISTS" = 1 ]; then dump_db | gzip -9 > "$dir/${DB_NAME}.sql.gz" || true; ok "Banco existente preservado em backup"; else mysql_admin "CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; ok "Banco $DB_NAME criado sem sobrescrever banco existente"; fi

    NEW_PASS="$(openssl rand -hex 24)"
    mysql_admin "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${NEW_PASS}'; ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${NEW_PASS}';"
    mysql_admin "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${NEW_PASS}'; ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${NEW_PASS}';"
    mysql_admin "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1'; FLUSH PRIVILEGES;"
    DB_HOST="127.0.0.1"; DB_PORT="3306"; DB_PASS="$NEW_PASS"; set_env DB_HOST "$DB_HOST"; set_env DB_PORT "$DB_PORT"; set_env DB_PASSWORD "$DB_PASS"; chown "$APP_USER:$APP_GROUP" "$SITE/.env"; chmod 640 "$SITE/.env"

    if ! node_db_ok "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME"; then
      echo "[DB] conta legada nao autenticou no mysql2; criando usuario dedicado limpo"
      ALT_USER="belastockapp"; ALT_PASS="$(openssl rand -hex 24)"
      mysql_admin "CREATE USER IF NOT EXISTS '${ALT_USER}'@'localhost' IDENTIFIED BY '${ALT_PASS}'; ALTER USER '${ALT_USER}'@'localhost' IDENTIFIED BY '${ALT_PASS}';"
      mysql_admin "CREATE USER IF NOT EXISTS '${ALT_USER}'@'127.0.0.1' IDENTIFIED BY '${ALT_PASS}'; ALTER USER '${ALT_USER}'@'127.0.0.1' IDENTIFIED BY '${ALT_PASS}';"
      mysql_admin "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${ALT_USER}'@'localhost'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${ALT_USER}'@'127.0.0.1'; FLUSH PRIVILEGES;"
      DB_USER="$ALT_USER"; DB_PASS="$ALT_PASS"; set_env DB_USER "$DB_USER"; set_env DB_PASSWORD "$DB_PASS"; chown "$APP_USER:$APP_GROUP" "$SITE/.env"; chmod 640 "$SITE/.env"
    fi

    node_db_ok "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME" || fail "mysql2 tambem nao conseguiu autenticar no banco."
    unset MASTER_PASS NEW_PASS ALT_PASS
  fi
  echo "DB_AUTH_MYSQL2=OK DB_NAME=$DB_NAME DB_USER=$DB_USER"

  echo "[3/7] Dependencias e migrations"
  chown -R "$APP_USER:$APP_GROUP" "$SITE"
  sudo -u "$APP_USER" -H bash -lc "cd '$SITE' && npm install --omit=dev && npm run migrate"

  echo "[4/7] Testes"
  sudo -u "$APP_USER" -H bash -lc "cd '$SITE' && npm run check"

  echo "[5/7] PM2"
  pm2_user delete belastock >/dev/null 2>&1 || true
  if [ -f "$SITE/ecosystem.config.cjs" ]; then pm2_user start "$SITE/ecosystem.config.cjs" --update-env; else pm2_user start npm --name belastock --cwd "$SITE" -- start; fi
  pm2_user save

  echo "[6/7] Persistencia"
  pm2_service_ensure

  echo "[7/7] Health"
  for i in {1..40}; do health_local >/dev/null 2>&1 && break; sleep 1; done
  health_local || { pm2_user logs belastock --nostream --lines 160 || true; fail "Aplicacao nao respondeu na porta $APP_PORT."; }
  nginx -t; systemctl reload nginx
  ok "RUNTIME_BELASTOCK=LOCAL_100%_OK"
}

nginx_diagnose(){
  echo "BELASTOCK_NGINX_DIAG_V1"
  echo "===== LOCAL APP ====="; health_local || true
  echo "===== PORT 3210 ====="; ss -lntp | grep ":${APP_PORT}" || true
  echo "===== EXPECTED VHOST ====="; echo "VHOST=$VHOST"; ls -la "$VHOST" 2>&1 || true; readlink -f "$VHOST" 2>&1 || true
  echo "===== VHOST CONTENT ====="; sed -n '1,360p' "$VHOST" 2>&1 || true
  echo "===== ACTIVE BELASTOCK CONFIG REFERENCES ====="; grep -RniE 'server_name[[:space:]].*(www\.)?belastock\.com\.br|proxy_pass[[:space:]]+http' /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null || true
  echo "===== NGINX -T BELASTOCK CONTEXT ====="; nginx -T 2>&1 | awk 'BEGIN{show=0;n=0} /belastock\.com\.br/{show=1;n=0} show{print;n++} n>80{show=0}' || true
  echo "===== ORIGIN ====="; health_origin || true
  echo "===== ERROR LOGS ====="; for f in /var/log/nginx/error.log /home/$APP_USER/logs/nginx/error.log /home/$APP_USER/logs/*error*.log; do [ -f "$f" ] && { echo "--- $f"; tail -n 120 "$f"; }; done
}

nginx_repair(){
  echo "BELASTOCK_NGINX_REPAIR_V2"
  [ -f "$VHOST" ] || fail "Vhost Bela Stock ausente: $VHOST"
  health_local || fail "App local nao esta saudavel em 127.0.0.1:${APP_PORT}."
  local stamp backup old_count new_count origin_root public_health www_code www_location origin_ok code i
  stamp="$(date +%Y%m%d_%H%M%S)"; backup="$BACKUP_BASE/belastock-vhost-${stamp}.conf"
  cp -a "$VHOST" "$backup"; chmod 600 "$backup"; echo "VHOST_BACKUP=$backup"

  old_count="$(grep -Ec 'proxy_pass[[:space:]]+http://127\.0\.0\.1:3003/;' "$VHOST" || true)"
  new_count="$(grep -Ec "proxy_pass[[:space:]]+http://127\\.0\\.0\\.1:${APP_PORT}/;" "$VHOST" || true)"
  echo "UPSTREAM_OLD_3003_COUNT=$old_count"
  echo "UPSTREAM_CANONICAL_${APP_PORT}_COUNT=$new_count"

  if [ "$new_count" -eq 1 ] && [ "$old_count" -eq 0 ]; then
    echo "VHOST_CHANGE=ALREADY_CANONICAL"
  elif [ "$old_count" -eq 1 ] && [ "$new_count" -eq 0 ]; then
    sed -i "s#proxy_pass http://127.0.0.1:3003/;#proxy_pass http://127.0.0.1:${APP_PORT}/;#" "$VHOST"
    echo "VHOST_CHANGE=3003_TO_${APP_PORT}"
  else
    fail "Estado de upstream inesperado; nenhuma alteracao aplicada."
  fi

  grep -q "proxy_pass http://127.0.0.1:${APP_PORT}/;" "$VHOST" || { cp -a "$backup" "$VHOST"; fail "Upstream canonical nao persistiu; vhost restaurado."; }
  nginx -t || { cp -a "$backup" "$VHOST"; nginx -t || true; fail "nginx -t rejeitou a configuracao; vhost restaurado."; }

  echo "NGINX_EFFECTIVE_PROXY_BEFORE_RELOAD=$(grep -Eo 'proxy_pass[[:space:]]+http://127\.0\.0\.1:[0-9]+/' "$VHOST" | head -1)"
  systemctl reload nginx
  systemctl is-active --quiet nginx || { cp -a "$backup" "$VHOST"; nginx -t && systemctl reload nginx; fail "Nginx nao permaneceu ativo; rollback aplicado."; }

  origin_ok=0
  for i in $(seq 1 30); do
    code="$(curl -ksS --resolve "${DOMAIN}:443:127.0.0.1" --max-time 5 -o /tmp/bs-health-origin.json -w '%{http_code}' "https://${DOMAIN}/health?reload=${i}-$(date +%s%N)" || true)"
    echo "ORIGIN_RELOAD_CHECK_${i}=$code"
    if [ "$code" = 200 ]; then origin_ok=1; break; fi
    sleep 1
  done

  if [ "$origin_ok" != 1 ]; then
    echo "===== FAILURE EVIDENCE BEFORE ROLLBACK ====="
    echo "VHOST_PROXY_NOW=$(grep -Eo 'proxy_pass[[:space:]]+http://127\.0\.0\.1:[0-9]+/' "$VHOST" | head -1)"
    ss -lntp | grep ":${APP_PORT}" || true
    tail -n 60 "/home/$APP_USER/logs/nginx/error.log" 2>/dev/null || true
    cp -a "$backup" "$VHOST"
    nginx -t && systemctl reload nginx
    fail "Origem permaneceu sem health 200 apos 30s; evidencia capturada e rollback aplicado."
  fi

  echo "ORIGIN_HEALTH_HTTP=200"
  cat /tmp/bs-health-origin.json 2>/dev/null || true; echo
  origin_root="$(curl -ksS --resolve "${DOMAIN}:443:127.0.0.1" --max-time 15 -o /tmp/bs-origin-root.html -w '%{http_code}' "https://${DOMAIN}/" || true)"
  echo "ORIGIN_ROOT_HTTP=$origin_root"
  [[ "$origin_root" =~ ^(200|301|302)$ ]] || fail "Raiz da origem nao retornou 200/301/302."

  www_code="$(curl -ksS --resolve "www.${DOMAIN}:443:127.0.0.1" --max-time 15 -o /dev/null -D /tmp/bs-www.headers -w '%{http_code}' "https://www.${DOMAIN}/" || true)"
  www_location="$(awk 'BEGIN{IGNORECASE=1}/^location:/{sub(/\r$/,"");print $2;exit}' /tmp/bs-www.headers 2>/dev/null || true)"
  echo "WWW_HTTP=$www_code WWW_LOCATION=${www_location:-none}"
  [ "$www_code" = 301 ] || fail "WWW nao esta redirecionando com 301."

  public_health="$(curl -ksS --max-time 20 -o /tmp/bs-public-health.json -w '%{http_code}' "https://${DOMAIN}/health?public=$(date +%s)" || true)"
  echo "PUBLIC_HEALTH_HTTP=$public_health"; cat /tmp/bs-public-health.json 2>/dev/null || true; echo
  [ "$public_health" = 200 ] || fail "Publico ainda nao respondeu health 200."

  echo "VHOST_UPSTREAM_FINAL=$(grep -Eo 'proxy_pass[[:space:]]+http://127\.0\.0\.1:[0-9]+/' "$VHOST" | head -1)"
  ok "ORIGIN_BELASTOCK=100%_OK"
  ok "PUBLICO_BELASTOCK=100%_OK"
  ok "NGINX_ROOT_CAUSE_FIXED=3003_TO_${APP_PORT}"
}

cmd="${1:-status}"
case "$cmd" in
  runtime-repair) runtime_repair ;;
  pm2-service-ensure) pm2_service_ensure ;;
  health) health_local; health_origin ;;
  db-test)
    h="$(get_env DB_HOST)"; h="${h:-127.0.0.1}"; p="$(get_env DB_PORT)"; p="${p:-3306}"; u="$(get_env DB_USER)"; pass="$(get_env DB_PASSWORD)"; d="$(get_env DB_NAME)"
    echo "DB_HOST=$h DB_PORT=$p DB_NAME=$d DB_USER=$u"; node_db_ok "$h" "$p" "$u" "$pass" "$d"; echo "DB_AUTH_MYSQL2=OK"
    ;;
  nginx-diagnose) nginx_diagnose ;;
  nginx-repair) nginx_repair ;;
  status)
    echo "BELASTOCK_SITE=$SITE BELASTOCK_PORT=$APP_PORT HOST=$(hostname) DATE=$(date -Is)"; echo "NODE=$(node -v 2>/dev/null || echo ausente) NPM=$(npm -v 2>/dev/null || echo ausente) PM2=$(pm2_bin)"
    nginx -t; systemctl is-active nginx || true; ss -lntp | grep -E ":(80|443|${APP_PORT})[[:space:]]" || true; pm2_user status || true; systemctl is-enabled "$PM2_UNIT" 2>/dev/null || true; systemctl is-active "$PM2_UNIT" 2>/dev/null || true; health_local || true; health_origin || true
    ;;
  inventory) echo "=== SITE ==="; ls -la "$SITE" | head -100; echo "=== VHOST ==="; grep -nE 'server_name|proxy_pass|root |listen ' "$VHOST" 2>/dev/null || true; echo "=== PORTS ==="; ss -lntup || true ;;
  backup-site) stamp="$(date +%Y%m%d_%H%M%S)"; out="$BACKUP_BASE/site-${stamp}.tar.gz"; tar -C "$(dirname "$SITE")" -czf "$out" "$(basename "$SITE")"; chmod 600 "$out"; echo "BACKUP=$out" ;;
  refresh-control) tmp="$(mktemp)"; curl -fsSL --retry 3 --connect-timeout 15 "$CONTROL_URL" -o "$tmp"; bash -n "$tmp"; install -o root -g root -m 0755 "$tmp" "$CONTROL_DST"; rm -f "$tmp"; ok "Controlador Bela Stock atualizado do GitHub." ;;
  nginx-test) nginx -t ;;
  nginx-reload) nginx -t; systemctl reload nginx ;;
  pm2-status) pm2_user status ;;
  pm2-restart)
    pm2_user restart belastock --update-env
    pm2_user save
    restart_ok=0
    for i in $(seq 1 30); do
      if health_local >/dev/null 2>&1; then restart_ok=1; break; fi
      sleep 1
    done
    if [ "$restart_ok" != 1 ]; then
      pm2_user logs belastock --nostream --lines 120 || true
      fail "Aplicacao nao recuperou health apos restart PM2."
    fi
    health_local
    ;;
  *) fail "Comando nao autorizado: $cmd" ;;
esac
