#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
DERIVED_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sonar-mac-derived.XXXXXX")"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sonar-mac-stage.XXXXXX")"

cleanup() {
  rm -rf "${DERIVED_DIR}" "${STAGE_DIR}"
}
trap cleanup EXIT

echo "==> 正在编译 SonarMac (Release)..."
xcodebuild -project "${PROJECT_ROOT}/Sonar.xcodeproj" \
  -scheme SonarMac \
  -configuration Release \
  -derivedDataPath "${DERIVED_DIR}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build

APP_PATH="${DERIVED_DIR}/Build/Products/Release/SonarMac.app"

if [ ! -d "${APP_PATH}" ]; then
  echo "错误: 未找到构建产物 ${APP_PATH}" >&2
  exit 1
fi

mkdir -p "${BUILD_DIR}"

echo "==> 正在打包 SonarMac.zip..."
(cd "${DERIVED_DIR}/Build/Products/Release" && zip -qry "${BUILD_DIR}/SonarMac.zip" "SonarMac.app")
shasum -a 256 "${BUILD_DIR}/SonarMac.zip" > "${BUILD_DIR}/SonarMac.zip.sha256"

echo "==> 正在生成 SonarMac.dmg..."
DMG_PATH="${BUILD_DIR}/SonarMac.dmg"
rm -f "${DMG_PATH}" "${DMG_PATH}.sha256"

# 准备 DMG 内容
cp -R "${APP_PATH}" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"

hdiutil create -volname "Sonar" -srcfolder "${STAGE_DIR}" -ov -format UDZO "${DMG_PATH}"
shasum -a 256 "${DMG_PATH}" > "${DMG_PATH}.sha256"

echo ""
echo "=================================================="
echo " 恭喜！macOS 打包已顺利完成："
echo " DMG 安装包: ${DMG_PATH}"
echo " ZIP 压缩包: ${BUILD_DIR}/SonarMac.zip"
echo "=================================================="
echo "普通 Mac 用户首次运行若遇到安全提示，可在终端执行："
echo "  xattr -cr /Applications/SonarMac.app"
echo "=================================================="
