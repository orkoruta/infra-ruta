#!/usr/bin/env bash
# Clona un landing existente en frontend-clients-ruta/.
# Uso: bash clone_landing.sh <slug> [base_dir]
# Ejemplo: bash clone_landing.sh restaurante-el-prado

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../workspace.config.json"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq es requerido. Instálalo con: sudo apt install jq" >&2
  exit 1
fi

SLUG="${1:-}"
if [ -z "$SLUG" ]; then
  echo "Uso: bash clone_landing.sh <slug> [base_dir]" >&2
  exit 1
fi

GITHUB_ORG=$(jq -r '.github_org' "$CONFIG")
BASE_DIR="${2:-$(jq -r '.base_dir' "$CONFIG")}"
BASE_DIR="${BASE_DIR/#\~/$HOME}"
DEST="$BASE_DIR/frontend-clients-ruta/$SLUG"

if [ -d "$DEST/.git" ]; then
  echo "✓ landing-$SLUG ya existe en $DEST, actualizando"
  git -C "$DEST" pull --ff-only
else
  echo "↓ Clonando landing-$SLUG  →  $DEST"
  git clone "git@github.com:$GITHUB_ORG/landing-$SLUG.git" "$DEST"
  echo "✅ Landing clonado en $DEST"
fi
