#!/usr/bin/env bash
#
# assemble.sh — Clones all repos from games.yaml, builds each,
# and assembles into a single static directory tree.
#
# Requires: yq, node (18+), npm, git
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$ROOT_DIR/games.yaml"
ASSEMBLED="$ROOT_DIR/assembled"
WORK="$ROOT_DIR/.work"

# Auth prefix — set GH_TOKEN for private repos
if [ -n "${GH_TOKEN:-}" ]; then
  CLONE_PREFIX="https://x-access-token:${GH_TOKEN}@github.com/"
else
  CLONE_PREFIX="https://github.com/"
fi

NODE_VERSION=$(node --version)
echo "==> Node: $NODE_VERSION"
echo "==> Manifest: $MANIFEST"

# Clean previous runs
rm -rf "$ASSEMBLED" "$WORK"
mkdir -p "$ASSEMBLED" "$WORK"

# ─── Main site ───────────────────────────────────────────────

MAIN_REPO=$(yq -r '.main_site.repo' "$MANIFEST")
MAIN_BUILD_CMD=$(yq -r '.main_site.build_cmd' "$MANIFEST")
MAIN_DIST_DIR=$(yq -r '.main_site.dist_dir' "$MANIFEST")

echo ""
echo "==> [main-site] Cloning $MAIN_REPO"
git clone --depth 1 "${CLONE_PREFIX}${MAIN_REPO}.git" "$WORK/main-site"

echo "==> [main-site] Installing dependencies"
cd "$WORK/main-site"
npm ci

echo "==> [main-site] Building ($MAIN_BUILD_CMD)"
$MAIN_BUILD_CMD

echo "==> [main-site] Copying $MAIN_DIST_DIR/ -> assembled/"
cp -r "$MAIN_DIST_DIR"/* "$ASSEMBLED/"

# ─── Game scenes ─────────────────────────────────────────────

GAME_COUNT=$(yq '.games | length' "$MANIFEST")
echo ""
echo "==> Found $GAME_COUNT game(s) in manifest"

for i in $(seq 0 $((GAME_COUNT - 1))); do
  NUMBER=$(yq ".games[$i].number" "$MANIFEST")
  REPO=$(yq -r ".games[$i].repo" "$MANIFEST")
  BUILD_CMD=$(yq -r ".games[$i].build_cmd" "$MANIFEST")
  DIST_DIR=$(yq -r ".games[$i].dist_dir" "$MANIFEST")

  echo ""
  echo "==> [game-$NUMBER] Cloning $REPO"
  git clone --depth 1 "${CLONE_PREFIX}${REPO}.git" "$WORK/game-$NUMBER"

  echo "==> [game-$NUMBER] Installing dependencies"
  cd "$WORK/game-$NUMBER"
  npm ci

  echo "==> [game-$NUMBER] Building ($BUILD_CMD)"
  $BUILD_CMD

  echo "==> [game-$NUMBER] Copying $DIST_DIR/ -> assembled/doors/$NUMBER/"
  mkdir -p "$ASSEMBLED/doors/$NUMBER"
  cp -r "$DIST_DIR"/* "$ASSEMBLED/doors/$NUMBER/"
done

# ─── Summary ─────────────────────────────────────────────────

echo ""
echo "==> Assembly complete."
echo "==> Directory tree (top-level):"
ls -la "$ASSEMBLED/"
echo ""
echo "==> Total files:"
find "$ASSEMBLED" -type f | wc -l
