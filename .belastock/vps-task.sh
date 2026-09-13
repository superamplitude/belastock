#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(pwd)"
CONTROL="/usr/local/sbin/belastock-vps-control"
SITE="/home/lojabelastock/htdocs/belastock.com.br"
E2E="$ROOT/.belastock/validate-v30-e2e.mjs"
DB_AUDIT="$ROOT/.belastock/final-adversarial-audit.mjs"
PM2="/home/lojabelastock/.local/bin/pm2"
PM2_HOME="/home/lojabelastock/.pm2"

echo "============================================================"
echo " BELA STOCK 3.0 - FINAL POST-HARDENING PRODUCTION AUDIT"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

sudo -n "$CONTROL" db-test
sudo -n "$CONTROL" health
sudo -n "$CONTROL" pm2-service-ensure

PKG_VERSION="$(node -p "require('$SITE/package.json').version")"
echo "PACKAGE_VERSION=$PKG_VERSION"
test "$PKG_VERSION" = "3.0.0"

ENV_MODE="$(stat -c '%a' "$SITE/.env")"
ENV_OWNER="$(stat -c '%U:%G' "$SITE/.env")"
echo "ENV_MODE=$ENV_MODE"
echo "ENV_OWNER=$ENV_OWNER"
test "$ENV_OWNER" = "lojabelastock:lojabelastock"
test "${ENV_MODE: -1}" = "0"
echo "ENV_WORLD_ACCESS=NONE"

systemctl is-active --quiet pm2-lojabelastock
echo "PM2_SYSTEMD_ACTIVE=YES"
systemctl is-enabled --quiet pm2-lojabelastock
echo "PM2_SYSTEMD_ENABLED=YES"
sudo -n -u lojabelastock -H env PM2_HOME="$PM2_HOME" "$PM2" jlist > /tmp/bs-final-pm2.json
node --input-type=module - <<'NODE'
import fs from 'node:fs';
const list=JSON.parse(fs.readFileSync('/tmp/bs-final-pm2.json','utf8'));
const app=list.find(x=>x.name==='belastock');
if(!app) throw new Error('PM2 belastock ausente');
console.log(`PM2_APP_STATUS=${app.pm2_env?.status}`);
console.log(`PM2_APP_VERSION=${app.pm2_env?.version}`);
if(app.pm2_env?.status!=='online'||app.pm2_env?.version!=='3.0.0') process.exit(3);
NODE
ss -lnt | grep -qE '127\.0\.0\.1:3210\b'
echo "PORT_3210_LOCAL_ONLY=YES"

sudo -n -u lojabelastock -H bash -lc "cd '$SITE' && npm run check && npm ls @fastify/rate-limit --depth=0 && npm audit --omit=dev --audit-level=high"

# Rate limit real no endpoint de login. Uma resposta 429 é obrigatória antes da 10ª tentativa.
RATE_LIMIT_SEEN=0
for i in $(seq 1 10); do
  code="$(curl -ksS --max-time 15 -o "/tmp/bs-rate-$i.json" -D "/tmp/bs-rate-$i.headers" -w '%{http_code}' \
    -H 'content-type: application/json' \
    --data '{"email":"security-audit-no-user@example.invalid","password":"invalid-audit-password"}' \
    https://belastock.com.br/api/customer/login || true)"
  echo "AUTH_RATE_LIMIT_ATTEMPT_${i}=$code"
  if [ "$code" = 429 ]; then RATE_LIMIT_SEEN=1; break; fi
  [ "$code" = 401 ] || { echo "Resposta inesperada no teste de rate limit"; cat "/tmp/bs-rate-$i.json" || true; exit 41; }
done
[ "$RATE_LIMIT_SEEN" = 1 ] || { echo "Rate limit não produziu HTTP 429"; exit 42; }
cat /tmp/bs-rate-*.headers | grep -qi '^retry-after:'
echo "AUTH_RATE_LIMIT_HTTP_429=OK"

sudo -n "$CONTROL" nginx-diagnose > /tmp/bs-final-nginx.txt || true
grep -Eq 'proxy_set_header[[:space:]]+X-Real-IP[[:space:]]+\$remote_addr' /tmp/bs-final-nginx.txt
echo "NGINX_REAL_IP_HEADER=TRUSTED_REMOTE_ADDR"

chmod o+r "$E2E" "$DB_AUDIT"
sudo -n -u lojabelastock -H node "$E2E"
sudo -n -u lojabelastock -H node "$DB_AUDIT"

