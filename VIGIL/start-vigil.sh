#!/usr/bin/env sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if ! command -v node >/dev/null 2>&1; then
  echo 'Node.js was not found. Install Node.js 20.19+ or 22.12+ LTS, then run this file again.' >&2
  exit 1
fi
exec node scripts/serve.mjs "$@"
