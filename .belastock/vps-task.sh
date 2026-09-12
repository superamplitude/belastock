#!/usr/bin/env bash
set -Eeuo pipefail
SITE="/home/lojabelastock/htdocs/belastock.com.br"
for rel in \
  src/services/supplier-service.mjs \
  src/services/catalog-service.mjs \
  src/services/pricing-service.mjs \
  src/services/pricing-core.mjs \
  src/services/supplier-scoring.mjs \
  src/db.mjs \
  src/config.mjs \
  migrations/001_init.sql \
  scripts/migrate.mjs \
  public/admin.html \
  public/app.js; do
  echo "===== FILE: $rel ====="
  sed -n '1,500p' "$SITE/$rel" 2>/dev/null || true
  echo
 done
