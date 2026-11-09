#!/bin/sh
# 把最新的 macOS 发行包同步进 R2 镜像，供 https://sonar.bobochang.cn/SonarMac.dmg 使用。
#
# 用法：
#   export CLOUDFLARE_API_TOKEN=...   # 需要 R2 写权限，令牌不要提交
#   ./install/upload-mirror.sh [tag]  # 默认 latest
#
# 为什么需要这一步：GitHub 的 /releases/download 边缘偶发 504，Worker 直接回源并不可靠，
# 因此镜像以 R2 为准，GitHub 只作为兜底。
set -eu

TAG="${1:-latest}"
BUCKET="sonar-mirror"
REPO="can4hou6joeng4/Sonar"

[ -n "${CLOUDFLARE_API_TOKEN:-}" ] || {
  echo "✗ 需要 CLOUDFLARE_API_TOKEN（R2 写权限）" >&2
  exit 1
}

wrangler_cli() {
  if [ -n "${WRANGLER:-}" ]; then
    "$WRANGLER" "$@"
  elif command -v wrangler >/dev/null 2>&1; then
    wrangler "$@"
  else
    npx -y wrangler@4 "$@"
  fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "→ 从 GitHub 取 $TAG 的 SonarMac.dmg"
# gh 走 API 资源接口，比网页的 /releases/download 稳定（后者在部分区域会间歇 504）。
if command -v gh >/dev/null 2>&1; then
  if [ "$TAG" = "latest" ]; then
    gh release download -R "$REPO" -p SonarMac.dmg -D "$WORK" --clobber
  else
    gh release download "$TAG" -R "$REPO" -p SonarMac.dmg -D "$WORK" --clobber
  fi
else
  curl -fL --retry 5 --retry-all-errors --retry-delay 3 -o "$WORK/SonarMac.dmg" \
    "https://github.com/$REPO/releases/$TAG/download/SonarMac.dmg"
fi
(cd "$WORK" && shasum -a 256 SonarMac.dmg > SonarMac.dmg.sha256)

echo "→ 上传到 R2（${BUCKET}）"
wrangler_cli r2 object put "$BUCKET/releases/SonarMac.dmg" \
  --file="$WORK/SonarMac.dmg" --content-type=application/x-apple-diskimage --remote >/dev/null
wrangler_cli r2 object put "$BUCKET/releases/SonarMac.dmg.sha256" \
  --file="$WORK/SonarMac.dmg.sha256" --content-type=text/plain --remote >/dev/null

echo "→ 校验线上镜像"
REMOTE="$(curl -fsL "https://sonar.bobochang.cn/SonarMac.dmg.sha256" | awk '{print $1}')"
LOCAL="$(awk '{print $1}' "$WORK/SonarMac.dmg.sha256")"
if [ "$REMOTE" != "$LOCAL" ]; then
  echo "✗ 镜像校验不一致：$REMOTE ≠ $LOCAL" >&2
  exit 1
fi
echo "✓ 镜像已更新：$LOCAL"
