#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARTS="$REPO_ROOT/deploy/runtime/home-hero-v31/assets-pack/hero-assets.zip.b64.part*"
TMP_B64="$(mktemp)"
TMP_ZIP="$(mktemp)"
trap 'rm -f "$TMP_B64" "$TMP_ZIP"' EXIT
cat $PARTS > "$TMP_B64"
base64 -d "$TMP_B64" > "$TMP_ZIP"
echo "HERO_ASSET_ZIP_SHA256=$(sha256sum "$TMP_ZIP" | awk '{print $1}')"
unzip -l "$TMP_ZIP"
python3 - "$TMP_ZIP" <<'PY'
import sys,zipfile
p=sys.argv[1]
with zipfile.ZipFile(p) as z:
    print('ZIP_TEST=', z.testzip())
    print('ZIP_NAMES=', ','.join(z.namelist()))
PY