check_code(){ local expected="$1" url="$2" file="$3" code; code="$(curl -ksS --max-time 25 -o "$file" -w '%{http_code}' "$url" || true)"; echo "$url -> $code"; test "$code" = "$expected"; }
check_code 200 https://belastock.com.br/ /tmp/bs-final-root.html
check_code 200 https://belastock.com.br/health /tmp/bs-final-health.json
check_code 200 https://belastock.com.br/admin /tmp/bs-final-admin.html
check_code 200 https://belastock.com.br/cliente /tmp/bs-final-cliente.html
check_code 200 https://belastock.com.br/parceiro /tmp/bs-final-parceiro.html
check_code 200 https://belastock.com.br/storefront.js /tmp/bs-final-storefront.js
check_code 200 https://belastock.com.br/operations.js /tmp/bs-final-operations.js
check_code 200 https://belastock.com.br/api/public/store /tmp/bs-final-store.json
check_code 200 https://belastock.com.br/api/public/products /tmp/bs-final-products.json
check_code 404 https://belastock.com.br/api/cart /tmp/bs-final-cart-empty.json
check_code 401 https://belastock.com.br/api/admin/completion /tmp/bs-final-admin-unauth.json
check_code 401 https://belastock.com.br/api/admin/orders /tmp/bs-final-orders-unauth.json
check_code 401 https://belastock.com.br/api/customer/panel /tmp/bs-final-customer-unauth.json
check_code 401 https://belastock.com.br/api/partner/panel /tmp/bs-final-partner-unauth.json
check_code 404 https://belastock.com.br/__final_audit_not_found__ /tmp/bs-final-404.json
WWW_CODE="$(curl -ksS --max-time 20 -o /dev/null -w '%{http_code}' https://www.belastock.com.br/ || true)"; echo "PUBLIC_WWW_HTTP=$WWW_CODE"; test "$WWW_CODE" = "301"

grep -q '"version":"3.0.0"' /tmp/bs-final-health.json
grep -q '"db":true' /tmp/bs-final-health.json
grep -q 'storefront.js' /tmp/bs-final-root.html
grep -q 'AI Commerce 3.0' /tmp/bs-final-admin.html
grep -q 'viewport' /tmp/bs-final-root.html
grep -q 'viewport' /tmp/bs-final-admin.html
grep -q 'viewport' /tmp/bs-final-cliente.html
grep -q 'viewport' /tmp/bs-final-parceiro.html
grep -q '"error":"not_found"' /tmp/bs-final-404.json

curl -ksS -D /tmp/bs-final-headers.txt -o /dev/null https://belastock.com.br/
tr -d '\r' < /tmp/bs-final-headers.txt | tr '[:upper:]' '[:lower:]' > /tmp/bs-final-headers-lower.txt
grep -q '^x-content-type-options: nosniff' /tmp/bs-final-headers-lower.txt
grep -q '^x-frame-options: deny' /tmp/bs-final-headers-lower.txt
grep -q '^referrer-policy: strict-origin-when-cross-origin' /tmp/bs-final-headers-lower.txt
grep -q '^permissions-policy:' /tmp/bs-final-headers-lower.txt
echo "SECURITY_HEADERS_BASELINE=OK"

CERT_END="$(echo | openssl s_client -connect belastock.com.br:443 -servername belastock.com.br 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2-)"
echo "TLS_CERT_NOT_AFTER=$CERT_END"
echo | openssl s_client -connect belastock.com.br:443 -servername belastock.com.br 2>/dev/null | openssl x509 -checkend 1209600 -noout
echo "TLS_CERT_VALID_GT_14_DAYS=YES"

VHOST_PROXY="$(awk '/===== VHOST CONTENT =====/{inside=1;next}/===== ACTIVE BELASTOCK CONFIG REFERENCES =====/{inside=0} inside && /proxy_pass http:\/\/127\.0\.0\.1:[0-9]+\//{print;exit}' /tmp/bs-final-nginx.txt | xargs)"
echo "VHOST_PROXY=$VHOST_PROXY"
echo "$VHOST_PROXY" | grep -q 'proxy_pass http://127.0.0.1:3210/'

node - "$SITE/package.json" <<'NODE'
const p=require(process.argv[2]);
console.log('FASTIFY_VERSION='+(p.dependencies?.fastify||'UNKNOWN'));
console.log('RATE_LIMIT_DEP='+(p.dependencies?.['@fastify/rate-limit']||'ABSENT'));
if(p.dependencies?.['@fastify/rate-limit']!=='11.2.0') process.exit(30);
NODE
grep -q "AUTH_RATE_LIMITS.customerLogin" "$SITE/src/server.mjs"
grep -q "AUTH_RATE_LIMITS.partnerLogin" "$SITE/src/server.mjs"
grep -q "AUTH_RATE_LIMITS.customerRegister" "$SITE/src/server.mjs"
echo "AUTH_RATE_LIMIT_CODE=PRESENT"

echo "SECOND_PASS_RUNTIME=100%_OK"
echo "SECOND_PASS_DATABASE_INTEGRITY=100%_OK"
echo "SECOND_PASS_E2E=100%_OK"
echo "SECOND_PASS_PM2_PERSISTENCE=100%_OK"
echo "SECOND_PASS_NGINX=100%_OK"
echo "SECOND_PASS_SECURITY_BASELINE=100%_OK"
echo "SECOND_PASS_AUTH_RATE_LIMIT=100%_OK"
echo "SECOND_PASS_REGRESSION=100%_OK"
echo "SECOND_PASS_AUDIT=CONCLUIDA"
echo "BELA_STOCK_V30_PRODUCTION_APPROVAL=APPROVED"
