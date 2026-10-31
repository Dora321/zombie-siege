#!/bin/bash
# 导出网页版并发布到 gh-pages 分支。每次覆盖成单个提交，避免 wasm 撑大仓库历史。
set -euo pipefail
cd "$(dirname "$0")/.."
REMOTE=$(git remote get-url origin)
NAME=$(git config user.name)
EMAIL=$(git config user.email)

mkdir -p build/web
touch build/.gdignore
rm -rf build/web
mkdir build/web
godot --headless --path . --export-release "Web" build/web/index.html
touch build/web/.nojekyll

cd build/web
git init -q -b gh-pages
git add -A
git -c user.name="$NAME" -c user.email="$EMAIL" commit -q -m "Deploy web build

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -q -f "$REMOTE" gh-pages
rm -rf .git
