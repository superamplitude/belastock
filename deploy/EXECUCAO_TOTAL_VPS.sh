#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

APP_DIR="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
APP_GROUP="lojabelastock"
SITE_DOMAIN="belastock.com.br"
VHOST="/etc/nginx/sites-enabled/belastock.com.br.conf"
BACKUP_ROOT="/home/lojabelastock/backups"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/pre-node-$STAMP"
BUNDLE_URL="https://raw.githubusercontent.com/superamplitude/belastock/main/dist/BELASTOCK_NODE_V2_EXECUCAO_TOTAL.zip"
BUNDLE_SHA256="deba72261bd1f63a5e525cb7903cecd80583a54089575602ba3af351768575b7"
TMP_ZIP="/tmp/BELASTOCK_NODE_V2_EXECUCAO_TOTAL.zip"
TMP_DIR="/tmp/belastock-node-$STAMP"
DB_NAME="belastock_node"
DB_USER="belastock_node"
APP_PORT="3210"
CRED_FILE="/root/BELASTOCK_CREDENTIALS_${STAMP}.txt"
MYSQL_ADMIN_MODE=""

fail() {
  local code=$?
  echo
  echo "============================================================"
  echo "FALHA BELA STOCK - código $code - linha ${BASH_LINENO[0]}"
  echo "Backups: $BACKUP_DIR"
  echo "============================================================"
  exit "$code"
}
trap fail ERR

[[ $EUID -eq 0 ]] || { echo "Execute como root"; exit 1; }
id "$APP_USER" >/dev/null 2>&1 || { echo "Usuário $APP_USER não existe"; exit 1; }

printf '\n============================================================\n'
printf ' BELA STOCK NODE 2.0 - EXECUÇÃO TOTAL\n'
printf ' %s\n' "$(date -Is)"
printf '============================================================\n\n'

# 1) Pré-validação antes de alterar o servidor
command -v mysql >/dev/null || { echo "MySQL client ausente"; exit 2; }
command -v nginx >/dev/null || { echo "Nginx ausente"; exit 2; }

# CloudPanel protege o root do MySQL com senha. Nunca assume root sem senha.
if mysql -NBe 'SELECT 1' >/dev/null 2>&1; then
  MYSQL_ADMIN_MODE="socket-root"
elif command -v clpctl >/dev/null 2>&1 && clpctl db:show:master-credentials >/dev/null 2>&1; then
  MYSQL_ADMIN_MODE="cloudpanel"
else
  echo "Não foi possível obter um método administrativo seguro para o MySQL."
  echo "Nem root via socket nem CloudPanel clpctl estão disponíveis."
  exit 3
fi

echo "MySQL admin mode: $MYSQL_ADMIN_MODE"
[[ -f /etc/nginx/ssl-certificates/belastock.com.br.crt ]] || { echo "Certificado SSL não encontrado"; exit 4; }
[[ -f /etc/nginx/ssl-certificates/belastock.com.br.key ]] || { echo "Chave SSL não encontrada"; exit 4; }

