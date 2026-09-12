#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

APP_DIR="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
APP_GROUP="lojabelastock"
DOMAIN="belastock.com.br"
WWW_DOMAIN="www.belastock.com.br"
APP_PORT_DEFAULT="3210"
VHOST="/etc/nginx/sites-enabled/belastock.com.br.conf"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="/home/lojabelastock/backups/recovery-total-$STAMP"
LOG_FILE="/root/BELASTOCK_RECOVERY_TOTAL_${STAMP}.log"
PM2_SERVICE="/etc/systemd/system/pm2-${APP_USER}.service"

mkdir -p "$BACKUP_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

say(){ printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
fail(){
  local rc=$?
  echo
  echo "============================================================"
  echo "BELA STOCK - FALHA NO RECOVERY TOTAL"
  echo "codigo=$rc linha=${BASH_LINENO[0]}"
  echo "backup=$BACKUP_DIR"
  echo "log=$LOG_FILE"
  echo "============================================================"
  exit "$rc"
}
trap fail ERR

[[ $EUID -eq 0 ]] || { echo "ERRO: execute como root"; exit 1; }
id "$APP_USER" >/dev/null 2>&1 || { echo "ERRO: usuario $APP_USER nao existe"; exit 2; }
[[ -d "$APP_DIR" ]] || { echo "ERRO: diretorio ausente: $APP_DIR"; exit 3; }
[[ -f "$APP_DIR/package.json" ]] || { echo "ERRO: package.json ausente"; exit 4; }
[[ -f "$APP_DIR/.env" ]] || { echo "ERRO: .env ausente"; exit 5; }

say "Inventario e backup antes de qualquer alteracao"
cp -a "$APP_DIR/.env" "$BACKUP_DIR/.env.before"
cp -a "$APP_DIR/package.json" "$BACKUP_DIR/package.json"
[[ -f "$APP_DIR/ecosystem.config.cjs" ]] && cp -a "$APP_DIR/ecosystem.config.cjs" "$BACKUP_DIR/ecosystem.config.cjs"
[[ -f "$VHOST" ]] && cp -a "$VHOST" "$BACKUP_DIR/belastock.com.br.conf.before"
nginx -T > "$BACKUP_DIR/nginx-T.before.txt" 2>&1 || true
ss -lntup > "$BACKUP_DIR/ports.before.txt" 2>&1 || true

say "Garantindo ferramentas necessarias"
for cmd in curl node npm nginx mysql mysqldump sudo ss systemctl awk sed grep openssl gzip; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERRO: comando ausente: $cmd"; exit 6; }
done
if ! command -v pm2 >/dev/null 2>&1; then
  npm install -g pm2@latest >/dev/null
fi
PM2_BIN="$(command -v pm2)"
NPM_BIN="$(command -v npm)"
PM2_HOME_DIR="/home/$APP_USER/.pm2"
install -d -m 750 -o "$APP_USER" -g "$APP_GROUP" "$PM2_HOME_DIR"

pm2_user(){ sudo -u "$APP_USER" -H env PM2_HOME="$PM2_HOME_DIR" "$PM2_BIN" "$@"; }
npm_user(){ sudo -u "$APP_USER" -H env HOME="/home/$APP_USER" "$NPM_BIN" "$@"; }

env_get(){ awk -v k="$1" 'index($0,k"=")==1{sub("^[^=]*=",""); print; exit}' "$APP_DIR/.env"; }
APP_PORT="$(env_get PORT | tr -d '[:space:]\r\n')"
[[ "$APP_PORT" =~ ^[0-9]{2,5}$ ]] || APP_PORT="$APP_PORT_DEFAULT"

say "Normalizando configuracao oficial da aplicacao"
if grep -q '^HOST=' "$APP_DIR/.env"; then sed -i 's/^HOST=.*/HOST=127.0.0.1/' "$APP_DIR/.env"; else echo 'HOST=127.0.0.1' >> "$APP_DIR/.env"; fi
if grep -q '^PORT=' "$APP_DIR/.env"; then sed -i "s/^PORT=.*/PORT=$APP_PORT/" "$APP_DIR/.env"; else echo "PORT=$APP_PORT" >> "$APP_DIR/.env"; fi
if grep -q '^APP_URL=' "$APP_DIR/.env"; then sed -i 's#^APP_URL=.*#APP_URL=https://belastock.com.br#' "$APP_DIR/.env"; else echo 'APP_URL=https://belastock.com.br' >> "$APP_DIR/.env"; fi
chown "$APP_USER:$APP_GROUP" "$APP_DIR/.env"
chmod 640 "$APP_DIR/.env"

say "Verificando conflito da porta $APP_PORT"
LISTENER_PID="$(ss -lntp 2>/dev/null | awk -v p=":$APP_PORT" '$4 ~ p {if(match($0,/pid=([0-9]+)/,m)) print m[1]}' | head -1 || true)"
if [[ -n "$LISTENER_PID" ]]; then
  LISTENER_CWD="$(readlink -f "/proc/$LISTENER_PID/cwd" 2>/dev/null || true)"
  LISTENER_CMD="$(tr '\0' ' ' < "/proc/$LISTENER_PID/cmdline" 2>/dev/null || true)"
  if [[ "$LISTENER_CWD" == "$APP_DIR"* || "$LISTENER_CMD" == *"$APP_DIR"* ]]; then
    echo "Encerrando processo antigo do proprio Bela Stock: PID=$LISTENER_PID"
    kill "$LISTENER_PID" || true
    sleep 2
  else
    echo "ERRO: porta $APP_PORT ocupada por outro processo."
    echo "PID=$LISTENER_PID CWD=$LISTENER_CWD CMD=$LISTENER_CMD"
    exit 30
  fi
fi

say "Reparando dependencias Node"
cd "$APP_DIR"
npm_user install --omit=dev

has_script(){ node -e "const p=require('./package.json');process.exit(p.scripts&&p.scripts['$1']?0:1)"; }
if has_script check; then
  say "Executando validacao interna npm run check"
  npm_user run check
fi

say "Validando e reparando banco configurado no .env"
DB_HOST="$(env_get DB_HOST)"
DB_PORT="$(env_get DB_PORT)"
DB_NAME="$(env_get DB_NAME)"
DB_USER="$(env_get DB_USER)"
DB_PASS="$(env_get DB_PASSWORD)"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"

[[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || { echo "ERRO: DB_NAME invalido"; exit 31; }
[[ "$DB_USER" =~ ^[A-Za-z0-9_]+$ ]] || { echo "ERRO: DB_USER invalido"; exit 31; }
[[ "$DB_PORT" =~ ^[0-9]+$ ]] || { echo "ERRO: DB_PORT invalido"; exit 31; }

app_db_ok(){ MYSQL_PWD="$DB_PASS" mysql --protocol=TCP -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -NBe 'SELECT 1' "$DB_NAME" >/dev/null 2>&1; }

sql_escape(){
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\'/\\\'}"
  printf '%s' "$s"
}

ADMIN_MODE=""
MASTER_HOST=""
MASTER_PORT=""
MASTER_USER=""
MASTER_PASS=""

mysql_admin_sql(){
  local sql="$1"
  if [[ "$ADMIN_MODE" == "socket-root" ]]; then
    mysql -NBe "$sql"
  elif [[ "$ADMIN_MODE" == "cloudpanel" ]]; then
    MYSQL_PWD="$MASTER_PASS" mysql --protocol=TCP -h "$MASTER_HOST" -P "$MASTER_PORT" -u "$MASTER_USER" -NBe "$sql"
  else
    return 1
  fi
}

if ! app_db_ok; then
  echo "Credenciais atuais da aplicacao nao autenticam. Iniciando reparo nao destrutivo do usuario MySQL."

  if mysql -NBe 'SELECT 1' >/dev/null 2>&1; then
    ADMIN_MODE="socket-root"
  elif command -v clpctl >/dev/null 2>&1; then
    MASTER_RAW="$(clpctl db:show:master-credentials 2>/dev/null || true)"
    MASTER_CLEAN="$(printf '%s\n' "$MASTER_RAW" | sed -r $'s/\\x1B\\[[0-9;]*[mK]//g')"
    MASTER_HOST="$(printf '%s\n' "$MASTER_CLEAN" | sed -nE 's/^[[:space:]]*Host[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$/\1/ip' | head -1)"
    MASTER_PORT="$(printf '%s\n' "$MASTER_CLEAN" | sed -nE 's/^[[:space:]]*Port[[:space:]]*:[[:space:]]*([0-9]+).*$/\1/ip' | head -1)"
    MASTER_USER="$(printf '%s\n' "$MASTER_CLEAN" | sed -nE 's/^[[:space:]]*(User Name|Username|User)[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$/\2/ip' | head -1)"
    MASTER_PASS="$(printf '%s\n' "$MASTER_CLEAN" | sed -nE 's/^[[:space:]]*Password[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$/\1/ip' | head -1)"
    MASTER_HOST="${MASTER_HOST:-127.0.0.1}"
    MASTER_PORT="${MASTER_PORT:-3306}"
    if [[ -n "$MASTER_USER" && -n "$MASTER_PASS" ]] && MYSQL_PWD="$MASTER_PASS" mysql --protocol=TCP -h "$MASTER_HOST" -P "$MASTER_PORT" -u "$MASTER_USER" -NBe 'SELECT 1' >/dev/null 2>&1; then
      ADMIN_MODE="cloudpanel"
    fi
    unset MASTER_RAW MASTER_CLEAN
  fi

  [[ -n "$ADMIN_MODE" ]] || { echo "ERRO: nao foi possivel obter acesso administrativo seguro ao MySQL."; exit 32; }
  echo "MySQL admin mode: $ADMIN_MODE"

  DB_EXISTS="$(mysql_admin_sql "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$DB_NAME';" | tail -1)"
  if [[ "$DB_EXISTS" == "1" ]]; then
    if [[ "$ADMIN_MODE" == "socket-root" ]]; then
      mysqldump --single-transaction --quick --routines --triggers "$DB_NAME" | gzip -c > "$BACKUP_DIR/${DB_NAME}.before.sql.gz" || true
    else
      MYSQL_PWD="$MASTER_PASS" mysqldump --protocol=TCP -h "$MASTER_HOST" -P "$MASTER_PORT" -u "$MASTER_USER" --single-transaction --quick --routines --triggers "$DB_NAME" | gzip -c > "$BACKUP_DIR/${DB_NAME}.before.sql.gz" || true
    fi
  fi

  PASS_SQL="$(sql_escape "$DB_PASS")"
  mysql_admin_sql "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  mysql_admin_sql "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$PASS_SQL';"
  mysql_admin_sql "ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$PASS_SQL';"
  mysql_admin_sql "CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$PASS_SQL';"
  mysql_admin_sql "ALTER USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$PASS_SQL';"
  mysql_admin_sql "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
  mysql_admin_sql "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';"
  mysql_admin_sql "FLUSH PRIVILEGES;"

  if ! app_db_ok; then
    echo "ERRO: credencial MySQL foi reparada, mas a aplicacao ainda nao consegue autenticar."
    exit 33
  fi
  echo "Banco/usuario MySQL reparados e validados."
  unset PASS_SQL MASTER_PASS
fi

MYSQL_PWD="$DB_PASS" mysql --protocol=TCP -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -NBe "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" > "$BACKUP_DIR/db-table-count.txt"

if has_script migrate; then
  say "Executando migrations idempotentes"
  npm_user run migrate
fi

say "Recriando processo PM2 do Bela Stock com caminho absoluto"
pm2_user delete belastock >/dev/null 2>&1 || true
if [[ -f "$APP_DIR/ecosystem.config.cjs" ]]; then
  pm2_user start "$APP_DIR/ecosystem.config.cjs" --update-env
else
  if ! has_script start; then
    echo "ERRO: ecosystem.config.cjs ausente e package.json nao possui script start."
    exit 34
  fi
  pm2_user start "$NPM_BIN" --name belastock --cwd "$APP_DIR" -- start
fi
pm2_user save

say "Aguardando healthcheck local"
LOCAL_OK=0
for i in {1..40}; do
  if curl -fsS --connect-timeout 2 --max-time 5 "http://127.0.0.1:$APP_PORT/health" > "$BACKUP_DIR/health-local.json" 2>/dev/null; then
    LOCAL_OK=1
    break
  fi
  sleep 1
done
if (( ! LOCAL_OK )); then
  echo "ERRO: aplicacao nao respondeu em 127.0.0.1:$APP_PORT/health."
  pm2_user status || true
  pm2_user logs belastock --nostream --lines 200 || true
  ss -lntup | grep ":$APP_PORT" || true
  exit 35
fi

say "Criando inicializacao automatica do PM2 no boot"
cat > "$PM2_SERVICE" <<PM2UNIT
[Unit]
Description=PM2 process manager for $APP_USER
After=network.target mariadb.service mysql.service
Wants=network-online.target

[Service]
Type=forking
User=$APP_USER
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=PM2_HOME=$PM2_HOME_DIR
PIDFile=$PM2_HOME_DIR/pm2.pid
Restart=on-failure
ExecStart=$PM2_BIN resurrect
ExecReload=$PM2_BIN reload all
ExecStop=$PM2_BIN kill

[Install]
WantedBy=multi-user.target
PM2UNIT
systemctl daemon-reload
systemctl enable "pm2-${APP_USER}.service" >/dev/null

say "Validando certificado SSL"
CRT="/etc/nginx/ssl-certificates/belastock.com.br.crt"
KEY="/etc/nginx/ssl-certificates/belastock.com.br.key"
[[ -s "$CRT" && -s "$KEY" ]] || { echo "ERRO: certificado/chave SSL ausentes"; exit 36; }
openssl x509 -in "$CRT" -noout -subject -issuer -dates > "$BACKUP_DIR/certificate.txt"

say "Aplicando vhost Nginx oficial"
cat > "$VHOST.new" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN $WWW_DOMAIN;
    return 301 https://$DOMAIN\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name $WWW_DOMAIN;
    ssl_certificate $CRT;
    ssl_certificate_key $KEY;
    return 301 https://$DOMAIN\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name $DOMAIN;
    ssl_certificate $CRT;
    ssl_certificate_key $KEY;
    access_log /home/lojabelastock/logs/nginx/access.log main;
    error_log /home/lojabelastock/logs/nginx/error.log;
    client_max_body_size 25m;

    location = /cgi-sys/suspendedpage.cgi {
        return 301 https://$DOMAIN/;
    }

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";
        proxy_read_timeout 90s;
        proxy_connect_timeout 10s;
    }
}
NGINX
cp "$VHOST.new" "$VHOST"
rm -f "$VHOST.new"
if ! nginx -t; then
  echo "ERRO: Nginx rejeitou novo vhost. Restaurando backup."
  [[ -f "$BACKUP_DIR/belastock.com.br.conf.before" ]] && cp -a "$BACKUP_DIR/belastock.com.br.conf.before" "$VHOST"
  nginx -t || true
  exit 37
fi
systemctl reload nginx
sleep 2

say "Auditoria final ponta a ponta"
LOCAL_HEALTH="$(curl -sS -o "$BACKUP_DIR/local-health-final.json" -w '%{http_code}' "http://127.0.0.1:$APP_PORT/health" || true)"
ORIGIN_HEALTH="$(curl -k -sS -o "$BACKUP_DIR/origin-health-final.json" -w '%{http_code}' --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/health" || true)"
ORIGIN_HOME="$(curl -k -sS -o "$BACKUP_DIR/origin-home-final.html" -w '%{http_code}' --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/" || true)"
LEGACY_CODE="$(curl -k -sS -o /dev/null -w '%{http_code}' --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/cgi-sys/suspendedpage.cgi" || true)"
PUBLIC_HEALTH="$(curl -sS -o "$BACKUP_DIR/public-health-final.txt" -w '%{http_code}' "https://$DOMAIN/health" || true)"
PUBLIC_HOME="$(curl -sS -o "$BACKUP_DIR/public-home-final.html" -w '%{http_code}' "https://$DOMAIN/" || true)"
WWW_CODE="$(curl -sS -o /dev/null -w '%{http_code}' "https://$WWW_DOMAIN/" || true)"

