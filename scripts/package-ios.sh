#!/usr/bin/env bash
# 构建可安装的 Sonar IPA（未签名，交给 vphoned / 侧载工具重签）。
#
#   ./scripts/package-ios.sh                 # 含 Widget 扩展
#   ./scripts/package-ios.sh --no-widget     # 去掉 Widget 扩展（VPhone 虚拟机用）
#   ./scripts/package-ios.sh --out=/path/to/Sonar.ipa
#
# 为什么需要 --no-widget：
#   VPhone 虚拟机的 WidgetKit 渲染进程会让所有 widget 扩展在启动时崩溃
#   （Sonar、计算器、条码扫描器同样崩，堆栈都在 WidgetBodyAccessor 里），
#   属于环境限制而不是 Sonar 代码问题。虚拟机内安装时去掉扩展可以避免
#   反复崩溃与通知。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/build/Sonar.ipa}"
DERIVED="${DERIVED:-$ROOT/build/ios-ipa}"
INCLUDE_WIDGET=1

for arg in "$@"; do
  case "$arg" in
    --no-widget) INCLUDE_WIDGET=0 ;;
    --out=*) OUT="${arg#*=}" ;;
    --derived=*) DERIVED="${arg#*=}" ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

case "$OUT" in
  /*) ;;
  *) OUT="$ROOT/$OUT" ;;
esac
mkdir -p "$(dirname "$OUT")"

echo "==> building Release for generic/platform=iOS"
xcodebuild \
  -project "$ROOT/Sonar.xcodeproj" \
  -scheme Sonar \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= \
  build >/dev/null

APP="$DERIVED/Build/Products/Release-iphoneos/Sonar.app"
[[ -d "$APP" ]] || { echo "missing $APP" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/Sonar.app"

if [[ "$INCLUDE_WIDGET" -eq 0 ]]; then
  rm -rf "$STAGE/Payload/Sonar.app/PlugIns"
  echo "==> dropped PlugIns (widget extension)"
fi

rm -f "$OUT"
( cd "$STAGE" && zip -qry "$OUT" Payload )

SIZE=$(stat -f%z "$OUT")
SHA=$(shasum -a 256 "$OUT" | awk '{print $1}')
echo "ipa:    $OUT"
echo "size:   $SIZE bytes"
echo "sha256: $SHA"