# 2) Backup restaurável
mkdir -p "$BACKUP_DIR" "$APP_DIR"
if [[ -n "$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  tar -C "$(dirname "$APP_DIR")" -czf "$BACKUP_DIR/site.tar.gz" "$(basename "$APP_DIR")"
else
  printf 'Diretório estava vazio em %s\n' "$(date -Is)" > "$BACKUP_DIR/site-was-empty.txt"
fi
[[ -f "$VHOST" ]] && cp -a "$VHOST" "$BACKUP_DIR/belastock.com.br.conf.before"
printf 'mysql_admin_mode=%s\n' "$MYSQL_ADMIN_MODE" > "$BACKUP_DIR/mysql-admin-mode.txt"
if [[ "$MYSQL_ADMIN_MODE" == "socket-root" ]]; then
  mysql -NBe "SHOW DATABASES" > "$BACKUP_DIR/mysql-databases.before.txt" 2>/dev/null || true
else
  # Não grava credenciais-mestre do CloudPanel em backup/log.
  printf 'CloudPanel master credentials intentionally not exported.\n' > "$BACKUP_DIR/mysql-databases.before.txt"
fi
nginx -T > "$BACKUP_DIR/nginx-T.before.txt" 2>&1 || true
ss -lntup > "$BACKUP_DIR/ports.before.txt" 2>&1 || true

# 3) Dependências do runtime
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends nodejs npm git unzip curl ca-certificates rsync openssl sudo >/dev/null
NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
if (( NODE_MAJOR < 20 )); then
  echo "Node.js $(node -v) é antigo. Necessário >=20. Abortando sem trocar o vhost."
  exit 5
fi
if ! command -v pm2 >/dev/null; then
  npm install -g pm2@latest >/dev/null
fi

# 4) Obtém pacote versionado e verifica integridade
rm -rf "$TMP_DIR" "$TMP_ZIP"
mkdir -p "$TMP_DIR"
curl -fL --retry 3 --connect-timeout 15 "$BUNDLE_URL" -o "$TMP_ZIP"
echo "$BUNDLE_SHA256  $TMP_ZIP" | sha256sum -c -
unzip -q "$TMP_ZIP" -d "$TMP_DIR"
[[ -f "$TMP_DIR/belastock-node/package.json" ]] || { echo "Bundle inválido"; exit 6; }

# 5) Publica código sem destruir .env existente
EXISTING_ENV=""
if [[ -f "$APP_DIR/.env" ]]; then
  EXISTING_ENV="$BACKUP_DIR/.env.before"
  cp -a "$APP_DIR/.env" "$EXISTING_ENV"
fi
rsync -a --delete --exclude='.env' "$TMP_DIR/belastock-node/" "$APP_DIR/"

# 6) Credenciais locais e banco. Nunca envia segredos ao GitHub.
if [[ -z "$EXISTING_ENV" ]]; then
  DB_PASS="$(openssl rand -hex 24)"
  MASTER_KEY="$(openssl rand -base64 32 | tr -d '\n')"
  ADMIN_TOKEN="$(openssl rand -hex 40)"

  cat > "$APP_DIR/.env" <<EOF
NODE_ENV=production
HOST=127.0.0.1
PORT=$APP_PORT
APP_URL=https://belastock.com.br
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS
CREDENTIALS_MASTER_KEY=$MASTER_KEY
ADMIN_TOKEN=$ADMIN_TOKEN
AI_PROVIDER=disabled
AI_BASE_URL=
AI_API_KEY=
AI_MODEL=
AI_AUTONOMY_MODE=automatic
AI_CYCLE_INTERVAL_SECONDS=300
LEGACY_DB_HOST=127.0.0.1
LEGACY_DB_PORT=3306
LEGACY_DB_NAME=belastock_legacy
LEGACY_DB_USER=
LEGACY_DB_PASSWORD=
EOF

  if [[ "$MYSQL_ADMIN_MODE" == "socket-root" ]]; then
    mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
  else
    # CloudPanel v2: cria banco + usuário através da CLI oficial, sem revelar master password.
    clpctl db:add \
      --domainName="$SITE_DOMAIN" \
      --databaseName="$DB_NAME" \
      --databaseUserName="$DB_USER" \
      --databaseUserPassword="$DB_PASS"
  fi

  cat > "$CRED_FILE" <<EOF
BELA STOCK NODE 2.0
Criado: $(date -Is)
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS
ADMIN_TOKEN=$ADMIN_TOKEN
CREDENTIALS_MASTER_KEY=$MASTER_KEY
OBS: AI_PROVIDER está desabilitado até inserir credenciais de um provedor compatível. O orquestrador determinístico continua ativo.
EOF
  chmod 600 "$CRED_FILE"
else
  echo "Mantendo .env existente."
fi

chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"
chmod 640 "$APP_DIR/.env"
find "$APP_DIR" -type d -exec chmod 750 {} +

# 7) Dependências, testes, migrations
cd "$APP_DIR"
npm install --omit=dev
npm run check
npm run migrate

# 8) Processo Node como usuário da aplicação
chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"
sudo -u "$APP_USER" -H bash -lc "cd '$APP_DIR' && pm2 delete belastock >/dev/null 2>&1 || true; pm2 start ecosystem.config.cjs; pm2 save"
pm2 startup systemd -u "$APP_USER" --hp "/home/$APP_USER" >/dev/null 2>&1 || true

# Só troca o Nginx depois do Node estar comprovadamente saudável
for i in {1..20}; do
  if curl -fsS "http://127.0.0.1:$APP_PORT/health" >/tmp/belastock-health.json; then break; fi
  sleep 1
done
curl -fsS "http://127.0.0.1:$APP_PORT/health" | tee "$BACKUP_DIR/health-local.json"

# 9) Vhost exclusivo de belastock.com.br. Não toca loja.belastock.com.br.
cat > "$VHOST.new" <<'NGINX'
server {
    listen 80;
    listen [::]:80;
    server_name belastock.com.br www.belastock.com.br;
    return 301 https://belastock.com.br$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name www.belastock.com.br;

    ssl_certificate /etc/nginx/ssl-certificates/belastock.com.br.crt;
    ssl_certificate_key /etc/nginx/ssl-certificates/belastock.com.br.key;

    return 301 https://belastock.com.br$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name belastock.com.br;

    ssl_certificate /etc/nginx/ssl-certificates/belastock.com.br.crt;
    ssl_certificate_key /etc/nginx/ssl-certificates/belastock.com.br.key;

    access_log /home/lojabelastock/logs/nginx/access.log main;
    error_log /home/lojabelastock/logs/nginx/error.log;
    client_max_body_size 25m;

    location / {
        proxy_pass http://127.0.0.1:3210;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_read_timeout 90s;
        proxy_connect_timeout 10s;
    }
}
NGINX

cp "$VHOST.new" "$VHOST"
rm -f "$VHOST.new"
if ! nginx -t; then
  echo "Nginx rejeitou o novo vhost. Restaurando backup."
  [[ -f "$BACKUP_DIR/belastock.com.br.conf.before" ]] && cp -a "$BACKUP_DIR/belastock.com.br.conf.before" "$VHOST"
  nginx -t && systemctl reload nginx
  exit 7
fi
systemctl reload nginx

# 10) Validação ponta-a-ponta
sleep 2
ORIGIN_STATUS="$(curl -k -sS -o "$BACKUP_DIR/origin-health.json" -w '%{http_code}' --resolve belastock.com.br:443:127.0.0.1 https://belastock.com.br/health || true)"
PUBLIC_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' https://belastock.com.br/health || true)"
PUBLIC_LOCATION="$(curl -sSI https://belastock.com.br/ 2>/dev/null | awk 'BEGIN{IGNORECASE=1}/^location:/{print $2}' | tr -d '\r' | head -1)"

sudo -u "$APP_USER" -H pm2 status belastock || true

# Valida o banco com o usuário da própria aplicação; não usa root/master credentials.
set -a
# shellcheck disable=SC1091
source "$APP_DIR/.env"
set +a
MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -NBe \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" \
  | tee "$BACKUP_DIR/db-table-count.txt"
unset MYSQL_PWD

printf '\n============================================================\n'
printf ' BELA STOCK - RESULTADO FINAL\n'
printf '============================================================\n'
printf 'MySQL admin: %s\n' "$MYSQL_ADMIN_MODE"
printf 'Node: %s\n' "$(node -v)"
printf 'npm: %s\n' "$(npm -v)"
printf 'PM2: %s\n' "$(pm2 -v)"
printf 'Local health: OK\n'
printf 'Origin HTTPS /health: %s\n' "$ORIGIN_STATUS"
printf 'Public HTTPS /health: %s\n' "$PUBLIC_STATUS"
printf 'Public redirect: %s\n' "${PUBLIC_LOCATION:-nenhum}"
printf 'App: %s\n' "$APP_DIR"
printf 'Backup: %s\n' "$BACKUP_DIR"
printf 'Credenciais locais: %s\n' "$CRED_FILE"
printf 'Git bundle SHA256: %s\n' "$BUNDLE_SHA256"
printf '============================================================\n'

if [[ "$ORIGIN_STATUS" != "200" ]]; then
  echo "ATENÇÃO: aplicação está localmente viva, mas o HTTPS no origin não retornou 200."
  exit 8
fi

if [[ "$PUBLIC_STATUS" != "200" ]]; then
  echo "ATENÇÃO: origin está saudável, mas Cloudflare/DNS público ainda não retorna 200 em /health."
  echo "Isso normalmente indica regra de redirecionamento/cache na camada Cloudflare, não falha do Node."
fi

echo "EXECUCAO_TOTAL_BELASTOCK=CONCLUIDA"
