#!/usr/bin/env bash
set -Eeuo pipefail
SITE="/home/lojabelastock/htdocs/belastock.com.br"
echo "BELA_STOCK_SECURITY_DIAGNOSTIC"
sudo -n -u lojabelastock -H bash -lc "echo '--- config.mjs'; sed -n '1,240p' '$SITE/src/config.mjs'; echo '--- crypto.mjs'; sed -n '1,260p' '$SITE/src/security/crypto.mjs'; echo '--- env key names only'; cut -d= -f1 '$SITE/.env' | sed '/^[[:space:]]*$/d' | sort -u"