pm2_user status belastock || true
ss -lntp | grep -E ":$APP_PORT[[:space:]]" || true

DB_TABLES="$(cat "$BACKUP_DIR/db-table-count.txt" 2>/dev/null || echo '?')"
printf '\n============================================================\n'
printf ' BELA STOCK - AUDITORIA FINAL\n'
printf '============================================================\n'
printf 'Node: %s\n' "$(node -v)"
printf 'npm: %s\n' "$(npm -v)"
printf 'PM2: %s\n' "$($PM2_BIN -v)"
printf 'Porta: %s\n' "$APP_PORT"
printf 'Banco: OK (%s tabelas)\n' "$DB_TABLES"
printf 'Local /health: %s\n' "$LOCAL_HEALTH"
printf 'Origin /health: %s\n' "$ORIGIN_HEALTH"
printf 'Origin /: %s\n' "$ORIGIN_HOME"
printf 'Legacy suspendedpage: %s\n' "$LEGACY_CODE"
printf 'Public /health: %s\n' "$PUBLIC_HEALTH"
printf 'Public /: %s\n' "$PUBLIC_HOME"
printf 'WWW: %s\n' "$WWW_CODE"
printf 'Backup: %s\n' "$BACKUP_DIR"
printf 'Log: %s\n' "$LOG_FILE"
printf '============================================================\n'

[[ "$LOCAL_HEALTH" == "200" ]] || { echo "ERRO: health local falhou"; exit 40; }
[[ "$ORIGIN_HEALTH" == "200" ]] || { echo "ERRO: health da origem falhou"; exit 41; }
[[ "$ORIGIN_HOME" =~ ^(200|301|302)$ ]] || { echo "ERRO: home da origem falhou"; exit 42; }

echo "ORIGIN_BELASTOCK=100%_OK"
if [[ "$PUBLIC_HEALTH" == "200" && "$PUBLIC_HOME" =~ ^(200|301|302)$ ]]; then
  echo "PUBLICO_BELASTOCK=100%_OK"
else
  echo "PUBLICO_BELASTOCK=AGUARDANDO_DNS_OU_CAMADA_EXTERNA"
fi
echo "EXECUCAO_TOTAL_BELASTOCK=CONCLUIDA"
